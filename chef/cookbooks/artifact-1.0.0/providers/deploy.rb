#
# Cookbook Name:: artifact
# Provider:: deploy
#
# Author:: Jamie Winsor (<jamie@vialstudios.com>)
# Author:: Kyle Allan (<kallan@riotgames.com>)
# 
# Copyright 2013, Riot Games
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
require 'digest'
require 'pathname'
require 'uri'
require 'yaml'

attr_reader :release_path
attr_reader :current_path
attr_reader :shared_path
attr_reader :current_release_path
attr_reader :artifact_root
attr_reader :version_container_path
attr_reader :manifest_file
attr_reader :previous_version_paths
attr_reader :previous_version_numbers
attr_reader :artifact_location
attr_reader :artifact_version

def load_current_resource
  if latest?(@new_resource.version) && from_http?(@new_resource.artifact_location)
    Chef::Application.fatal! "You cannot specify the latest version for an artifact when attempting to download an artifact using http(s)!"
  end

  chef_gem "activesupport" do
    version "3.2.11"
  end

  if from_nexus?(@new_resource.artifact_location)
    %W{libxml2-devel libxslt-devel}.each do |nokogiri_requirement|
      package nokogiri_requirement do
        action :install
      end.run_action(:install)
    end

    chef_gem "nexus_cli" do
      version "2.0.2"
    end

    group_id, artifact_id, extension = @new_resource.artifact_location.split(':')
    @artifact_version = Chef::Artifact.get_actual_version(node, group_id, artifact_id, @new_resource.version, extension)
    @artifact_location = [group_id, artifact_id, artifact_version, extension].join(':')
  else
    @artifact_version = @new_resource.version
    @artifact_location = @new_resource.artifact_location
  end

  @release_path             = get_release_path
  @current_path             = @new_resource.current_path
  @shared_path              = @new_resource.shared_path
  @artifact_root            = ::File.join(@new_resource.artifact_deploy_path, @new_resource.name)
  @version_container_path   = ::File.join(@artifact_root, artifact_version)
  @current_release_path     = get_current_release_path
  @previous_version_paths   = get_previous_version_paths
  @previous_version_numbers = get_previous_version_numbers
  @manifest_file            = ::File.join(@release_path, "manifest.yaml")
  @deploy                   = false
  @current_resource         = Chef::Resource::ArtifactDeploy.new(@new_resource.name)

  @current_resource
end

action :deploy do
  delete_previous_versions(:keep => new_resource.keep)
  setup_deploy_directories!
  setup_shared_directories!

  @deploy = manifest_differences?

  retrieve_artifact!

  run_proc :before_deploy

  if deploy?
    run_proc :before_extract
    if new_resource.is_tarball
      extract_artifact
    else
      copy_artifact
    end
    run_proc :after_extract

    run_proc :before_symlink
    symlink_it_up!
    run_proc :after_symlink
  end

  run_proc :configure

  if deploy? && new_resource.should_migrate
    run_proc :before_migrate
    run_proc :migrate
    run_proc :after_migrate
  end

  if deploy? || manifest_differences? || current_symlink_changing?
    run_proc :restart
  end

  run_proc :after_deploy

  recipe_eval do
    link new_resource.current_path do
      to release_path
      user new_resource.owner
      group new_resource.group
    end
  end

  recipe_eval { write_manifest }

  new_resource.updated_by_last_action(true)
end

action :pre_seed do
  setup_deploy_directories!
  retrieve_artifact!
end

# Extracts the artifact defined in the resource call. Handles
# a variety of 'tar' based files (tar.gz, tgz, tar, tar.bz2, tbz)
# and a few 'zip' based files (zip, war, jar).
# 
# @return [void]
def extract_artifact
  recipe_eval do
    case ::File.extname(cached_tar_path)
    when /tar.gz|tgz|tar|tar.bz2|tbz/
      execute "extract_artifact" do
        command "tar xf #{cached_tar_path} -C #{release_path}"
        user new_resource.owner
        group new_resource.group
      end
    when /zip|war|jar/
      package "unzip"
      execute "extract_artifact" do
        command "unzip -q -u -o #{cached_tar_path} -d #{release_path}"
        user new_resource.owner
        group new_resource.group
      end
    else
      Chef::Application.fatal! "Cannot extract artifact because of its extension. Supported types are"
    end
  end
end

