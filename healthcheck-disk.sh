#!/bin/bash
#
# Healthcheck disk usage when above 90% used
# Healthcheck disk stats with smartctl and btrfs
#
# Required package:
# apt -y install --no-install-recommends smartmontools
#
# Launch command:
# $HOME/healthcheck-disk.sh
#
# crontab -e
# # Healthcheck disk usage and stats @05:45
# 45 5 * * * $HOME/healthcheck-disk.sh
#

# Add /sbin path for linux command
PATH=/usr/bin:/bin:/usr/sbin:/sbin

FILE_PATH=$(readlink -f $(dirname $0))  #/home/media
FILE_NAME=$(basename $0)                #healthcheck-disk.sh
FILE_NAME=${FILE_NAME%.*}               #healthcheck-disk
FILE_DATE=$(date +'%Y%m%d-%H%M%S')
FILE_LOG="/var/log/$FILE_NAME.log"

###############################################################################
### Functions

function fShowStatus() {
  local CURR=$1 MAX=$2
  echo "[$([ $CURR -eq $MAX ] && echo "OK" || echo "!!")]"
}

function fShowStatusLt() {
  local CURR=$1 MAX=$2
  echo "[$([ $CURR -lt $MAX ] && echo "OK" || echo "!!")]"
}

function fCheckSmart {
  local MNT=$1 DEV= STATUS=

  DEV=$(df | grep -E '^/dev|/mnt' | grep "$MNT$" | awk '{print $1}')
  STATUS=$(smartctl -H $DEV | awk -F: '/^SMART /{print $2}' | xargs)
  
  if [ "$STATUS" == "PASSED" ] || [ "$STATUS" == "OK" ]; then
    echo " Disk stats: $MNT [OK]"
  else
    echo " Disk stats: $MNT [!!]"
    # Show information section
    smartctl -a $DEV | sed -n '5,19p' | sed 's/^/\t/'
  fi
  
}

function fCheckBtrfs {
  local MNT=$1

  if [ $(btrfs device stats $MNT | grep -vE ' 0$' | wc -l) -eq 0 ]; then
    echo " Disk stats: $MNT [OK]"
    
    # Show filesystem allocation of block group types
    #btrfs filesystem df -H $MNT | sed 's/^/\t/'

    #btrfs filesystem usage $MNT | sed -n '2,10p' | sed 's/ (estimated):/:           /g' | awk -F'(' '{print $1}' | sed 's/^ /*/'

  else
    echo " Disk stats: $MNT [!!]"
    btrfs device stats $MNT | sed 's/^/\t/'
    
    # Show filesystem allocation of block group types
    echo " * btrfs filesystem df $MNT"
    btrfs filesystem df -H $MNT | sed 's/^/\t/'
	
    # Show partitions filesystem usage
    echo " * btrfs filesystem usage $MNT"
    btrfs filesystem usage -H $MNT | sed 's/^/\t/'
  fi
}

function fSendMail() {
  if [ -n "$(cat $FILE_LOG | grep 'Disk:' | grep "[!!]")" ] || [ -n "$(cat $FILE_LOG | grep 'Disk stats:' | grep "[!!]")" ]; then
    MSG_HEAD="Disk used above limit of $DISK_LIMIT% or errors detected!"
    echo -e "$MSG_HEAD\n$(cat $FILE_LOG)" | mailx -s "[$HOSTNAME@$DOMAIN] Healthcheck Disk" -- $(whoami)
  fi
}

###############################################################################
### Environment Variables

# Source under this script directory
cd $(readlink -f $(dirname $0))
. os-install.env
. .bash_colors
. /etc/os-release
export DISPLAY=:0

ROOT_UID=$(id -u root)
USER_UID=$(id -u)
USER=$(who -m | awk '{print $1}')

# Disk limit used in percentage
DISK_LIMIT=90

# GNU/Linux 5.4.0-72-generic x86_64
# Linux 5.4.0-1019-raspi aarch64
KER_VER="$(uname -sri)"
# OS_VER="20.04.19"
OS_VER="$(do-release-upgrade -V | cut -d' ' -f3)"
LTS=""
if [ "$(cat /etc/update-manager/release-upgrades | grep "^Prompt" | cut -d'=' -f2)" = "lts" ]; then
  # OS_VER="20.04.19 LTS"
  OS_VER="$OS_VER LTS"
  LTS="LTS"
