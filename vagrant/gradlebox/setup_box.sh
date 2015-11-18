#!/bin/bash -x
vagrant plugin install vagrant-vbguest
vagrant plugin install vagrant-cachier
vagrant box update
vagrant up
vagrant up
./update_guest_additions.sh
vagrant halt
vagrant up
vagrant ssh
