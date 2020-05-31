#!/bin/bash
#
# ssh ubuntu@ubuntu / ubuntu
# sudo -i
# (
# echo "RPi.!#_" # New UNIX password
# echo "Rpi.!#_" # Retype new UNIX password
# ) | passwd
# useradd -m -d /home/media -s /bin/bash -c "RPi's media user" -g users media
# usermod -a -G adm,dialout,cdrom,floppy,sudo,audio,dip,video,plugdev,lxd,netdev,www-data,syslog media
# usermod -g 100 media
# (
# echo "M&di@!" # New UNIX password
# echo "M&di@!" # Retype new UNIX password
# ) | passwd media
# echo "rpi" > /etc/hostname
# reboot
#
# ssh media@rpi / M&di@!
# sudo -i
# deluser ubuntu
# rm -Rf /home/ubuntu
# mkdir /var/docker
# chown media:users /var/docker
# exit
# ln -sf /var/docker $HOME/docker
#
# Launch command:
# sudo $HOME/rpi-install.sh --backup 2>&1 | tee /var/log/rpi-backup.log
# sudo $HOME/rpi-install.sh 2>&1 | tee /var/log/rpi-install.log
#
# cpu=$(cat /sys/class/thermal/thermal_zone0/temp) && echo "CPU => $((cpu/1000))°C"
#

FILE_PATH=$(readlink -f $(dirname $0))  #/home/media
FILE_NAME=$(basename $0)                #rpi-install.sh
FILE_NAME=${FILE_NAME%.*}               #rpi-install
FILE_DATE=$(date +'%Y%m%d-%H%M%S')
FILE_LOG="/var/log/$FILE_NAME.log"

# For Loop File Names With Spaces
SAVEIFS=$IFS
IFS=$(echo -en "\n\b")

# Source syntax color script
cd $FILE_PATH
. .bash_colors

USER_UID=$(id -u)
ROOT_UID=0
# Check if run as root
if [ $USER_UID -ne $ROOT_UID ] ; then
  echo "* "
  echored "* You must be root to do that!"
  echo "* "
  exit 1
fi

HELP=0
if [ "$1" == "-b" ] || [ "$1" == "--backup" ]; then
  FILE_LOG=$(echo $FILE_LOG | sed 's/install/backup/g')
fi
if [ ! -f $FILE_LOG ] || [ $(cat $FILE_LOG | wc -l) -gt 0 ] || [ "$(ls -l --time-style=long-iso $FILE_LOG | awk '{print $6" "$7}')" != "$(date +'%Y-%m-%d %H:%M')" ]; then
  HELP=1
  echo "* "
  echored "* $FILE_LOG file not found!"
  echo "* "
fi
if [ "$1" == "-h" ] || [ "$1" == "--help" ] || [ $HELP -eq 1 ]; then
  echo "* Ubuntu script must have one sub-command argument"
  echo "* Usage: $FILE_NAME.sh [option]"
  echo "* where sub-command is one of:"
  echo "  -d, --domain=sub.example.com    Install Ubuntu for specific domain"
  echo "  -b, --backup                    Backup Ubuntu"
  echo "* "
  echo "* sudo $FILE_PATH/$FILE_NAME.sh --backup 2>&1 | tee /var/log/$HOSTNAME-backup.log"
  echo "* sudo $FILE_PATH/$FILE_NAME.sh --domain=${DOMAIN:-sub.example.com} 2>&1 | tee /var/log/$HOSTNAME-install.log"
  exit 1
fi


runstart=$(date +%s)
echo "* Command: $0 $@"
echo "* Start time: $(date)"
echo "* "

# Source environment variables
ACME_COPY=0
if [ -f $FILE_NAME.env ]; then
  . $FILE_NAME.env
fi

