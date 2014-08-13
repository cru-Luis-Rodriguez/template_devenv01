# -*- mode: ruby -*-
# vi: set ft=ruby :

# Vagrantfile API/syntax version. Don't touch unless you know what you're doing!
VAGRANTFILE_API_VERSION = "2"

#Vagrant.require_version ">= 1.5.0"

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  config.omnibus.chef_version = :latest
  config.berkshelf.enabled = true


config.vm.define :cla07 do |tlchefcla07|
    tlchefcla07.vm.hostname = "tlchefcla07.ccci.org"
    tlchefcla07.vm.box = "opscode_centos-7.0"
    tlchefcla07.vm.box_url = "http://opscode-vm-bento.s3.amazonaws.com/vagrant/virtualbox/opscode_centos-7.0_chef-provisionerless.box"
    tlchefcla07.vm.network "public_network", bridge: 'en4: Thunderbolt Ethernet'
    tlchefcla07.vm.network "forwarded_port", guest: 8080, host: 8080
    tlchefcla07.vm.provision :chef_client do |chef|
    chef.node_name = config.vm.hostname
    chef.chef_server_url =  'https://dlchef01.ccci.org:443'
    chef.validation_key_path = "/Users/luis.rodriguez/Documents/projects/project_five/devenv/.chef/chef-validator.pem"
    chef.validation_client_name = "chef-validator"
    chef.client_key_path = "/etc/chef/client.pem"
    chef.provisioning_path = "/etc/chef"
    chef.log_level = :info
    chef.environment = "dev-vagrant"
    chef.delete_node = "true"
    chef.delete_client = "true"
    # Add a recipe
    #chef.run_list = ["recipe[wildfly::default]", "recipe[chef:splunk::install_forwarder]"]
    # Or maybe a role
    chef.add_role "wildfly"
    chef.add_role "splunkforwarder"
    chef.add_role "splunk_config"
     end
 end
end

