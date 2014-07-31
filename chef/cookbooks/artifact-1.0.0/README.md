# Artifact cookbook

Provides your cookbooks with the Artifact Deploy LWRP

# Requirements

* Chef 10

# Resources / Providers

## artifact_deploy

Deploys a collection of build artifacts packaged into a tar ball. Artifacts are extracted from
the package and managed in a deploy directory in the same fashion you've seen in the Opscode
deploy resource or Capistrano's default deploy strategy.

### Actions
Action   | Description                   | Default
-------  |-------------                  |---------
deploy   | Deploy the artifact package   | Yes
pre_seed | Pre-seed the artifact package |

### Attributes
Attribute           | Description                                                                          |Type     | Default
---------           |-------------                                                                         |-----    |--------
artifact_name       | Name of the artifact package to deploy                                               | String  | name
artifact_location   | URL, local path, or Maven identifier of the artifact package to download             | String  |
artifact_checksum   | The SHA256 checksum of the artifact package that is being downloaded                 | String  |
deploy_to           | Deploy directory where releases are stored and linked                                | String  |
version             | Version of the artifact being deployed                                               | String  |
owner               | Owner of files created and modified                                                  | String  |
group               | Group of files created and modified                                                  | String  |
environment         | An environment hash used by resources within the provider                            | Hash    | Hash.new
symlinks            | A hash that maps files in the shared directory to their paths in the current release | Hash    | Hash.new
shared_directories  | Directories to be created in the shared folder                                       | Array   | %w{ log pids }
force               | Forcefully deploy an artifact even if the artifact has already been deployed         | Boolean | false
should_migrate      | Notify the provider if it should perform application migrations                      | Boolean | false
keep                | Specify a number of artifacts deployments to keep on disk                            | Integer | 2
before_deploy       | A proc containing resources to be executed before the deploy process begins          | Proc    |
before_extract      | A proc containing resources to be executed before the artifact package is extracted  | Proc    |
after_extract       | A proc containing resources to be executed after the artifac package is extracted    | Proc    |
before_symlink      | A proc containing resources to be executed before the symlinks are created           | Proc    |
after_symlink       | A proc containing resources to be executed after the symlinks are created            | Proc    |
configure           | A proc containing resources to be executed to configure the artifact package         | Proc    |
before_migrate      | A proc containing resources to be executed before the migration Proc                 | Proc    |
migrate             | A proc containing resources to be executed during the migration stage                | Proc    |
after_migrate       | A proc containing resources to be executed after the migration Proc                  | Proc    |
restart_proc        | A proc containing resources to be executed at the end of a successful deploy         | Proc    |
after_deploy        | A proc containing resources to be executed after the deploy process ends             | Proc    |

### Deploy Flow, the Manifest, and Procs

The deploy flow is outlined in the Artifact Deploy flow chart below. 