CONF_BASE="backup-$HOSTNAME"
CONF_NAME="backup-$HOSTNAME-$(date +'%Y-%m-%d')"
CONF_FILE="backup-$HOSTNAME-$(date +'%Y-%m-%d').tar.gz"
if [ "$1" == "-b" ] || [ "$1" == "--backup" ]; then
  if [ ! -f $HOSTNAME-backup.conf ]; then
    echo "* "
    echored "* File $HOSTNAME-backup.conf is not found!"
    exit 1
  fi
  echo "* [Ubuntu] Backup files/folders into $CONF_FILE"

  BKP_PATH=$FILE_PATH/$HOSTNAME-backup
  mkdir -p $BKP_PATH
  cd $BKP_PATH

  # Keep only the last 3 more recent backup files
  if [ $(ls -tr $CONF_BASE-* 2> /dev/null | wc -l) -gt 3 ]; then
    NB=$(eval echo $(($(ls -tr $CONF_BASE-* | wc -l) -3)))
    echo "* [fs] Keep only 3 last backup, then removing these old files under $BKP_PATH"
    ls -tr $CONF_BASE-* | head -n$NB
    ls -tr $CONF_BASE-* | head -n$NB | xargs rm -f
  fi

  # Remove same existing file
  rm -f $CONF_NAME*
  # Create archive w/ list of files/folders
  tar -cf $CONF_NAME.tar -T $FILE_PATH/$HOSTNAME-backup.conf > /dev/null 2>&1
#  for obj in $(cat $FILE_PATH/$HOSTNAME-backup.conf | grep -v -e "^#" -e "^[[:space:]]*$"); do
#    # Skip line starting with # and empty line
#    if [ -f "$CONF_NAME.tar" ]; then
#      # Add file/folder into existing archive
#      tar -uf $CONF_NAME.tar $obj > /dev/null 2>&1
#    else
#      # Create archive w/ new file/folder
#      tar -cf $CONF_NAME.tar $obj > /dev/null 2>&1
#    fi
#  done
  gzip -f $CONF_NAME.tar

  chown -R media:users $BKP_PATH
  # Moves to the previous directory
  cd - > /dev/null

  echo "* "
  echo "* "
  echo "* "
  echo "* [Ubuntu] Backup completed."

  echo "* "
  echo "* End time: $(date)"
  runend=$(date +%s)
  runtime=$((runend-runstart))
  echo "* Elapsed time: $(($runtime / 3600))hrs $((($runtime / 60) % 60))min $(($runtime % 60))sec"
  exit 0

