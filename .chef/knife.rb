log_level                :info
log_location             STDOUT
node_name                'luisr'
client_key               '/Users/luis.rodriguez/Documents/projects/project_five/devenv/.chef/luisr.pem'
validation_client_name   'chef-validator'
validation_key           '/Users/luis.rodriguez/Documents/projects/project_five/devenv/.chef/chef-validator.pem'
encrypted_data_bag_secret "./encrypted_data_bag_secret"
chef_server_url          'https://dlchef01.ccci.org:443'
syntax_check_cache_path  '/Users/luis.rodriguez/Documents/projects/project_five/devenv/.chef/syntax_check_cache'
cookbook_path [ '/Users/luis.rodriguez/Documents/projects/project_five/devenv/chef/cookbooks' ]
knife[:vault_mode] = 'client'
knife[:vault_admins] = [ 'luis']
