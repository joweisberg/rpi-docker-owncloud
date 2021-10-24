#!/bin/bash
#
# Change welcome message
#

###############################################################################
### Functions

function fShowStatus() {
  local CURR=$1 MAX=$2
  echo "[$([ $CURR -eq $MAX ] && echo $(echogreen "OK") || echo $(echoyellow "!!"))]"
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
USER=$(id -un)

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

# Check if run as non root
if [ $USER_UID -eq $ROOT_UID ] ; then
  echo "* "
  echored "* You must be non root to do that!"
  echo "* "
  exit 1
fi

###############################################################################
### Script

echo
# Welcome to Ubuntu 20.04.1 LTS (GNU/Linux 5.4.0-52-generic x86_64)
#printf "Welcome to %s (%s %s %s)\n" "$PRETTY_NAME" "$(uname -o)" "$(uname -r)" "$(uname -m)"
echo "Welcome to $NAME $OS_VER ($KER_VER)"

echo
echo "GENERAL SYSTEM INFORMATION"
# media@htpc.home
# OS: Ubuntu 20.04.1 LTS (Focal Fossa)
# Kernel: x86_64 Linux 5.4.0-52-generic
# Uptime: 4d 17h 9m
# Packages: 1303
# Shell: bash 5.0.17
# CPU: Intel(R) Core(TM) i5-4590T @ 4x 3GHz [39.5°C]
# GPU: Xeon E3-1200 v3/4th Gen Core Processor Integrated Graphics (i915)
# OpenGL: Mesa DRI Intel(R) HD Graphics 4600 (HSW GT2) [OpenGL 3.0 Mesa 20.2.6]
# Resolution: 1920x1080
# GTK Theme: Adwaita [GTK-3.24.20-0ubuntu1]
# RAM: 3.01G / 15.71G (19%)
# SWAP: 0.00G / 0.00G (0%)
# Processes: 332
# Users account: 51 / 51 [OK]
# Users shell: 2 / 2 [OK]
# Users logged in: 1

#echo "$(echored " $(whoami)")@$(host $HOSTNAME | awk '{print $1}')"
echo "$(echored " $(id -un)")@$HOSTNAME.$(cat /etc/resolv.conf | grep '^search' | awk '{print $2}')"
echo "$(echored " OS: ")$NAME $OS_VER ($VERSION_CODENAME)"
echo "$(echored " Kernel: ")$KER_VER"
echo "$(echored " Uptime: ")$(uptime | awk -F'( |,|:)+' '{d=h=m=0; if ($7=="min") m=$6; else {if ($7~/^day/) {d=$6;h=$8;m=$9} else {h=$6;m=$7}}} {print d+0"d",h+0"h",m+0"m"}')"
echo "$(echored " Packages installed: ")$(apt list --installed 2> /dev/null | grep "installed" | wc -l)"
CHK_DT=/tmp/aptCheckDate.txt
if [ ! -f $CHK_DT ] || [ $(cat $CHK_DT) -ne $(date +'%Y%m%d') ]; then
  sudo apt update > /dev/null 2>&1
  # Save current date, check daily
  date +'%Y%m%d' > $CHK_DT
fi
pkgUpgradable=$(apt list --upgradable 2> /dev/null | grep "upgradable" | wc -l)
pkgDowngradeNb=0
if [ -f os-downgrade.conf ]; then
  pkgDowngradeNb=$(cat os-downgrade.conf | grep -v '^#' | cut -d' ' -f1 | wc -l)
fi
if [ $pkgUpgradable -gt 0 ]; then
  pkgUpgradable=$(($pkgUpgradable - $pkgDowngradeNb))
fi
echo "$(echored " Packages upgradable: ")$pkgUpgradable $(fShowStatus $pkgUpgradable 0)"
echo "$(echored " Shell: ")$(echo "bash $BASH_VERSION" | cut -d'(' -f1)"

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
  CPU_TEXT="[$(echogreen "$CPU_TEMP°C")]"
fi
echo "$(echored " CPU: ")$CPU_NAME @ ${CPU_NCORE}x $CPU_SPEED $CPU_TEXT"

GPU_NAME=$(lshw -C video 2> /dev/null | grep "product:" | awk -F':' '{print $2}' | awk -F'Controller' '{print $1}' | sed 's/ *$//g' | sed 's/^ *//g')
# Remove the trailing and leading spaces 
#GPU_NAME=$(echo $GPU_NAME | sed 's/ *$//g' | sed 's/^ *//g')
GPU_DRIVER=$(lshw -C video 2> /dev/null | grep "driver" | awk '{print $2}' | awk -F'=' '{print $2}')
GPU_RES=$(xrandr 2> /dev/null | grep '*' | awk '{print $1}')
if [ -n "$GPU_NAME" ]; then
  echo "$(echored " GPU: ")$GPU_NAME ($GPU_DRIVER)"
  # OpenGL: Mesa DRI Intel(R) HD Graphics 4600 (HSW GT2) [OpenGL 3.0 Mesa 20.2.6]
  echo "$(echored " OpenGL: ")$(glxinfo | awk -F: '/^OpenGL renderer string/ {print $2}' | sed 's/^ *//g') [OpenGL $(glxinfo | awk -F: '/^OpenGL version string/ {print $2}' | sed 's/^ *//g')]"
  echo "$(echored " Resolution: ")$GPU_RES"
  echo "$(echored " GTK Theme: ")$(gsettings get org.gnome.desktop.interface gtk-theme | cut -d"'" -f2) [GTK-$(dpkg -s libgtk-3-0 2> /dev/null | grep '^Version' | cut -d' ' -f2)]"
#  else
#    echo "$(echored " GPU: ")N/A"
#    echo "$(echored " OpenGL: ")N/A"
#    echo "$(echored " Resolution: ")N/A"
#    echo "$(echored " GTK Theme: ")N/A"
fi

echo "$(echored " RAM: ")$(free -m | grep ^Mem | awk '{printf("%.2fG / %.2fG (%.0f%%)",$3/1024,$2/1024,$2!=0?$3*100/$2:0)}')"
echo "$(echored " SWAP: ")$(free -m | grep ^Swap | awk '{printf("%.2fG / %.2fG (%.0f%%)",$3/1024,$2/1024,$2!=0?$3*100/$2:0)}')"
echo "$(echored " Processes: ")$(ps -ax | wc -l)"
echo "$(echored " Users account: ")$(cat /etc/passwd | wc -l) / $OS_USER_MAX $(fShowStatus $(cat /etc/passwd | wc -l) $OS_USER_MAX)"
echo "$(echored " Users shell: ")$(cat /etc/passwd | grep "$(cat /etc/shells)" | wc -l) / $OS_SHELL_MAX $(fShowStatus $(cat /etc/passwd | grep "$(cat /etc/shells)" | wc -l) $OS_SHELL_MAX)"
echo "$(echored " Users logged in: ")$(w -h | grep -v "$(date +%H:%M)" | wc -l)"

echo
echo "DISKS USAGE"
# Disk: /boot/efi [vfat] 7.8M / 504M (2%)
#df -HT | grep -E '^/dev|/mnt' | awk '{print $7" ["$2"] "$4" / "$3" ("$6")"}' | sed "s/^/$(echored ' Disk: ')/"
df -HT | grep -E '^/dev|/mnt' | awk '{print $7" ["$2"] "$4" / "$3" ("$6")"}' > /tmp/df.tmp
# Replace fuseblk FS Type by exfat value from "lsblk --fs /mnt/data" command
while read line; do fsmnt=$(echo $line | awk '{print $1}'); fstype=$(lsblk -o NAME,FSTYPE,MOUNTPOINT | grep "$fsmnt$" | awk '{print $2}'); echo $line | sed "s#fuseblk#$fstype#g"; done < /tmp/df.tmp > /tmp/df.out
cat /tmp/df.out | sed "s/^/$(echored ' Disk: ')/"
rm /tmp/df.tmp /tmp/df.out

echo
echo "NETWORK INFORMATION"
ETH_DEV="$(ip route | grep default | head -n1 | sed -e 's/^.*dev.//' -e 's/.proto.*//')"
ETH_ADR=$(ip -4 address show $ETH_DEV | grep inet | awk '{print $2}')
ETH_DNS=$(ip route | grep '^default' | grep $ETH_DEV | awk '{print $3}')
if [ -z $ETH_DNS ]; then
  ETH_DNS=$(ip route | grep -v '^default' | grep "$ETH_DEV proto kernel" | awk '{print $9}')
fi
ETH_GTW=$(curl -4s wgetip.com)
echo "$(echored " Local domain: ")$(cat /etc/resolv.conf | grep '^search' | awk '{print $2}')"
echo "$(echored " IPv4 network: ")$ETH_ADR $ETH_DNS [$ETH_DEV]"
#echo "$(echored " IPv4 outside: ")$ETH_GTW [$(nslookup $ETH_GTW | grep name | awk '{print $4'})]"
echo "$(echored " IPv4 outside: ")$ETH_GTW [$DOMAIN]"

echo
echo "DOCKER SYSTEM INFORMATION"
echo "$(echored " Processes: ")$(docker ps | wc -l)"
echo "$(echored " Images: ")$(docker system df | grep Images | awk '{print $3" actives / "$2" for "$4" [Reclaimable: "$5" "$6"]"}') $(fShowStatus $(docker system df | grep Images | awk '{print $3" "$2}'))"
echo "$(echored " Containers: ")$(docker system df | grep Containers | awk '{print $3" actives / "$2" for "$4" [Reclaimable: "$5" "$6"]"}') $(fShowStatus $(docker system df | grep Containers | awk '{print $3" "$2}'))"

if [ $(cat /etc/passwd | grep "$(cat /etc/shells)" | wc -l) -ne $OS_SHELL_MAX ]; then
  echo
  echo "ACTIVE USERS SHELL"
  cat /etc/passwd | grep "$(cat /etc/shells)" | sed 's/^/ /'
fi

echo
if [ $(w -h | grep -v "$(date +%H:%M)" | wc -l) -gt 0 ]; then
  echo "ACTIVE SSH CONNECTIONS"
  w | grep -v "$(date +%H:%M)" | sed 's/^/ /'
else
  echo "NO ACTIVE SSH CONNECTION"
fi

echo
