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
# sudo $HOME/os-install.sh --domain=ejw.root.sx 2>&1 | tee /var/log/os-install.log
#
# cpu=$(cat /sys/class/thermal/thermal_zone0/temp) && echo "CPU => $((cpu/1000))°C"
#

# Add /sbin path for linux command
PATH=/usr/bin:/bin:/usr/sbin:/sbin

FILE_PATH=$(readlink -f $(dirname $0))  #/home/media
FILE_NAME=$(basename $0)                #os-install.sh
FILE_NAME=${FILE_NAME%.*}               #os-install
FILE_DATE=$(date +'%Y%m%d-%H%M%S')
FILE_LOG="/var/log/$FILE_NAME.log"
export FILE_MAIL="/var/log/$FILE_NAME-mail.log"

###############################################################################
### Functions

###############################################################################
### Environment Variables

# Source under this script directory
cd $(readlink -f $(dirname $0))
. .bash_colors

# Source OS details (for VERSION_ID)
. /etc/os-release

# Source environment variables
ACME_COPY=0
. os-install.env > /dev/null 2>&1

ROOT_UID=$(id -u root)
USER_UID=$(id -u)
USER=$(id -un)

###############################################################################
### Pre-Script

# Check if run as root
if [ $USER_UID -ne $ROOT_UID ] ; then
  echo "* "
  echored "* You must be root to do that!"
  echo "* "
  exit 1
fi

HELP=0
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
  echo "* "
  echo "* sudo $FILE_PATH/$FILE_NAME.sh --domain=${DOMAIN:-ejw.root.sx} 2>&1 | sudo tee /var/log/$FILE_NAME.log"
  exit 1
fi

