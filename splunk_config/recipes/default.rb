# Cookbook Name:: splunk_config
# Recipe:: default
#

include_attribute "chef-splunk"
include_attribute "wildfly"

#configure splunk
auth_user = "node['splunk']['auth']"
default_pass = "node['splunk']['pass']"
new_pass = "node['splunk']['newpass']"
install_path = "node['splunk']['install_path']"

begin
    resources('service[splunk]')
    rescue Chef::Exceptions::ResourceNotFound
    service 'splunk'
end

directory "#{splunk_dir}/etc/system/local" do
    recursive true
    owner node['splunk']['user']['username']
    group node['splunk']['user']['username']
end

bash 'change-admin-user-password-from-default' do
    if !File.exists?("#{splunk_dir}/etc/.setup_#{user}_password")
    user "root"
    cwd "#{install_path}/bin"
    code <<-EOH
    ./splunk edit user #{auth_user} -password #{new_pass} -auth #{auth_user}:#{default_pass}
    EOH
    end
end

file "#{splunk_dir}/etc/.setup_#{user}_password" do
    content 'true\n'
    owner 'root'
    group 'root'
    mode 00600
end

template "#{splunk_dir}/etc/system/local/outputs.conf" do
    source 'outputs.conf.erb'
    mode 0644
    variables(
    :default_group => node['splunk']['group'],
    :splunk_servers => node['splunk']['forward_server']
             )
    notifies :restart, 'service[splunk]'
end

template "#{splunk_dir}/etc/apps/search/local/inputs.conf" do
    source 'inputs.conf.erb'
    mode 0644
    variables(
    :monitor_path => node['splunk']['monitor_path']
             )
    notifies :restart, 'service[splunk]'
end