![Artifact Deploy](http://riotgames.github.com/artifact-cookbook/images/ArtifactDeployFlow.png)

For a more detailed flow of what happens when we check with `deploy?`, see the [Manifest Differences Flow chart.](http://riotgames.github.com/artifact-cookbook/images/ManifestDifferencesFlow.png)

The 'happy-path' of this flow is the default path when an artifact has already been deploy - there will be no need to
execute many of the Procs. That being said, there are a few 'choice' paths through the flow where a Proc may affect the
flow.

There are two checks in the artifact deploy flow where a *manifest* check is executed - at the beginning, before the *before_deploy* proc,
and just after the *configure* proc (and after the *migrate* procs). When the latter check returns true, the *restart* proc will execute.

The *manifest* is a YAML file with a mapping of files in the deploy path to their SHA1 checksum. For example:

```
/srv/artifact_test/releases/2.0.68/log4j.xml: 96be5753fbf845e30b643fa04008f2c4fe6956a7
/srv/artifact_test/releases/2.0.68/readme.txt: fcb8d816b062565930f19f9bdb954f5ac43c5039
/srv/artifact_test/releases/2.0.68/my-artifact.jar: 42ad63cc883afad010573d3d8eea4e5a4011e5d4
```

There are numerous Procs placed throughout the flow of the artifact_deploy resource. They are meant to give the user many different
ways to configure the artifact and execute resources during the flow. Some good examples include executing a resource to stop a service
in the *before_deploy* proc, or placing configuration files in the deployed artifact during the *configure* proc.

**Please note** the *before_deploy*, *configure*, and *after_deploy* procs are executed on every Chef run. It is recommended that any *template*
(or configuration changing resource calls) take place within those procs. In particular, the *configure* proc was added for this very purpose. Following
this pattern will ensure that the templates will change, and the *restart* proc will execute (perhaps restarting the service the configured artifact provides
in order to pick up the configuration changes).

Procs can also utilize the internal methods of the provider class, because they are evaluated inside of the instance of the provider class. For example:

```
artifact_deploy "artifact_test" do
  # omitted for brevity
  configure Proc.new {
    # release_path is an attr_reader on the @release_path variable
    template "#{release_path}/conf/config.properties" do
      source "config.properties.erb"
      variables(:config => config)
    end
  }
end
```

### Documentation

The RDocs for the deploy.rb provider can be found under the [Top Level Namespace](http://riotgames.github.com/artifact-cookbook/doc/top-level-namespace.html) page
for this repository.

### Nexus Usage

In order to deploy an artifact from a Nexus repository, you must first create
an [encrypted data bag](http://wiki.opscode.com/display/chef/Encrypted+Data+Bags) that contains
the credentials for your Nexus repository.

    knife data bag create artifact nexus -c <your chef config> --secret-file=<your secret file>

Your data bag should look like the following:

    {
      "id": "nexus",
      "your_chef_environment": {
        "username": "nexus_user",
        "password": "nexus_user_password",
        "url": "http://nexus.yourcompany.com:8081/nexus/",
        "repository": "your_repository"
      }
    }

After your encrypted data bag is setup you can use Maven identifiers
for your artifact_location. A Maven identifier is shown as a colon-separated string
that includes three elemens - groupId:artifactId:extension - ex. "com.my.artifact:my-artifact:tgz". 
If many environments share the same configuration, you can use "*" as a wildcard environment name.

### Examples

##### Deploying a Rails application

    artifact_deploy "pvpnet" do
      version "1.0.0"
      artifact_location "https://artifacts.riotgames.com/pvpnet-1.0.0.tar.gz"
      deploy_to "/srv/pvpnet"
      owner "riot"
      group "riot"
      environment { 'RAILS_ENV' => 'production' }
      shared_directories %w{ data log pids system vendor_bundle assets }

      before_deploy Proc.new {
        bluepill_service 'pvpnet-unicorn' do
          action :stop
        end
      }

      before_migrate Proc.new {
        template "#{shared_path}/database.yml" do
          source "database.yml.erb"
          owner node[:merlin][:owner]
          group node[:merlin][:group]
          mode "0644"
          variables(
            :environment => environment,
            :options => database_options
          )
        end
        
        execute "bundle install --local --path=vendor/bundle --without test development cucumber --binstubs" do
          environment { 'RAILS_ENV' => 'production' }
          user "riot"
          group "riot"
        end
      }

      migrate Proc.new {
        execute "bundle exec rake db:migrate" do
          cwd release_path
          environment { 'RAILS_ENV' => 'production' }
          user "riot"
          group "riot"
        end
      }

      after_migrate Proc.new {
        ruby_block "remove_run_migrations" do
          block do
            Chef::Log.info("Migrations were run, removing role[pvpnet_run_migrations]")
            node.run_list.remove("role[pvpnet_run_migrations]")
          end
        end
      }

      configure Proc.new {
        template "/srv/pvpnet/current/config.properties" do
          source "config.properties.erb"
          owner 'riot'
          group 'riot'
          variables(:database_config => node[:pvpnet_cookbook][:database_config])
        end
      }

      restart_proc Proc.new {
        bluepill_service 'pvpnet-unicorn' do 
          action :restart
        end
      }

      keep 2
      should_migrate (node[:pvpnet][:should_migrate] ? true : false)
      force (node[:pvpnet][:force_deploy] ? true : false)
      action :deploy
    end

# Testing

A sample cookbook is available in `fixtures`. You can package it with mkartifact.sh, and
upload it to Nexus as artifact_cookbook:test:1.2.3:tgz.

Set the artifact_test_location and artifact_test_version environment variables when running
vagrant to change how they'll be provisioned. Default is 1.2.3 from a file URL.

* artifact_test_location=artifact_cookbook:test:1.2.3:tgz artifact_test_version=1.2.3 bundle exec vagrant

# Releasing

1. Install the prerequisite gems
    
        $ gem install chef
        $ gem install thor

2. Increment the version number in the metadata.rb file

3. Run the Thor release task to create a tag and push to the community site

        $ thor release

# License and Author

Author:: Jamie Winsor (<jamie@vialstudios.com>)<br/>
Author:: Kyle Allan (<kallan@riotgames.com>)

Copyright 2013, Riot Games

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