DOMAIN=${DOMAIN:-ejw.root.sx}
if [ -n "$(echo $1 | grep '\-d=')" ] || [ -n "$(echo $1 | grep '\--domain=')" ]; then
  # $1 = "--domain=ejw.root.sx"
  # Get the value after =
  DOMAIN=${1#*=}
fi

###############################################################################
### Script

# Do not interprate space in variable during for loop
SAVEIFS=$IFS
IFS=$'\n'

runstart=$(date +%s)
echo "* Command: $0 $@"
echo "* Start time: $(date)"
echo "* "


echo "* Ubuntu installation for $DOMAIN"


./os-backup.sh --restore


echo "* [apt] Checking for updates, please wait..."
# Fix apt sources list Network is unreachable
# Err:8 http://fr.archive.ubuntu.com/ubuntu focal-updates Release
# Cannot initiate the connection to fr.archive.ubuntu.com:80 (2001:860:f70a::2). - connect (101: Network is unreachable)
sed -i 's#http://fr.archive.ubuntu#http://archive.ubuntu#g' /etc/apt/sources.list
apt update > /dev/null 2>&1

echo "* [shell] Set aliases"
cat << 'EOF' > .bash_aliases
alias ll='ls -alFh --color=auto'
alias topfiles='f() { du -hsx $2/* 2> /dev/null | sort -rh | head -n $1; }; f'
# Copy with incremental progress bar
alias cpsync='rsync -rpthW --inplace --no-compress --exclude=.bin/ --info=progress2'
# Copy with incremental progress bar and preserve rights
alias cpsyncP='rsync -ahW --inplace --no-compress --exclude=.bin/ --info=progress2'
alias osinfo='/home/media/os-info.sh'
alias osbackup='/home/media/os-backup.sh'
alias osupgrade='/home/media/os-upgrade.sh --auto'
alias doclog='docker logs'
alias docres='docker restart'
alias docrec='f() { cd /home/media/docker-media; docker-compose up -d --no-deps --force-recreate $1; cd - > /dev/null; }; f'
alias docps='docker ps  --format "table {{.Names}}\t{{.Image}}\t{{.Command}}\t{{.Status}}"'
alias docstats='docker stats --all --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"'
alias docdf='docker system df'
alias docprune='docker system prune --all --volumes --force'
alias cputemp='cpu=$(cat /sys/class/thermal/thermal_zone0/temp) && echo "CPU = $((cpu/1000))°C"'
EOF
sed -i "s#/home/media#$FILE_PATH#g" .bash_aliases
cp .bash_aliases /root

echo "* [shell] Set bash colors"
cp .bash_colors /root

apt -y install lm-sensors hddtemp
echo "* [shell] Set system information command at login"
#ln -sf ~/os-info.sh /etc/profile.d/99-os-info.sh
cat << 'EOF' >> .profile

#
# Change welcome message
#

# Check internet status
echo
wget -q --spider http://www.google.com 2> /dev/null
if [ $? -eq 0 ]; then  # if Google website is available we update
echo "You are connected to the internet."
else
echo "You are not connected to the internet."
fi

# Show OS informations and status
echo
echo -n "* Show OS informations and status? [y/N] "
read answer
if [ -n "$(echo $answer | grep -i '^y')" ]; then
~/os-info.sh
else
echo "* You can use 'osinfo' command alias later."
echo
fi
EOF

echo "* [locale] Setup language en_GB"
if [ -z "$(locale -a | grep "en_GB.utf8")" ]; then
  locale-gen en_GB.UTF-8
  update-locale LANG=en_GB.UTF-8
  locale-gen --purge en_GB.UTF-8
  #echo "LANG=en_GB.UTF-8" > /etc/default/locale
fi
echo "* [tzdata] Setup timezone $TZ"
echo $TZ > /etc/timezone
ln -sf /usr/share/zoneinfo/$TZ /etc/localtime
#dpkg-reconfigure tzdata
timedatectl set-timezone $TZ

echo "* [sshd] Setup service details"
cat << EOF > /etc/ssh/sshd_config
Protocol 2
#Port 22
#AddressFamily any
#ListenAddress 0.0.0.0
#ListenAddress ::

# Authentication
AllowUsers $USER
PermitEmptyPasswords no
PermitRootLogin no
PasswordAuthentication yes
ChallengeResponseAuthentication no
MaxAuthTries 3

# Message after a successful login
UsePAM no
PrintMotd no

# Network configuration
ClientAliveInterval 180
AllowTcpForwarding yes
X11Forwarding yes
TCPKeepAlive yes
Compression yes
UseDNS no

AcceptEnv LANG LC_*
Subsystem  sftp internal-sftp
EOF

echo "* [user] Create user $USER & the familly"
# useradd -m -d /home/media -s /bin/bash -c "Media user" -g users media
# usermod -a -G adm,dialout,cdrom,floppy,sudo,audio,dip,video,plugdev,lxd,netdev,www-data,syslog media
# usermod -g 100 media
# (
# echo "M&di@!" # New UNIX password
# echo "M&di@!" # Retype new UNIX password
# ) | passwd media

# Add a existing user to existing group
usermod -a -G users $USER
# Change existing primary group
usermod -g users $USER
# Remove group
delgroup $USER

# USER="Jonathan|passwd|Jonathan Weisberg"
for L in $(cat $FILE_NAME.env | grep "^USER="); do
  # Get the value after =
  V=${L#*=}
  # Evaluate variable inside the line
  V=$(eval echo $V)
  # Remove " from string
  #V=${V//\"}

  USR=$(echo $V | cut -d'|' -f1)      # User login
  U_PWD=$(echo $V | cut -d'|' -f2)    # Password
  U_DESC="$(echo $V | cut -d'|' -f3)" # Description
  U_MAIL=$(echo $V | cut -d'|' -f4)   # Email

  # User login to lowercase
  USR_LC=$(echo $USR | awk '{print tolower($0)}')
  
  # useradd -m -d /home/Jonathan -s /bin/false -c "Jonathan Weisberg" -g users Jonathan
  # usermod -a -G users Jonathan
  # rm -Rf /home/Jonathan
  useradd -m -d /home/$USR -s /bin/false -c "$U_DESC" -g users $USR
  usermod -a -G users $USR
  echo "$USR:$U_PWD" | chpasswd
  rm -Rf /home/$USR
done

if [ -z "$WIFI_NAME" ]; then
  echo "* [netplan] Enable Wi-Fi access to $WIFI_NAME"
  apt -y install wireless-tools
  cat << EOF >> /etc/netplan/50-cloud-init.yaml
  wifis:
      wlan0:
          dhcp4: true
          optional: true
          access-points:
              "$WIFI_NAME":
                  password: "$WIFI_PWD"
EOF
  netplan generate
  netplan apply
fi

echo "* [fstab] Install packages cifs,nfs"
apt -y install cifs-utils nfs-common
echo "* [usb-automount] Install packages"
apt -y install ntfs-3g exfat-utils exfat-fuse
cat << EOF > /etc/systemd/system/usb-automount.service
[Unit]
Description=USB automount

After=local-fs.target network.target dbus.socket syslog.socket

[Service]
Type=simple
ExecStart=$FILE_PATH/usb-automount.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable usb-automount

echo "* [fstab] Attach USB data devices"
#/dev/sda1: LABEL="home_data" UUID="7662-C355" TYPE="exfat" PARTUUID="6c727443-01"
#/dev/sda1: LABEL="home_data" UUID="60E8C1B2E8C186AE" TYPE="ntfs" PARTUUID="68e32bcd-01"
eval $(blkid | grep sda | grep -o -e "TYPE=\S*")
eval $(blkid | grep sda | grep -o -e "LABEL=\S*")
if [ "$TYPE" == "ntfs" ]; then
  mkdir /mnt/data
  cat << EOF >> /etc/fstab
# Usb data disk /dev/sda
#$(blkid | grep sda | cut -d':' -f1) /mnt/data $TYPE-3g defaults,uid=$(id -u media),gid=$(id -g media),noatime 0 2
LABEL="$LABEL" /mnt/data $TYPE-3g defaults,uid=$(id -u media),gid=$(id -g media),noatime 0 2
EOF
elif [ -n "$TYPE" ]; then
  mkdir /mnt/data
  cat << EOF >> /etc/fstab
# Usb data disk /dev/sda
#$(blkid | grep sda | cut -d':' -f1) /mnt/data $TYPE defaults,uid=$(id -u media),gid=$(id -g media),noatime 0 2
LABEL="$LABEL" /mnt/data $TYPE defaults,uid=$(id -u media),gid=$(id -g media),noatime 0 2
EOF
fi
if [ $ACME_COPY -eq 1 ]; then
  mkdir /mnt/openwrt-certs
  cat << EOF >> /etc/fstab
# Attached devices
#//openwrt/OpenWrt-Certs$ /mnt/openwrt-certs cifs _netdev,guest,user=root,iocharset=utf8,vers=2.0 0 2
//openwrt/OpenWrt-Certs$ /mnt/openwrt-certs cifs guest,user=root,iocharset=utf8,vers=2.0,noauto,x-systemd.automount,x-systemd.idle-timeout=30 0 2
EOF
  # Remount CIFS on network reconnect by adding "noauto,x-systemd.automount,x-systemd.idle-timeout=30" and restart daemon
  systemctl daemon-reload
  systemctl restart mnt-openwrt\\x2dcerts.mount
  systemctl restart mnt-openwrt\\x2dcerts.automount
  sed -i 's/^#__ACME_COPY__//' $FILE_PATH/docker-media/docker-compose.yml
fi

echo "* [journald] Limit size=100M and 3day of /var/log/journal"
sed -i 's/.*SystemMaxUse=.*/SystemMaxUse=200M/g' /etc/systemd/journald.conf
sed -i 's/.*MaxFileSec=.*/MaxFileSec=3day/g' /etc/systemd/journald.conf
systemctl restart systemd-journald

echo "* [cronjob] Add healthcheck disk"
apt -y install --no-install-recommends smartmontools
echo "* [cronjob] Add packages upgrade"
echo "* [cronjob] Add backup data"
cat << EOF >> /var/spool/cron/crontabs/root
# Healthcheck disk usage and stats @05:45
45 5 * * * $FILE_PATH/healthcheck-disk.sh
# Packages upgrade automatically @06:00
0 6 * * * $FILE_PATH/os-upgrade.sh --auto
# OS backup every Friday @06:15
15 6 * * 5 $FILE_PATH/os-backup.sh
EOF

echo "* [fs] Create directory /share "
mkdir /share
chown $USER:users /share
mkdir -p /var/docker
chown $USER:users /var/docker

echo "* [fs] Set symlink on /share"
sudo -i -u $USER bash << EOF
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

  chown -R $USER:users /mnt/data/Public/*

  # USER="Jonathan|passwd|Jonathan Weisberg"
  for L in $(cat $FILE_NAME.env | grep "^USER="); do
    # Get the value after =
    V=${L#*=}
    # Evaluate variable inside the line
    V=$(eval echo $V)
    # Remove " from string
    #V=${V//\"}

    USR=$(echo $V | cut -d'|' -f1)      # User login
    U_PWD=$(echo $V | cut -d'|' -f2)    # Password
    U_DESC="$(echo $V | cut -d'|' -f3)" # Description
    U_MAIL=$(echo $V | cut -d'|' -f4)   # Email

    # User login to lowercase
    USR_LC=$(echo $USR | awk '{print tolower($0)}')

    # chown -R Jonathan:users /mnt/data/Users/Jonathan/
    chown -R $USR:users /mnt/data/Users/$USR/
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
local master=no
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
guest account=$USER
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
#socket options=TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=524288 SO_SNDBUF=524288 SO_KEEPALIVE
socket options=TCP_NODELAY IPTOS_LOWDELAY
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
for L in $(cat $FILE_NAME.env | grep "^USER="); do
  # Get the value after =
  V=${L#*=}
  # Evaluate variable inside the line
  V=$(eval echo $V)
  # Remove " from string
  #V=${V//\"}

  USR=$(echo $V | cut -d'|' -f1)      # User login
  U_PWD=$(echo $V | cut -d'|' -f2)    # Password
  U_DESC="$(echo $V | cut -d'|' -f3)" # Description
  U_MAIL=$(echo $V | cut -d'|' -f4)   # Email
  
  # User login to lowercase
  USR_LC=$(echo $USR | awk '{print tolower($0)}')

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
path=/share/Users/$USR
comment=$USR's Folder
available=yes
writeable=yes
guest only=no
# Access rights
valid users=$USR
create mask=0600
directory mask=0700
oplocks=yes
locking=yes
EOF

  echo "* [Samba] Add user $USR"
  # Add samba user with password
  (
  echo $U_PWD # New password
  echo $U_PWD # Retype new password
  ) | smbpasswd -a $USR
  
  rm -Rf /share/Users/$USR/.bin/*
done

echo "* [Samba] Add user www-data"
# (
# echo   # New SMB password
# echo   # Retype new SMB password
# ) | smbpasswd -a Jonathan
(
echo www-data # New SMB password
echo www-data # Retype new SMB password
) | smbpasswd -a www-data
usermod -a -G users www-data

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
account default : gmail
EOF
cat << EOF > /etc/msmtp.aliases
root: jo.weisberg@gmail.com
$USER: jo.weisberg@gmail.com
EOF
rm -f /etc/msmtp.aliases
# echo "Hello this is sending email using mSMTP" | msmtp $(id -un)
# echo -e "Subject: Test mSMTP\r\nHello this is sending email using mSMTP" | msmtp $(id -un)
# echo -e "Subject: Power outage @ $(date)\r\n $(upsc el650usb)" | msmtp -a gmail $(whoami)
# echo -e "From: Pretty Name\r\nSubject: Example subject\r\nContent goes here." | msmtp --debug jo.weisberg@gmail.com
# Error:
# Allow access to unsecure apps
# https://myaccount.google.com/lesssecureapps
# msmtp: authentication failed (method PLAIN)
# https://accounts.google.com/DisplayUnlockCaptcha

echo "* [Mutt] Setup email attachment encapsulation w/ mSMTP"
# https://gist.github.com/ramn/1923071
apt -y install mutt
cat << EOF > /etc/muttrc
# Sending mail
set sendmail="/usr/bin/msmtp"
set from = "no-reply@gmail.com"
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
alias $USER jo.weisberg@gmail.com
EOF

sudo -i -u root bash << EOF
ln -sf /etc/muttrc ~/.muttrc
mkdir -p ~/.mutt/cache
EOF
sudo -i -u $USER bash << EOF
ln -sf /etc/muttrc ~/.muttrc
mkdir -p ~/.mutt/cache
EOF
ln -sf /usr/bin/mutt /usr/bin/mailx
# echo "" | mutt -s "My Subject" -i body.txt -a attachment.txt -- recipient@example.com
# echo -e "My body message\r\nThks" | mutt -s "My Subject" -i body.txt -a attachment.txt -- recipient@example.com
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
iptables -A INPUT -p udp --dport 137 -j ACCEPT -m comment --comment "Samba NetBIOS name service (WINS)"
iptables -A INPUT -p udp --dport 138 -j ACCEPT -m comment --comment "Samba NetBIOS datagram"
iptables -A INPUT -p tcp --dport 139 -j ACCEPT -m comment --comment "Samba NetBIOS Session, Windows File and Printer Sharing"
iptables -A INPUT -p tcp --dport 445 -j ACCEPT -m comment --comment "Samba Microsoft-DS Active Directory, Windows shares"
iptables -A INPUT -p udp --dport 445 -j ACCEPT -m comment --comment "Samba Microsoft-DS SMB file sharing"
iptables -A INPUT -i docker0 -j ACCEPT
iptables -A FORWARD -i docker0 -o $(ip -o -4 route show to default | head -n1 | awk '{print $5}') -j ACCEPT
iptables -A FORWARD -i $(ip -o -4 route show to default | head -n1 | awk '{print $5}') -o docker0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables-save > /etc/iptables/rules.v4
echo "* [iptables] Set firewall rules as persistent"
iptables-restore < /etc/iptables/rules.v4
systemctl enable netfilter-persistent
systemctl restart netfilter-persistent
#systemctl start docker

echo "* [docker] Install packages"
# For older version than Ubuntu 20.04 LTS
if [ $(echo $VERSION_ID | sed 's/\.//') -lt 2004 ]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
  add-apt-repository -y "deb [arch=$(dpkg --print-architecture)] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
  apt update > /dev/null 2>&1
  apt -y install docker-ce
#else
  # docker-ce not supported from Ubuntu 20.04 LTS, use docker-compose only
  
  # apt-cache policy docker-compose
  #docker-compose:
  #  Installed: 1.25.0-1
  #  Candidate: 1.25.0-1
  #  Version table:
  # *** 1.25.0-1 500
  #        500 http://fr.archive.ubuntu.com/ubuntu focal/universe amd64 Packages
  #        100 /var/lib/dpkg/status
fi
apt -y install docker-compose jq
usermod -aG docker $USER
echo "* [docker] Add dependency w/ netfilter-persistent"
#sed -i 's/^After=.*/After=network-online.target netfilter-persistent.service containerd.service/g' /lib/systemd/system/docker.service
sed -i 's/firewalld.service/netfilter-persistent.service/g' /lib/systemd/system/docker.service
#sed -i 's/^After=.*/& smbd.service/' /lib/systemd/system/docker.service
# Kill process using http/https ports before starting docker, prevent "accept tcp [::]:80: use of closed network connection" on Traefik
#sed -i '/^ExecStart=.*/i ExecStartPre=/usr/bin/fuser --kill 80/tcp > /dev/null 2>&1\nExecStartPre=/usr/bin/fuser --kill 443/tcp > /dev/null 2>&1' /lib/systemd/system/docker.service
#sed -i '/^ExecStart=.*/i ExecStartPre=/home/media/docker-media/docker-iproute.sh' /lib/systemd/system/docker.service
systemctl enable docker

HOST=$(hostname -A | awk '{ print $1 }')
HOST_IP=$(hostname -I | awk '{ print $1 }')
if [ -f $FILE_PATH/docker-media/.env ]; then
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
echo "* [sudo] Use sudo without password"
echo "* sudo visudo"
echo "* Add at the end of the file:"
echo "* $(whoami) ALL=NOPASSWD:/usr/bin/apt update,/usr/sbin/hddtemp"


echo "* "
echo "* "
echo "* "
echo -n "* Reboot to complete the installation? [Y/n] "
read answer
if [ -n "$(echo $answer | grep -i '^y')" ] || [ -z "$answer" ]; then
  reboot
fi


echo "* "
echo "* End time: $(date)"
runend=$(date +%s)
runtime=$((runend-runstart))
echo "* Elapsed time: $(($runtime / 3600))hrs $((($runtime / 60) % 60))min $(($runtime % 60))sec"

# Restore Internal Field Separator
IFS=$SAVEIFS

exit 0