# Copies the artifact from its cached path to its release path. The cached path is
# the configured Chef::Config[:file_cache_path]/artifact_deploys
# 
# @example
#   cp /tmp/vagrant-chef-1/artifact_deploys/artifact_test/1.0.0/my-artifact.zip /srv/artifact_test/releases/1.0.0
# 
# @return [void]
def copy_artifact
  recipe_eval do
    execute "copy artifact" do
      command "cp #{cached_tar_path} #{release_path}"
      user new_resource.owner
      group new_resource.group
    end
  end
end

# Returns the file path to the cached artifact the resource is installing.
# 
# @return [String] the path to the cached artifact
def cached_tar_path
  ::File.join(version_container_path, artifact_filename)
end

# Returns the filename of the artifact being installed when the LWRP
# is called. Depending on how the resource is called in a recipe, the
# value returned by this method will change. If from_nexus?, return the
# concatination of "artifact_id-version.extension" otherwise return the
# basename of where the artifact is located.
# 
# @example
#   When: new_resource.artifact_location => "com.artifact:my-artifact:1.0.0:tgz"
#     artifact_filename => "my-artifact-1.0.0.tgz"
#   When: new_resource.artifact_location => "http://some-site.com/my-artifact.jar"
#     artifact_filename => "my-artifact.jar"
# 
# @return [String] the artifacts filename
def artifact_filename
  if from_nexus?(new_resource.artifact_location)    
    group_id, artifact_id, version, extension = artifact_location.split(":")
    unless extension
      extension = "jar"
    end
   "#{artifact_id}-#{version}.#{extension}"
  else
    ::File.basename(artifact_location)
  end
end

