name             'splunk_config'
maintainer       'Luis Rodriguez'
maintainer_email 'luis.rodriguez@cru.org'
license          'Apache 2.0'
description      'configure splunk forwarder'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          '0.1.0'


supports 'amazon'
supports 'centos'
supports 'debian'
supports 'fedora'
supports 'redhat'
supports 'ubuntu'


depends "chef-splunk"
