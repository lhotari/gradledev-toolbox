#!/usr/bin/env bash

set -x
export DEBIAN_FRONTEND=noninteractive

if [ ! -e "/home/vagrant/.firstboot" ]; then
  # remove ufw firewall
  dpkg --purge ufw

  apt-get update
 
  apt-get install -y --force-yes  ethtool

  # configure ethtool , disable tcp offloading in virtual ethernet adapter
cat >> /etc/network/interfaces.d/eth0.cfg <<EOF2
post-up /sbin/ethtool --offload eth0 gso off tso off sg off gro off || true
pre-up /sbin/ethtool --offload eth0 gso off tso off sg off gro off || true
EOF2
  /sbin/ethtool --offload eth0 gso off tso off sg off gro off

  # upgrade all packages
  apt-get upgrade -q -y --force-yes
  apt-get dist-upgrade -q -y --force-yes

  # install required packages
  apt-get install -y --force-yes vim acpid software-properties-common curl unzip python-software-properties git language-pack-en

  # java 7 & 8
  add-apt-repository ppa:webupd8team/java
  apt-get update

  for javaver in 7 8; do
      # purge cache
      find -L /var/cache/oracle-jdk${javaver}-installer -mindepth 1 -maxdepth 1 -not -name "jdk*" -exec rm -rf {} \;
      # accept license
      echo oracle-java${javaver}-installer shared/accepted-oracle-license-v1-1 select true | /usr/bin/debconf-set-selections
      # install package
      apt-get install -y --force-yes oracle-java${javaver}-installer
  done

  # install jenv
  su -l -c bash vagrant <<_EOF_
cd /home/vagrant
git clone https://github.com/gcuisinier/jenv.git .jenv
echo 'export PATH="\$HOME/.jenv/bin:\$PATH"' >> .bash_profile
echo 'eval "\$(jenv init -)"' >> .bash_profile
. .bash_profile
jenv add /usr/lib/jvm/java-7-oracle
jenv add /usr/lib/jvm/java-8-oracle
jenv global 1.8
jenv enable-plugin export
_EOF_

  touch /home/vagrant/.firstboot
  poweroff
fi