private

  # A wrapper that adds debug logging for running a recipe_eval on the 
  # numerous Proc attributes defined for this resource.
  # 
  # @param name [Symbol] the name of the proc to execute
  # 
  # @return [void]
  def run_proc(name)
    proc = new_resource.send(name)
    proc_name = name.to_s
    Chef::Log.info "artifact_deploy[run_proc::#{proc_name}] Determining whether to execute #{proc_name} proc."
    if proc
      Chef::Log.debug "artifact_deploy[run_proc::#{proc_name}] Beginning execution of #{proc_name} proc."
      recipe_eval(&proc)
      Chef::Log.debug "artifact_deploy[run_proc::#{proc_name}] Ending execution of #{proc_name} proc."
    else
      Chef::Log.info "artifact_deploy[run_proc::#{proc_name}] Skipping execution of #{proc_name} proc because it was not defined."
    end
  end

  # Deletes released versions of the artifact when the number of 
  # released versions exceeds the :keep value.
  #
  # @param [Hash] options
  #
  # @option options [Integer] :keep
  #   the number of releases to keep
  # 
  # @return [type] [description]
  def delete_previous_versions(options = {})
    recipe_eval do
      ruby_block "delete_previous_versions" do
        block do
          def delete_cached_files_for(version)
            FileUtils.rm_rf ::File.join(artifact_root, version)
          end

          def delete_release_path_for(version)
            FileUtils.rm_rf ::File.join(new_resource.deploy_to, 'releases', version)
          end

          keep = options[:keep] || 0
          delete_first = total = previous_version_paths.length

          if total == 0 || total <= keep
            true
          else
            delete_first -= keep

            Chef::Log.info "artifact_deploy[delete_previous_versions] is deleting #{delete_first} of #{total} old versions (keeping: #{keep})"

            to_delete = previous_version_paths.shift(delete_first)

            to_delete.each do |version|
              delete_cached_files_for(version.basename)
              delete_release_path_for(version.basename)
              Chef::Log.info "artifact_deploy[delete_previous_versions] #{version.basename} deleted"
            end
          end
        end
      end
    end
  end

  # Checks the various cases of whether an artifact has or has not been installed. If the artifact
  # has been installed let #has_manifest_changed? determine the return value.
  # 
  # @return [Boolean]
  def manifest_differences?
    if new_resource.force
      Chef::Log.info "artifact_deploy[manifest_differences?] Force attribute has been set for #{new_resource.name}."
      Chef::Log.info "artifact_deploy[manifest_differences?] Installing version, #{artifact_version} for #{new_resource.name}."
      return true
    elsif get_current_release_version.nil?
      Chef::Log.info "artifact_deploy[manifest_differences?] No current version installed for #{new_resource.name}."
      Chef::Log.info "artifact_deploy[manifest_differences?] Installing version, #{artifact_version} for #{new_resource.name}."
      return true
    elsif artifact_version != get_current_release_version && !previous_version_numbers.include?(artifact_version)
      Chef::Log.info "artifact_deploy[manifest_differences?] Currently installed version of artifact is #{get_current_release_version}."
      Chef::Log.info "artifact_deploy[manifest_differences?] Version #{artifact_version} for #{new_resource.name} has not already been installed."
      Chef::Log.info "artifact_deploy[manifest_differences?] Installing version, #{artifact_version} for #{new_resource.name}."
      return true
    elsif artifact_version != get_current_release_version && previous_version_numbers.include?(artifact_version)
      Chef::Log.info "artifact_deploy[manifest_differences?] Version #{artifact_version} of artifact has already been installed."
      return has_manifest_changed?
    elsif artifact_version == get_current_release_version
      Chef::Log.info "artifact_deploy[manifest_differences?] Currently installed version of artifact is #{artifact_version}."
      return has_manifest_changed?
    end
  end

  # Loads the saved manifest.yaml file and generates a new, current manifest. The
  # saved manifest is then parsed through looking for files that may have been deleted,
  # added, or modified.
  # 
  # @return [Boolean]
  def has_manifest_changed?
    require 'active_support/core_ext/hash'

    Chef::Log.info "artifact_deploy[has_manifest_changed?] Loading manifest.yaml file from directory: #{release_path}"
    begin
      saved_manifest = YAML.load_file(::File.join(release_path, "manifest.yaml"))
    rescue Errno::ENOENT
      Chef::Log.warn "artifact_deploy[has_manifest_changed?] Cannot load manifest.yaml. It may have been deleted. Deploying."
      return true
    end
  
    current_manifest = generate_manifest(release_path)
    Chef::Log.info "artifact_deploy[has_manifest_changed?] Comparing saved manifest from #{release_path} with regenerated manifest from #{release_path}."
    
    differences = !saved_manifest.diff(current_manifest).empty?
    if differences
      Chef::Log.info "artifact_deploy[has_manifest_changed?] Saved manifest from #{release_path} differs from regenerated manifest. Deploying."
      return true
    else
      Chef::Log.info "artifact_deploy[has_manifest_changed?] Saved manifest from #{release_path} is the same as regenerated manifest. Not Deploying."
      return false
    end
  end

  # Checks the not-equality of the current_release_version against the version of
  # the currently configured resource. Returns true when the current symlink will
  # be changed to a different release of the artifact at the end of the resource
  # call.
  # 
  # @return [Boolean]
  def current_symlink_changing?
    get_current_release_version != ::File.basename(release_path)
  end

  # @return [Boolean] the deploy instance variable
  def deploy?
    @deploy
  end

  # @return [String] the file the current symlink points to
  def get_current_release_path
    if ::File.exists?(current_path)
      ::File.readlink(current_path)
    end
  end

  # @return [String] the current version the current symlink points to
  def get_current_release_version
    if ::File.exists?(current_path)
      ::File.basename(get_current_release_path)
    end
  end

  # Returns a path to the artifact being installed by
  # the configured resource.
  # 
  # @example
  #   When: 
  #     new_resource.deploy_to = "/srv/artifact_test" and artifact_version = "1.0.0"
  #       get_release_path => "/srv/artifact_test/releases/1.0.0"
  # 
  # @return [String] the artifacts release path
  def get_release_path
    ::File.join(new_resource.deploy_to, "releases", artifact_version)
  end

  # Searches the releases directory and returns an Array of version folders. After
  # rejecting the current release version from the Array, the array is sorted by mtime
  # and returned.
  # 
  # @return [Array] the mtime sorted array of currently installed versions
  def get_previous_version_paths
    versions = Dir[::File.join(new_resource.deploy_to, "releases", '**')].collect do |v|
      Pathname.new(v)
    end

    versions.reject! { |v| v.basename.to_s == get_current_release_version }

    versions.sort_by(&:mtime)
  end

  # Convenience method for returning just the version numbers of 
  # the currently installed versions of the artifact.
  # 
  # @return [Array] the currently installed version numbers
  def get_previous_version_numbers
    previous_version_paths.collect { |version| version.basename.to_s}
  end

  # Creates directories and symlinks as defined by the symlinks
  # attribute of the resource.
  # 
  # @return [void]
  def symlink_it_up!
    new_resource.symlinks.each do |key, value|
      directory "#{new_resource.shared_path}/#{key}" do
        owner new_resource.owner
        group new_resource.group
        mode '0755'
        recursive true
      end

      link "#{release_path}/#{value}" do
        to "#{new_resource.shared_path}/#{key}"
        owner new_resource.owner
        group new_resource.group
      end
    end
  end

  # Creates directories that are necessary for installing
  # the artifact.
  # 
  # @return [void]
  def setup_deploy_directories!
    recipe_eval do
      [ version_container_path, release_path, shared_path ].each do |path|
        directory path do
          owner new_resource.owner
          group new_resource.group
          mode '0755'
          recursive true
        end
      end
    end
  end

  # Creates directories that are defined in the shared_directories
  # attribute of the resource.
  # 
  # @return [void]
  def setup_shared_directories!
    recipe_eval do
      new_resource.shared_directories.each do |dir|
        directory "#{shared_path}/#{dir}" do
          owner new_resource.owner
          group new_resource.group
          mode '0755'
          recursive true
        end
      end
    end
  end

  # Retrieves the configured artifact based on the
  # artifact_location instance variable.
  # 
  # @return [void]
  def retrieve_artifact!
    recipe_eval do
      if from_http?(new_resource.artifact_location)
        retrieve_from_http
      elsif from_nexus?(new_resource.artifact_location)
        retrieve_from_nexus
      elsif ::File.exist?(new_resource.artifact_location)
        retrieve_from_local
      else
        Chef::Application.fatal! "artifact_deploy[retrieve_artifact!] Cannot retrieve artifact #{new_resource.artifact_location}! Please make sure the artifact exists in the specified location."
      end
    end
  end

  # Returns true when the artifact is believed to be from an
  # http source.
  # 
  # @param  location [String] the artifact_location
  # 
  # @return [Boolean] true when the location matches http or https.
  def from_http?(location)
    location =~ URI::regexp(['http', 'https'])
  end

  # Returns true when the artifact is believed to be from a
  # Nexus source.
  #
  # @param  location [String] the artifact_location
  # 
  # @return [Boolean] true when the location is a colon-separated value
  def from_nexus?(location)
    !from_http?(location) && location.split(":").length > 2
  end

  # Convenience method for determining whether a String is "latest"
  # 
  # @param  version [String] the version of the configured artifact to check
  # 
  # @return [Boolean] true when version matches (case-insensitive) "latest"
  def latest?(version)
    version.casecmp("latest") == 0
  end

  # Defines a resource call for downloading the remote artifact.
  # 
  # @return [void]
  def retrieve_from_http
    remote_file cached_tar_path do
      source new_resource.artifact_location
      owner new_resource.owner
      group new_resource.group
      checksum new_resource.artifact_checksum
      backup false

      action :create
    end
  end

  # Defines a ruby_block resource call to download an artifact from Nexus.
  # 
  # @return [void]
  def retrieve_from_nexus
    ruby_block "retrieve from nexus" do
      block do
        require 'nexus_cli'
        unless ::File.exists?(cached_tar_path) && Chef::ChecksumCache.checksum_for_file(cached_tar_path) == new_resource.artifact_checksum
          config = Chef::Artifact.nexus_config_for(node)
          remote = NexusCli::RemoteFactory.create(config, false)
          remote.pull_artifact(artifact_location, version_container_path)
        end
      end
    end
  end

  # Defines a resource call for a file already on the file system.
  # 
  # @return [void]
  def retrieve_from_local
    file cached_tar_path do
      content ::File.open(new_resource.artifact_location).read
      owner new_resource.owner
      group new_resource.group
    end
  end

  # Generates a manifest for all the files underneath the given files_path. SHA1 digests will be
  # generated for all files under the given files_path with the exception of directories and the 
  # manifest.yaml file itself.
  # 
  # @param  files_path [String] a path to the files that a manfiest will be generated for
  # 
  # @return [Hash] a mapping of file_path => SHA1 of that file
  def generate_manifest(files_path)
    Chef::Log.info "artifact_deploy[generate_manifest] Generating manifest for files in #{files_path}"
    files_in_release_path = Dir[::File.join(files_path, "**/*")].reject { |file| ::File.directory?(file) || file =~ /manifest.yaml/ }

    {}.tap do |map|
      files_in_release_path.each { |file| map[file] = Digest::SHA1.hexdigest(file) }
    end
  end

  # Generates a manfiest Hash for the files under the release_path and
  # writes a YAML dump of the created Hash to manifest_file.
  # 
  # @return [String] a String of the YAML dumped to the manifest.yaml file
  def write_manifest
    manifest = generate_manifest(release_path)
    Chef::Log.info "artifact_deploy[write_manifest] Writing manifest.yaml file to #{manifest_file}"
    ::File.open(manifest_file, "w") { |file| file.puts YAML.dump(manifest) }
  end