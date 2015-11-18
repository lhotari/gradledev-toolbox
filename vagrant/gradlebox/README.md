gradlebox
=========

Vagrant VM configuration for running Java in a VM.

Installs Oracle Java 1.7 and 1.8 in the Ubuntu box.
[`jenv`](http://www.jenv.be/) is also installed to switch between Java versions.

Requirements:
* Vagrant 1.6.3+ , see http://docs.vagrantup.com/v2/installation/
* VirtualBox 4.3.14+ , see https://www.virtualbox.org/wiki/Downloads

Uses these vagrant plugins, installed by [`setup_box.sh`](setup_box.sh) script.
* vagrant [vbguest plugin](https://github.com/dotless-de/vagrant-vbguest)
* vagrant [cachier plugin](http://fgrehm.viewdocs.io/vagrant-cachier)

First usage:
```
./setup_box.sh
```