elif [ -n "$(echo $1 | grep '\-d=')" ] || [ -n "$(echo $1 | grep '\--domain=')" ]; then
  # $1 = "--domain=sub.example.com"
  # Get the value after =
  DOMAIN=${1#*=}

  echo "* Ubuntu installation for $DOMAIN"

  RESTORE_BKP=1
  if [ $(ls -t backup-$HOSTNAME*.tar.gz 2> /dev/null | wc -l) -eq 0 ]; then
    echo "* "
    echored "* No backup file found!"
    echo "* "
    echo "* Please check in the current directory, if backup-$HOSTNAME-*.tar.gz file exists..."
    echo "* Or run: "
    echoyellow "* sudo $FILE_PATH/$FILE_NAME.sh --backup 2>&1 | tee /var/log/$HOSTNAME-backup.log"
    echo "* "
    echo "* "
    echo "* "
    echo -n "* Do you want to force the installation? [y/N] "
    read answer
    if [ -n "$(echo $answer | grep -i '^y')" ]; then
      RESTORE_BKP=0
    else
      exit 1
    fi
  fi

  if [ $RESTORE_BKP -eq 1 ]; then
    echo "* [Ubuntu] Restoring backup"
    CONF_FILE=$(ls -t backup-$HOSTNAME-*.tar.gz | head -n1)
    ls -t backup-$HOSTNAME-*.tar.gz | head -n5
    echo -n "* Enter backup to restore? <$CONF_FILE> "
    read answer
    if [ -n "$answer" ]; then
      CONF_FILE=$answer
    fi
    gunzip -f $CONF_FILE
    tar -xzpf $CONF_NAME.tar -C / > /dev/null 2>&1
  fi

  echo "* [apt] Checking for updates, please wait..."
  apt update > /dev/null 2>&1

  echo "* [tzdata] Set timezone to $TZ"
  echo $TZ > /etc/timezone
  ln -sf /usr/share/zoneinfo/$TZ /etc/localtime

  echo "* [shell] Set aliases"
  cat << 'EOF' > .bash_aliases
alias ll='ls -alFh --color=auto'
alias topfiles='f() { du -hsx $2/* 2> /dev/null | sort -rh | head -n $1; }; f'
alias cpsync-mini='rsync -rpthW --inplace --no-compress --exclude=.bin/ --delete --info=progress2'
alias cpsync-full='rsync -ahW --inplace --no-compress --exclude=.bin/ --delete --info=progress2'
alias docrec='f() { cd /home/media/docker-media; docker-compose up -d --no-deps --force-recreate $1; cd - > /dev/null; }; f'
alias docps='docker ps -a'
alias docdf='docker system df'
alias docprune='docker system prune --all --volumes --force'
alias cputemp='cpu=$(cat /sys/class/thermal/thermal_zone0/temp) && echo "CPU = $((cpu/1000))°C"'
EOF
  cp .bash_aliases /root

  echo "* [sshd] Setup service details"
  cat << EOF > /etc/ssh/sshd_config
#Port 22
#AddressFamily any
#ListenAddress 0.0.0.0
#ListenAddress ::

# Authentication:
PermitRootLogin no
AllowUsers media
PasswordAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

AllowTcpForwarding yes
X11Forwarding yes
PrintMotd no
TCPKeepAlive yes
Compression yes
UseDNS no

AcceptEnv LANG LC_*
Subsystem  sftp internal-sftp
EOF

  echo "* [user] Create media & the familly"
  # useradd -m -d /home/media -s /bin/bash -c "Media user" -g users media
  # usermod -a -G adm,dialout,cdrom,floppy,sudo,audio,dip,video,plugdev,lxd,netdev,www-data,syslog media
  # usermod -g 100 media
  # (
  # echo "M&di@!" # New UNIX password
  # echo "M&di@!" # Retype new UNIX password
  # ) | passwd media

  # USER="Jonathan|passwd|Jonathan Weisberg"
  for L in $(cat $FILE_NAME.env | grep "^USER"); do
    # Get the value after =
    V=${L#*=}
    # Evaluate variable inside the line
    V=$(eval echo $V)
    # Remove " from string
    #V=${V//\"}

    # User login to lowercase
    U=$(echo $V | cut -d'|' -f1 | awk '{print tolower($0)}')

    # useradd -m -d /home/jonathan -s /bin/false -c "Jonathan Weisberg" -g users jonathan
    # usermod -a -G users jonathan
    # rm -Rf /home/jonathan
    useradd -m -d /home/$U -s /bin/false -c "$(echo $V | cut -d'|' -f3)" -g users $U
    usermod -a -G users $U
    rm -Rf /home/$U
  done

  echo "* [fstab] Install packages cifs,nfs"
  apt -y install cifs-utils nfs-common
  echo "* [usbmount] Install packages"
  apt -y install ntfs-3g exfat-utils exfat-fuse
  echo "* [fstab] Attach USB data devices"
  #/dev/sda1: LABEL="home_data" UUID="7662-C355" TYPE="exfat" PARTUUID="6c727443-01"
  #/dev/sda1: LABEL="home_data" UUID="60E8C1B2E8C186AE" TYPE="ntfs" PARTUUID="68e32bcd-01"
  eval $(blkid | grep sda | grep -o -e "TYPE=\S*")
  if [ "$TYPE" == "ntfs" ]; then
    mkdir /mnt/data
    cat << EOF >> /etc/fstab
# Usb data disk /dev/sda
/dev/sda1 /mnt/data ntfs-3g defaults,uid=$(id -u media),gid=$(id -g media),nofail,noatime 0 2
EOF
  elif [ -n "$TYPE" ]; then
    mkdir /mnt/data
    cat << EOF >> /etc/fstab
# Usb data disk /dev/sda
/dev/sda1 /mnt/data $TYPE defaults,uid=$(id -u media),gid=$(id -g media),nofail,noatime 0 2
EOF
  fi
  if [ $ACME_COPY -eq 1 ]; then
    mkdir /mnt/openwrt-certs
    cat << EOF >> /etc/fstab
# Attached devices
//openwrt/OpenWrt-Certs$ /mnt/openwrt-certs cifs _netdev,guest,user=root,iocharset=utf8,vers=2.0 0 2
EOF
    sed -i 's/^#__ACME_COPY__//' $FILE_PATH/docker-media/docker-compose.yml
  fi

  echo "* [cronjob] Add backup data"
  cat << EOF >> /var/spool/cron/crontabs/root
# Packages upgrade automatically @06:00
0 6 * * * $FILE_PATH/$HOSTNAME-upgrade.sh --quiet > /var/log/$HOSTNAME-upgrade.log 2>&1
# Packages backup every Monday @05:55
55 5 * * 1 $FILE_PATH/$HOSTNAME-install.sh --backup > /var/log/$HOSTNAME-backup.log 2>&1
EOF

  echo "* [fs] Create directory /share "
  mkdir /share
  chown media:users /share
  mkdir -p /var/docker
  chown media:users /var/docker

  echo "* [fs] Set symlink on /share"
  sudo -i -u media bash << EOF
#ln -sf /var/docker \$HOME/docker
ln -sf /share \$HOME/share
ln -sf /mnt/data/Public /share/Public
ln -sf /mnt/data/Users /share/Users
EOF

  find $FILE_PATH -type f -name "*.sh" -print0 | xargs -0 chmod +x
  echo -n "* Reset access rights on /mnt/data? [y/N] "
  read answer
  if [ -n "$(echo $answer | grep -i '^y')" ]; then
    chmod -R 755 /mnt/data/Public
    chmod -R g-s /mnt/data/*

    chown -R media:users /mnt/data/Public/*

    # USER="Jonathan|passwd|Jonathan Weisberg"
    for L in $(cat $FILE_NAME.env | grep "^USER"); do
      # Get the value after =
      V=${L#*=}
      # Evaluate variable inside the line
      V=$(eval echo $V)
      # Remove " from string
      #V=${V//\"}

      # User login to lowercase
      U=$(echo $V | cut -d'|' -f1 | awk '{print tolower($0)}')

      # chown -R jonathan:users /mnt/data/Users/Jonathan/
      chown -R $U:users /mnt/data/Users/$(echo $V | cut -d'|' -f1)/
    done

    find /mnt/data/Users -type d -print0 | xargs -0 chmod 700
    find /mnt/data/Users -type f -print0 | xargs -0 chmod 600
    chmod 550 /mnt/data/Users
    find /mnt/data/Public -type d -print0 | xargs -0 chmod 755
    find /mnt/data/Public -type f -print0 | xargs -0 chmod 644
    find /mnt/data/Public/*/.bin -maxdepth 0 -type d -print0 | xargs -0 chmod 755
    chmod 555 /mnt/data/Public
  fi

  echo "* [Samba] Setup file sharing over a network"
  apt -y install samba
  cat << EOF > /etc/samba/smb.conf
[global]
  workgroup = WORKGROUP
  server string=%h server (Samba, Ubuntu)
  dns proxy=no
  # Logging
  log level=3
  log file=/var/log/samba/log.%m
  max log size=1000
  # Printing
  load printers=no
  printing=bsd
  printcap name=/dev/null
  disable spoolss=yes
  # Authentication
  server role=standalone server
  security=user
  map to guest=Bad User
  guest account=media

  # Manage symlinks
  unix extensions=no
  follow symlinks=yes
  wide links=yes

  ### Access rights ###
  nt acl support=no
  force group=users
  create mask=0644
  directory mask=0755

  ### Recycle bin ###
  vfs object=recycle
  recycle:repository=.bin/%U
  recycle:keeptree=yes
  recycle:versions=yes
  recycle:exclude=*.tmp,*.temp,*.TMP,*.TEMP,*.o,*.obj,~$*,*.~??,*.log,*.trace
  recycle:excludedir=/.bin,/tmp,/temp,/TMP,/TEMP

  ### Performance tuning ###
  socket options=TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=524288 SO_SNDBUF=524288 SO_KEEPALIVE
  read raw=yes
  write raw=yes
  strict locking=no
  oplocks=yes
  max xmit=65535
  dead time=10
  use sendfile=yes

[Public]
  path=/share/Public
  comment=Public Documents
  available=yes
  writeable=yes
  guest only=yes
  # Access rights
  create mask=0664
  directory mask=0775
  oplocks=yes
  locking=yes
EOF
  # USER="Jonathan|passwd|Jonathan Weisberg"
  for L in $(cat $FILE_NAME.env | grep "^USER"); do
    # Get the value after =
    V=${L#*=}
    # Evaluate variable inside the line
    V=$(eval echo $V)
    # Remove " from string
    #V=${V//\"}

    U=$(echo $V | cut -d'|' -f1)  #Samba User
    P=$(echo $V | cut -d'|' -f2)  #Samba User Password

#[Jonathan$]
#  path=/share/Users/Jonathan
#  comment=Jonathan's Folder
#  available=yes
#  writeable=yes
#  guest only=no
#  # Access rights
#  valid users=Jonathan,www-data
#  force user=Jonathan
#  create mask=0600
#  directory mask=0700
#  oplocks=yes
#  locking=yes

    cat << EOF >> /etc/samba/smb.conf

[${U}$]
  path=/share/Users/$U
  comment=$U's Folder
  available=yes
  writeable=yes
  guest only=no
  # Access rights
  valid users=$U,www-data
  force user=$U
  create mask=0600
  directory mask=0700
  oplocks=yes
  locking=yes
EOF

    (
    echo $P # New SMB password
    echo $P # Retype new SMB password
    ) | smbpasswd -a $U

    rm -Rf /share/Users/$U/.bin/*
  done


  echo "* Add samaba users"
  # (
  # echo   # New SMB password
  # echo   # Retype new SMB password
  # ) | smbpasswd -a Jonathan
  (
  echo www-data # New SMB password
  echo www-data # Retype new SMB password
  ) | smbpasswd -a www-data
  usermod -a -G users www-data

  echo "* [fs] Purge .bin data on Samba"
  rm -Rf /share/Public/.bin/*
  # rm -Rf /share/Users/Jonathan/.bin/*

  echo "* [mSMTP] Setup email forward"
  apt -y install msmtp
  cat << EOF > /etc/msmtprc
# A system wide configuration file is optional.
# If it exists, it usually defines a default account.
# This allows msmtp to be used like /usr/sbin/sendmail.

# Set default values for all folowwing accounts.
defaults
# Use Standard/RFC on port 25
# Use TLS on port 465
# Use STARTTLS on port 587
port 25
tls off
tls_starttls off
tls_nocertcheck
from no-reply@free.fr
auth off
#aliases /etc/msmtp.aliases
logfile ~/.msmtp.log

# Free
account free
host smtp.free.fr
#from no-reply@free.fr

# Gmail
account gmail
host smtp.gmail.com
port 587
tls on
tls_starttls on
#from no-reply@gmail.com
auth on
#maildomain gmail.com
user jo.weisberg
password J@hn2711.

# Set a default account
account default : none
EOF
  cat << EOF > /etc/msmtp.aliases
default: jo.weisberg@gmail.com
root: jo.weisberg@gmail.com
EOF
  rm -f /etc/msmtp.aliases
  # echo -e "Subject: Power outage @ $(date)\n\n$(upsc el650usb)" | msmtp -a gmail $(whoami)

  echo "* [Mutt] Setup email attachment encapsulation w/ mSMTP"
  # https://gist.github.com/ramn/1923071
  apt -y install mutt
  cat << EOF > /etc/muttrc
# Sending mail
set sendmail="/usr/bin/msmtp"
set from = "no-reply@free.fr"
set realname = "htpc"
set use_from=yes
set envelope_from=yes
set smtp_url = "smtp://jo.weisberg@smtp.gmail.com:587/"
set smtp_pass = "J@hn2711."
#set smtp_url = "smtp://smtp.free.fr:25/"
#set smtp_pass = ""

# Where to put the stuff
set header_cache = "~/.mutt/cache/headers"
set message_cachedir = "~/.mutt/cache/bodies"
set certificate_file = "~/.mutt/certificates"

# Other settings
source /etc/mutt.aliases
# Move read messages from your spool mailbox to your $mbox mailbox
set move = no
EOF
cat << EOF > /etc/mutt.aliases
alias root jo.weisberg@gmail.com
alias media jo.weisberg@gmail.com
EOF

  sudo -i -u root bash << EOF
ln -sf /etc/muttrc ~/.muttrc
mkdir -p ~/.mutt/cache
EOF
  sudo -i -u media bash << EOF
ln -sf /etc/muttrc ~/.muttrc
mkdir -p ~/.mutt/cache
EOF
  ln -sf /usr/bin/mutt /usr/bin/mailx
  # echo "" | mutt -s "My Subject" -i body.txt -a attachment.txt -- recipient@example.com
  # echo -e "My body message\n\rThks" | mutt -s "My Subject" -i body.txt -a attachment.txt -- recipient@example.com
  # cat body.txt | mutt -s "My Subject" -a attachment.txt -- recipient@example.com
  # upsc el650usb | mailx -s "Power outage @ $(date)" -- $(whoami)

  echo "* [hd-idle] Enable SATA spin down (10 mins)"
  # For older version than Ubuntu 20.04 LTS
  if [ $(lsb_release -r | awk '{print $2}' | sed 's/\.//') -lt 2004 ]; then
    apt -y install build-essential fakeroot debhelper
    cd /root
    wget http://sourceforge.net/projects/hd-idle/files/hd-idle-1.05.tgz
    tar -xvf hd-idle-1.05.tgz && chown -R root:root hd-idle && cd hd-idle
    dpkg-buildpackage -rfakeroot
    dpkg -i ../hd-idle_*.deb
    apt -y autoremove --purge build-essential fakeroot debhelper
    cd $FILE_PATH
  else
    apt -y install hd-idle
  fi
  cat << EOF > /etc/default/hd-idle
START_HD_IDLE=true
HD_IDLE_OPTS="-i 0 -a sda -i 600 -l /var/log/hd-idle.log"
EOF
  systemctl start hd-idle
  systemctl enable hd-idle

  echo "* [iptables] Install packages"
  apt -y install iptables-persistent netfilter-persistent
  echo "* [iptables] Setup firewall rules for IPv4"
  #systemctl stop docker
  iptables -F
  iptables -X
  iptables -P INPUT ACCEPT
  iptables -P FORWARD ACCEPT
  iptables -P OUTPUT ACCEPT
  iptables -A INPUT -i lo -j ACCEPT
  iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
  iptables -A INPUT -p tcp --dport 22 -j ACCEPT -m comment --comment "ssh"
  iptables -A INPUT -p tcp --dport 80 -j ACCEPT -m comment --comment "http"
  iptables -A INPUT -p tcp --dport 443 -j ACCEPT -m comment --comment "https"
  iptables -A INPUT -p udp -m multiport --dports 137,138 -j ACCEPT -m comment --comment "samba"
  iptables -A INPUT -p tcp -m multiport --dports 139,445 -j ACCEPT -m comment --comment "samba"
  iptables -A INPUT -i docker0 -j ACCEPT
  iptables -A FORWARD -i docker0 -o $(ip -o -4 route show to default | awk '{print $5}') -j ACCEPT
  iptables -A FORWARD -i $(ip -o -4 route show to default | awk '{print $5}') -o docker0 -m state --state RELATED,ESTABLISHED -j ACCEPT
  iptables -P INPUT DROP
  iptables -P FORWARD DROP
  iptables-save > /etc/iptables/rules.v4
  echo "* [iptables] Set firewall rules as persistent"
  iptables-restore < /etc/iptables/rules.v4
  systemctl enable netfilter-persistent

  echo "* [docker] Install packages"
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
  add-apt-repository "deb [arch=$(dpkg --print-architecture)] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
  apt update > /dev/null 2>&1
  apt -y install docker-ce docker-compose jq
  usermod -aG docker media
  echo "* [docker] Add dependency w/ netfilter-persistent"
  sed -i 's/^After=.*/After=network-online.target netfilter-persistent.service containerd.service smbd.service/g' /lib/systemd/system/docker.service
  #sed -i 's/firewalld.service/netfilter-persistent.service/g' /lib/systemd/system/docker.service
  #sed -i 's/^After=.*/& smbd.service/' /lib/systemd/system/docker.service
  # Add sleep 20 before starting docker, prevent "accept tcp [::]:80: use of closed network connection" on Traefik
  #sed -i '/^ExecStart=.*/i ExecStartPre=/bin/sleep 20' /lib/systemd/system/docker.service

  if [ -f $FILE_PATH/docker-media/.env ]; then
    HOST=$(hostname -f | awk '{ print $1 }')
    HOST_IP=$(hostname -I | awk '{ print $1 }')
    sed -i "s/^HOST=.*/HOST=$HOST/g" $FILE_PATH/docker-media/.env
    sed -i "s/^HOST_IP=.*/HOST_IP=$HOST_IP/g" $FILE_PATH/docker-media/.env
    sed -i "s/^DOMAIN=.*/DOMAIN=$DOMAIN/g" $FILE_PATH/docker-media/.env
    if [ ! -d /var/docker/owncloud ]; then
      OC_VER=$(git ls-remote --tags --refs https://github.com/owncloud/core.git | cut -d'v' -f2 | grep -v -E "alpha|beta|RC" | sort -nr 2> /dev/null | head -n1)
      sed -i "s/^OWNCLOUD_VERSION=.*/OWNCLOUD_VERSION=$OC_VER/g" $FILE_PATH/docker-media/.env
    fi
    sed -i "s/^OWNCLOUD_DOMAIN=.*/OWNCLOUD_DOMAIN=$DOMAIN/g" $FILE_PATH/docker-media/.env
  fi
  if [ -f /var/docker/traefik/servers.toml ]; then
    sed -i "s/.*rule = \"Host.*/    rule = \"Host(\`$DOMAIN.\`)\"/g" /var/docker/traefik/servers.toml
    chmod 600 /var/docker/traefik/acme.json
  fi
  if [ -f /var/docker/traefik/certs/ssl-cert.key ]; then
    echo "* [traefik] Set symlink for ssl certificates"
    . $FILE_PATH/docker-media/.env
    ln -f /var/docker/traefik/certs/ssl-cert.key /etc/ssl/private/$DOMAIN.key
    ln -f /var/docker/traefik/certs/ssl-cert.pem /etc/ssl/certs/$DOMAIN.pem
    ln -f /var/docker/traefik/certs/ssl-cert.crt /var/docker/owncloud/files/files_external/rootcerts.crt
    ln -f /var/docker/traefik/certs/ssl-cert.key /var/docker/muximux/keys/cert.key
    ln -f /var/docker/traefik/certs/ssl-cert.crt /var/docker/muximux/keys/cert.crt
  fi
  if [ -f /var/docker/muximux/www/muximux/settings.ini.php ]; then
    sed -i "s|^url = \"http://monitoring.rpi.local.*|url = \"http://monitoring.$HOST\"|g" /var/docker/muximux/www/muximux/settings.ini.php
    sed -i "s|^url = \"http://proxy.rpi.local.*|url = \"http://proxy.$HOST/dashboard\"|g" /var/docker/muximux/www/muximux/settings.ini.php
    sed -i "s|^url = \"http://docker.rpi.local.*|url = \"http://docker.$HOST\"|g" /var/docker/muximux/www/muximux/settings.ini.php
    sed -i "s|^url = \"http://rpi.local/owncloud*|url = \"http://$HOST/owncloud\"|g" /var/docker/muximux/www/muximux/settings.ini.php
  fi

  echo "* [apt] Remove unused packages"
  apt -y autoremove --purge lxd snapd
  apt -y autoremove --purge cryptsetup


  echo "* "
  echo "* "
  echo "* "
  echo -n "* Reboot to complete the installation? [Y/n] "
  read answer
  if [ -n "$(echo $answer | grep -i '^y')" ] || [ -z "$answer" ]; then
    reboot
  fi
fi


echo "* "
echo "* End time: $(date)"
runend=$(date +%s)
runtime=$((runend-runstart))
echo "* Elapsed time: $(($runtime / 3600))hrs $((($runtime / 60) % 60))min $(($runtime % 60))sec"

# Restore $IFS
IFS=$SAVEIFS
exit 0
