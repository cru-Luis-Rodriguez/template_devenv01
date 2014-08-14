splunk_config Cookbook
==========================
Configures spunk forwarder client


Requirements
------------ 

depends chef-splunk 

supports :amazon, centos, debian, fedora, redhat, ubuntu


Attributes
----------
TODO: List your cookbook attributes here.

# General settings

default['splunk']['install_path’]= ‘default location for splunk install’.

Use json on Opsworks Stack setting to provided attribute information. Attributes can not be nil

default['splunk']['pass']='nil'
default['splunk']['newpass']='nil'
default['splunk']['forward_server']='nil'
default['splunk']['receiver_port']='nil'
default['splunk']['auth']='nil'
default['splunk']['monitor_path']='nil'


Usage
-----
#### splunk_config::default

Just include `splunk_config` in your node's `run_list`:

```json
{
  "name":"my_node",
  "run_list": [
    "recipe[splunk_config]"
  ]
}
```

Contributing
------------
TODO: (optional) If this is a public cookbook, detail the process for contributing. If this is a private cookbook, remove this section.

e.g.
1. Fork the repository on Github
2. Create a named feature branch (like `add_component_x`)
3. Write your change
4. Write tests for your change (if applicable)
5. Run the tests, ensuring they all pass
6. Submit a Pull Request using Github

License and Authors
-------------------
Authors: TODO: List authors
