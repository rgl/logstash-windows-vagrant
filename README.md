this is a [Logstash](https://www.elastic.co/products/logstash) playground

# Usage

[Build and install the Windows 2019 base image](https://github.com/rgl/windows-2016-vagrant).

Set the elastic stack flavor (`oss` (default) or `basic`) by setting the `elastic_flavor` variable inside the `Vagrantfile` file.

Launch the `logstash` machine:

```bash
vagrant up logstash --provider=virtualbox # or --provider=libvirt
```

Logon at the Windows console.