fi

###############################################################################
### Pre-Script

# Check if run as root
if [ $USER_UID -ne $ROOT_UID ] ; then
  echo "* "
  echored "* You must be root to do that!"
  echo "* "
  exit 1
fi

rm -f $FILE_LOG

###############################################################################
### Script

echo | tee -a $FILE_LOG
echo "GENERAL SYSTEM INFORMATION" | tee -a $FILE_LOG
echo " $(id -un)@$HOSTNAME.$(cat /etc/resolv.conf | grep '^search' | awk '{print $2}')" | tee -a $FILE_LOG
echo " OS: $NAME $OS_VER ($VERSION_CODENAME)" | tee -a $FILE_LOG
echo " Kernel: $KER_VER" | tee -a $FILE_LOG
echo " Uptime: $(uptime | awk -F'( |,|:)+' '{d=h=m=0; if ($7=="min") m=$6; else {if ($7~/^day/) {d=$6;h=$8;m=$9} else {h=$6;m=$7}}} {print d+0"d",h+0"h",m+0"m"}')" | tee -a $FILE_LOG
echo " Shell: $(echo "bash $BASH_VERSION" | cut -d'(' -f1)" | tee -a $FILE_LOG

if [ -n "$(cat /proc/cpuinfo | grep '^Hardware' | head -n1)" ]; then
  CPU_NAME=$(cat /proc/cpuinfo | grep '^Hardware' | head -n1 | awk -F':' '{print $2}' | awk -F'CPU' '{print $1}' | sed 's/ *$//g' | sed 's/^ *//g')
elif [ -n "$(cat /proc/cpuinfo | grep '^model name' | head -n1)" ]; then
  CPU_NAME=$(cat /proc/cpuinfo | grep '^model name' | head -n1 | awk -F':' '{print $2}' | awk -F'CPU' '{print $1}' | sed 's/ *$//g' | sed 's/^ *//g')
elif [ -n "$(cat /proc/cpuinfo | grep '^Model' | head -n1)" ]; then
  CPU_NAME=$(cat /proc/cpuinfo | grep '^Model' | head -n1 | awk -F':' '{print $2}' | awk -F'CPU' '{print $1}' | sed 's/ *$//g' | sed 's/^ *//g')
elif [ -n "$(cat /proc/cpuinfo | grep '^system type' | head -n1)" ]; then
  CPU_NAME=$(cat /proc/cpuinfo | grep '^system type' | head -n1 | awk -F':' '{print $2}' | awk -F'CPU' '{print $1}' | sed 's/ *$//g' | sed 's/^ *//g')
fi
# Remove the trailing and leading spaces
#CPU_NAME=$(echo $CPU_NAME | sed 's/ *$//g' | sed 's/^ *//g')
CPU_NCORE=$(cat /proc/cpuinfo | grep '^processor' | wc -l)
#CPU_SPEED=$(lshw -C CPU 2> /dev/null | grep "capacity:" | head -n1 | awk '{print $2}' | cut -d'@' -f1)
CPU_SPEED=$(lscpu | awk '/^CPU max MHz/ {printf "%.2fGHz", $4/1000}')
if [ $(sensors > /dev/null 2>&1; echo $?) -eq 0 ]; then
  CPU_TEMP="$(eval $OS_CPU_TEMP | awk -vx=0 '{sum+=$1} END {print sum/NR}')"
  CPU_TEXT="[$CPU_TEMP°C]"
fi
echo " CPU: $CPU_NAME @ ${CPU_NCORE}x $CPU_SPEED $CPU_TEXT" | tee -a $FILE_LOG

