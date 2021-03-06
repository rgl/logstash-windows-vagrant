elastic_flavor = 'oss' # oss or basic.

hosts = '''
10.10.10.100 elasticsearch.example.com
10.10.10.100 kibana.example.com
'''

Vagrant.configure('2') do |config|
  config.vm.provider "libvirt" do |lv, config|
    lv.memory = 6*1024
    lv.cpus = 2
    lv.cpu_mode = "host-passthrough"
    lv.keymap = "pt"
    # replace the default synced_folder with something that works in the base box.
    # NB for some reason, this does not work when placed in the base box Vagrantfile.
    config.vm.synced_folder '.', '/vagrant', type: 'smb', smb_username: ENV['USER'], smb_password: ENV['VAGRANT_SMB_PASSWORD']
  end

  config.vm.provider :virtualbox do |v, override|
    v.linked_clone = true
    v.cpus = 2
    v.memory = 6*1024
    v.customize ['modifyvm', :id, '--vram', 64]
    v.customize ['modifyvm', :id, '--clipboard', 'bidirectional']
  end

  config.vm.define :logstash do |config|
    config.vm.box = 'windows-2019-amd64'
    config.vm.hostname = 'logstash'
    config.vm.network :private_network, ip: '10.10.10.100', libvirt__forward_mode: 'route', libvirt__dhcp_enabled: false
    config.vm.provision :shell, inline: "'#{hosts}' | Out-File -Encoding Ascii -Append c:/Windows/System32/drivers/etc/hosts"
    config.vm.provision :shell, path: 'ps.ps1', args: 'provision-common.ps1'
    config.vm.provision :shell, path: 'ps.ps1', args: 'provision-wireshark.ps1'
    config.vm.provision :shell, path: 'ps.ps1', args: ['provision-elasticsearch.ps1', elastic_flavor]
    config.vm.provision :shell, path: 'ps.ps1', args: ['provision-logstash.ps1', elastic_flavor]
    config.vm.provision :shell, path: 'ps.ps1', args: ['provision-winlogbeat.ps1', elastic_flavor]
    # NB the kibana index pattern creation needs the index created (before calling
    #    the kibana api endpoint index_patterns/_fields_for_wildcard). this
    #    will indirectly create the logstash index before installing kibana.
    config.vm.provision :shell, path: 'ps.ps1', args: 'examples/powershell-generate-logs/run.ps1'
    config.vm.provision :shell, path: 'ps.ps1', args: ['provision-kibana.ps1', elastic_flavor]
    config.vm.provision :shell, path: 'ps.ps1', args: 'provision-grafana.ps1'
    config.vm.provision :shell, path: 'ps.ps1', args: 'provision-dotnetcore-sdk.ps1'
    config.vm.provision :shell, path: 'ps.ps1', args: 'examples/powershell-logstash-udp/run.ps1'
    config.vm.provision :shell, path: 'ps.ps1', args: 'examples/csharp-serilog-http/run.ps1'
    config.vm.provision :shell, path: 'ps.ps1', args: 'provision-gradle.ps1'
    config.vm.provision :shell, path: 'ps.ps1', args: 'examples/java-log4j2-http/run.ps1'
    config.vm.provision :shell, path: 'ps.ps1', args: 'examples/java-log4j-gelf/run.ps1'
    config.vm.provision :shell, path: 'ps.ps1', args: 'examples/java-log4j-syslog/run.ps1'
    config.vm.provision :shell, path: 'ps.ps1', args: 'provision-erlang.ps1'
    config.vm.provision :shell, path: 'ps.ps1', args: 'examples/erlang-lager-logstash-udp/run.ps1'
    config.vm.provision :shell, path: 'ps.ps1', args: 'provision-rabbitmq.ps1'
    config.vm.provision :shell, path: 'ps.ps1', args: 'examples/rabbitmq-syslog/run.ps1'
  end
end