GPU_NAME=$(lshw -C video 2> /dev/null | grep "product:" | awk -F':' '{print $2}' | awk -F'Controller' '{print $1}' | sed 's/ *$//g' | sed 's/^ *//g')
# Remove the trailing and leading spaces
#GPU_NAME=$(echo $GPU_NAME | sed 's/ *$//g' | sed 's/^ *//g')
GPU_DRIVER=$(lshw -C video 2> /dev/null | grep "driver" | awk '{print $2}' | awk -F'=' '{print $2}')
GPU_RES=$(xrandr 2> /dev/null | grep '*' | awk '{print $1}')
if [ -n "$GPU_NAME" ]; then
  echo " GPU: $GPU_NAME ($GPU_DRIVER)" | tee -a $FILE_LOG
  # OpenGL: Mesa DRI Intel(R) HD Graphics 4600 (HSW GT2) [OpenGL 3.0 Mesa 20.2.6]
  echo " OpenGL: $(glxinfo | awk -F: '/^OpenGL renderer string/ {print $2}' | sed 's/^ *//g') [OpenGL $(glxinfo | awk -F: '/^OpenGL version string/ {print $2}' | sed 's/^ *//g')]" | tee -a $FILE_LOG
  echo " Resolution: $GPU_RES" | tee -a $FILE_LOG
  echo " GTK Theme: $(gsettings get org.gnome.desktop.interface gtk-theme | cut -d"'" -f2) [GTK-$(dpkg -s libgtk-3-0 2> /dev/null | grep '^Version' | cut -d' ' -f2)]" | tee -a $FILE_LOG
#  else
#    echo " GPU: N/A"
#    echo " OpenGL: N/A"
#    echo " Resolution: N/A"
#    echo " GTK Theme: N/A"
fi

echo " RAM: $(free -m | grep ^Mem | awk '{printf("%.2fG / %.2fG (%.0f%%)",$3/1024,$2/1024,$2!=0?$3*100/$2:0)}')" | tee -a $FILE_LOG
echo " SWAP: $(free -m | grep ^Swap | awk '{printf("%.2fG / %.2fG (%.0f%%)",$3/1024,$2/1024,$2!=0?$3*100/$2:0)}')" | tee -a $FILE_LOG
echo " Processes: $(ps -ax | wc -l)" | tee -a $FILE_LOG
echo " Users account: $(cat /etc/passwd | wc -l) / $OS_USER_MAX $(fShowStatus $(cat /etc/passwd | wc -l) $OS_USER_MAX)" | tee -a $FILE_LOG
echo " Users shell: $(cat /etc/passwd | grep "$(cat /etc/shells)" | wc -l) / $OS_SHELL_MAX $(fShowStatus $(cat /etc/passwd | grep "$(cat /etc/shells)" | wc -l) $OS_SHELL_MAX)" | tee -a $FILE_LOG
echo " Users logged in: $(w -h | grep -v "$(date +%H:%M)" | wc -l)" | tee -a $FILE_LOG

echo | tee -a $FILE_LOG
echo "DISKS USAGE" | tee -a $FILE_LOG
# Disk: /boot/efi [vfat] 7.8M / 504M (2%)
#df -HT | grep -E '^/dev|/mnt' | awk '{print $7" ["$2"] "$4" / "$3" ("$6")"}' | sed "s/^/$(echored ' Disk: ')/"
df -HT | grep -E '^/dev|/mnt' | awk '{print $7" ["$2"] "$4" / "$3" ("$6")"}' > /tmp/df.tmp
# Replace fuseblk FS Type by exfat value from "lsblk --fs /mnt/data" command
while read line; do fsmnt=$(echo $line | awk '{print $1}'); fstype=$(lsblk -o NAME,FSTYPE,MOUNTPOINT | grep "$fsmnt$" | awk '{print $2}'); echo $line | sed "s#fuseblk#$fstype#g"; done < /tmp/df.tmp > /tmp/df.out
cat /tmp/df.out > /tmp/df.tmp
# Add Use% -> [OK] at the end of line
while read line; do use=$(echo $line | awk '{print $6}' | sed 's/[()%]//g'); echo "$line $(fShowStatusLt $use $DISK_LIMIT)"; done < /tmp/df.tmp > /tmp/df.out
cat /tmp/df.out | sed 's/^/ Disk: /' | tee -a $FILE_LOG
rm -f /tmp/df.*

echo | tee -a $FILE_LOG
echo "DISKS STATS" | tee -a $FILE_LOG
for DISK_DEV in $(df | grep '^/dev/sd' | awk '{print $1}'); do
  DISK_TYPE=$(df -T $DISK_DEV | sed -n '2p' | awk '{print $2}')
  DISK_MNT=$(df -T $DISK_DEV | sed -n '2p' | awk '{print $7}')
  [ "$DISK_TYPE" == "btrfs" ] && fCheckBtrfs $DISK_MNT | tee -a $FILE_LOG || fCheckSmart $DISK_MNT | tee -a $FILE_LOG
done

fSendMail

exit 0
