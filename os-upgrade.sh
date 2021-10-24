#!/bin/bash
#
# crontab -e
# # Packages upgrade automatically @06:00
# 0 6 * * * $HOME/os-upgrade.sh --auto
#
# Launch command:
# sudo $HOME/os-upgrade.sh --auto
# sudo $HOME/os-upgrade.sh --manual
#

# Add /sbin path for linux command
PATH=/usr/bin:/bin:/usr/sbin:/sbin

FILE_PATH=$(readlink -f $(dirname $0))  #/home/media
FILE_NAME=$(basename $0)                #os-upgrade.sh
FILE_NAME=${FILE_NAME%.*}               #os-upgrade
FILE_DATE=$(date +'%Y%m%d-%H%M%S')
export FILE_LOG="${FILE_LOG:-/var/log/$FILE_NAME.log}"
export FILE_LOG_ERRORS="${FILE_LOG_ERRORS:-/var/log/$FILE_NAME.err}"

###############################################################################
### Functions

function fFilePsUnlockRm() {
  local FILE_LOCK=$1 PIDs=""
  [ -f $FILE_LOCK ] && PIDs=$(lsof $FILE_LOCK | awk '/apt/{print $2}' | xargs) && [ -n "$PIDs" ] && kill -9 $PIDs
  rm -f $FILE_LOCK
}

function fSendMail() {
  if [ -n "$(cat $FILE_LOG_ERRORS > /dev/null 2>&1 | grep -Ei "error|failed")" ]; then
    MSG_HEAD="Upgrade ended with errors!\nOS: $HOSTNAME $OS_VER - $KER_VER"
    echo -e "$MSG_HEAD\n\n$(cat $FILE_LOG_ERRORS)" | mailx -s "[$HOSTNAME@$DOMAIN] Upgrade" -- $(whoami)

  elif [ -n "$(cat $FILE_LOG > /dev/null 2>&1 | grep -Ei "completed")" ]; then
    MSG_HEAD="Upgrade is completed.\nOS: $HOSTNAME $OS_VER - $KER_VER"
    #echo -e "$MSG_HEAD\n\n$(cat $FILE_LOG)" | mailx -s "[$HOSTNAME@$DOMAIN] Upgrade" -a $FILE_LOG_ERRORS -- $(whoami)
    echo -e "$MSG_HEAD\n\n$(cat $FILE_LOG)" | mailx -s "[$HOSTNAME@$DOMAIN] Upgrade" -- $(whoami)
  fi
}

###############################################################################
### Environment Variables

# Source under this script directory
cd $(readlink -f $(dirname $0))
. .bash_colors
. os-install.env

ROOT_UID=$(id -u root)
USER_UID=$(id -u)
USER=$(id -un)

# GNU/Linux 5.4.0-72-generic x86_64
# Linux 5.4.0-1019-raspi aarch64
KER_VER="$(uname -sri)"
# OS_VER="20.04.19"
OS_VER="$(do-release-upgrade -V | cut -d' ' -f3)"
LTS=""
if [ "$(cat /etc/update-manager/release-upgrades | grep "^Prompt" | cut -d'=' -f2)" == "lts" ]; then
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

REBOOT=0
UPG_AUTO=1
TYPE="auto"
while [ $# -gt 0 ]; do
  case "$1" in 
    "-a"|"--auto")
      TYPE="auto"
      UPG_AUTO=1
      shift;;
    "-m"|"--manual")
      TYPE="manual"
      UPG_AUTO=0
      shift;;
    *)
      echo "* "
      echo "* Unknown argument: $1"
      echo "* "
      echo "* Usage: $(basename $0) [option]"
      echo "* where sub-command is one of:"
      echo "  -a, --auto                      Packages upgrade automatically"
      echo "  -m, --manual                    Packages upgrade manually"
      echo "* "
      echo "* Example:"
      echo "* $(dirname $(readlink -f $(basename $0)))/$(basename $0) --auto"
      echo "* $(dirname $(readlink -f $(basename $0)))/$(basename $0) --manual"
      exit 1
      shift;; 
  esac
done

[ -z "$TYPE" ] && echoyellow "* " && echoyellow "* Please run sudo $0 --help" && echoyellow "* " && exit 1

rm -f $FILE_LOG $FILE_LOG_ERRORS

###############################################################################
### Script

runstart=$(date +%s)
echo "* Command: $0 $@" | tee -a $FILE_LOG $FILE_LOG_ERRORS
echo "* Start time: $(date)" | tee -a $FILE_LOG $FILE_LOG_ERRORS

echo -e "* \n* Command type: $TYPE" | tee -a $FILE_LOG $FILE_LOG_ERRORS

if [ "$(date +'%a')" == "Fri" ]; then
  
  ./owncloud.sh --cleanup

  echo "* [fs] Purge unused files in /mnt/data" | tee -a $FILE_LOG $FILE_LOG_ERRORS
  find /mnt/data -type f -name "[D|d]esktop.ini" -delete
  find /mnt/data -type f -name "Thumbs.db" -delete
  find /mnt/data -type f -name ".picasa.ini" -delete
  find /mnt/data -type f -name "\~\$*" -delete
  find /mnt/data -type d -name ".recycle" -delete
  rm -Rf /share/Public/.bin/*
  rm -Rf /share/Users/*/.bin/
  for U in $(ls /share/Users); do
    mkdir -p /share/Users/$U/.bin/
  done

  echo "* [log] Free up disk space" | tee -a $FILE_LOG $FILE_LOG_ERRORS
  # Delete files older than 1 month
  find /var/log -type f -mtime +30 -delete
  # Delete all .gz, rotated and old files
  find /var/log -type f -regex ".*\.gz$" -delete
  find /var/log -type f -regex ".*\.[0-9]$" -delete
  find /var/log -type f -regex ".*\.old$" -delete
  # Set to empty log files
  #for f in $(find /var/log -type f); do > $f; done

  if [ $(dpkg --list | grep -E "linux-image-[0-9]+|linux-headers-[0-9]+" | grep -v $(uname -r | sed 's/-generic//g') | wc -l) -gt 0 ]; then
    echo "* [dpkg] Remove All Unused Linux Kernel Headers and Images" | tee -a $FILE_LOG $FILE_LOG_ERRORS
    dpkg --list | grep -E "linux-image-|linux-headers-" | grep -v $(uname -r | sed 's/-generic//g') | awk '{print $2}' | xargs apt -y remove --purge 2>&1 | tee -a $FILE_LOG_ERRORS
    update-initramfs -u 2>&1 | tee -a $FILE_LOG_ERRORS
  fi
fi


./owncloud.sh --upgrade


echo "* " | tee -a $FILE_LOG $FILE_LOG_ERRORS
echo "* [Ubuntu] Checking for updates, please wait..." | tee -a $FILE_LOG $FILE_LOG_ERRORS
apt update 2>&1 | tee -a $FILE_LOG_ERRORS
pkgInstalled=$(apt list --installed 2> /dev/null | grep "installed" | wc -l)
pkgUpgradable=$(apt list --upgradable 2> /dev/null | grep "upgradable" | wc -l)
pkgDowngradeNb=0
if [ -f ./os-downgrade.conf ]; then
  pkgDowngradeList=$(cat ./os-downgrade.conf | grep -v '^#' | cut -d' ' -f1 | xargs | sed -e 's/ /|/g')
  pkgDowngradeNb=$(cat ./os-downgrade.conf | grep -v '^#' | cut -d' ' -f1 | wc -l)
  
  # Remove a hold on all Packages from apt upgrade
  apt-mark unhold $(apt-mark showhold) > /dev/null 2>&1
  # Exclude Specific Package from apt upgrade
  for pkg in $pkgDowngradeList; do apt-mark hold $pkg > /dev/null 2>&1; done
fi
pkgUpgradable=$(($pkgUpgradable - $pkgDowngradeNb))
echo "* $pkgInstalled packages are installed." | tee -a $FILE_LOG $FILE_LOG_ERRORS
echo "* $pkgUpgradable packages can be upgraded." | tee -a $FILE_LOG $FILE_LOG_ERRORS
if [ $pkgUpgradable -gt 0 ] && [ $UPG_AUTO -eq 1 ]; then
#  echo "* Upgrade Ubuntu packages? [Y/n] y"
  answer="y"
elif [ $pkgUpgradable -gt 0 ] && [ $pkgDowngradeNb -gt 0 ]; then
  echo "* "
  echo "* Packages partial upgradable:"
  apt list --upgradable 2> /dev/null | awk '/upgradable/{print $1}' | awk -F/ '{print $1}' | grep -vE "$pkgDowngradeList" | sed 's/^/- /'
  echo -n "* Partial Upgrade Ubuntu packages? [Y/n] "
  read answer
elif [ $pkgUpgradable -gt 0 ]; then
  echo "* "
  echo "* Packages upgradable:"
  apt list --upgradable 2> /dev/null | awk '/upgradable/{print $1}' | awk -F/ '{print $1}' | sed 's/^/- /'
  echo -n "* Upgrade Ubuntu packages? [Y/n] "
  read answer
fi
if [ $pkgUpgradable -eq 0 ]; then
    echogreen "* [Ubuntu] is up to date."
    echo "* [Ubuntu] is up to date." | tee -a $FILE_LOG $FILE_LOG_ERRORS > /dev/null
    
elif [ $(echo "$answer" | grep -i "^y") ] || [ -z "$answer" ]; then

  if [ $pkgUpgradable -gt 0 ]; then
    # Fix Could not get lock /var/lib/dpkg/lock
    fFilePsUnlockRm /var/lib/dpkg/lock
    fFilePsUnlockRm /var/lib/dpkg/lock-frontend
    fFilePsUnlockRm /var/lib/apt/lists/lock
    fFilePsUnlockRm /var/lib/apt/lists/lock-frontend
    fFilePsUnlockRm /var/cache/apt/archives/lock
  fi
  if [ $pkgUpgradable -gt 0 ] && [ $pkgDowngradeNb -gt 0 ]; then
    echo "* " | tee -a $FILE_LOG $FILE_LOG_ERRORS
    echo "* [Ubuntu] Partial Upgrade packages" | tee -a $FILE_LOG $FILE_LOG_ERRORS
    apt list --upgradable 2> /dev/null | awk '/upgradable/{print $1}' | awk -F/ '{print $1}' | grep -vE "$pkgDowngradeList" | sed 's/^/- /' | tee -a $FILE_LOG $FILE_LOG_ERRORS

    # Run partial upgrade packages
    apt list --upgradable 2> /dev/null | awk '/upgradable/{print $1}' | awk -F/ '{print $1}' | grep -vE "$pkgDowngradeList" | xargs apt -y upgrade 2>&1 | tee -a $FILE_LOG_ERRORS
    if [ $? -ne 0 ]; then
      echored "* [apt] Upgrade command failed! \nPlease check the log..."
      echo "* [apt] Upgrade command failed! \nPlease check the log..." | tee -a $FILE_LOG $FILE_LOG_ERRORS > /dev/null
      [ $UPG_AUTO -eq 1 ] && fSendMail
      exit 1
    fi
  
  elif [ $pkgUpgradable -gt 0 ]; then
    echo "* " | tee -a $FILE_LOG $FILE_LOG_ERRORS
    echo "* [Ubuntu] Upgrade packages" | tee -a $FILE_LOG $FILE_LOG_ERRORS
    apt list --upgradable 2> /dev/null | awk '/upgradable/{print $1}' | awk -F/ '{print $1}' | sed 's/^/- /' | tee -a $FILE_LOG $FILE_LOG_ERRORS

    # Run upgrade packages
    apt -y upgrade 2>&1 | tee -a $FILE_LOG_ERRORS
    if [ $? -ne 0 ]; then
      echored "* [apt] Upgrade command failed! \nPlease check the log..."
      echo "* [apt] Upgrade command failed! \nPlease check the log..." | tee -a $FILE_LOG $FILE_LOG_ERRORS > /dev/null
      [ $UPG_AUTO -eq 1 ] && fSendMail
      exit 1
    fi
  else
  
    echogreen "* [Ubuntu] is up to date."
    echo "* [Ubuntu] is up to date." | tee -a $FILE_LOG $FILE_LOG_ERRORS > /dev/null
  fi
  if [ $pkgUpgradable -gt 0 ]; then
    echo "* [Ubuntu] Upgrade distribution"
    # Run dist-upgrade packages
    apt -y dist-upgrade 2>&1 | tee -a $FILE_LOG_ERRORS
    if [ $? -ne 0 ]; then
      echored "* [apt] Dist-Upgrade command failed! \nPlease check the log..."
      echo "* [apt] Dist-Upgrade command failed! \nPlease check the log..." | tee -a $FILE_LOG $FILE_LOG_ERRORS > /dev/null
      [ $UPG_AUTO -eq 1 ] && fSendMail
      exit 1
    fi

    # Remove unused packages
    apt -y autoremove 2>&1 | tee -a $FILE_LOG_ERRORS

    # Fix docker dependency w/ netfilter-persistent
    if [ $(cat /lib/systemd/system/docker.service | grep netfilter-persistent | wc -l) -eq 0 ]; then
      #sed -i 's/^After=.*/After=network-online.target netfilter-persistent.service containerd.service smbd.service/g' /lib/systemd/system/docker.service
      sed -i 's/^After=.*/After=network-online.target netfilter-persistent.service containerd.service/g' /lib/systemd/system/docker.service
      systemctl daemon-reload
      systemctl restart docker
    fi
    
    echoblue "* [Ubuntu] Upgrade is completed."
    echo "* [Ubuntu] Upgrade is completed." | tee -a $FILE_LOG $FILE_LOG_ERRORS > /dev/null
  fi

else
  echored "* [Ubuntu] is not updated."
  echo "* [Ubuntu] is not updated." | tee -a $FILE_LOG $FILE_LOG_ERRORS > /dev/null
fi


echo "* " | tee -a $FILE_LOG $FILE_LOG_ERRORS
echo "* [Ubuntu] Checking for new release, please wait..." | tee -a $FILE_LOG $FILE_LOG_ERRORS
if [ -n "$(do-release-upgrade -m server --devel-release -c | grep "New release")" ]; then
  echo "* [Ubuntu] Upgrade release from $OS_VER to $(do-release-upgrade -m server --devel-release -c | grep "New release" | cut -d"'" -f2) $LTS" | tee -a $FILE_LOG $FILE_LOG_ERRORS
  echo "* " | tee -a $FILE_LOG $FILE_LOG_ERRORS
  echo "* Please run: sudo do-release-upgrade -m server --devel-release --quiet" | tee -a $FILE_LOG $FILE_LOG_ERRORS
  #do-release-upgrade -m server --devel-release --quiet
  if [ $? -ne 0 ]; then
    echored "* [Ubuntu] Do-Release-Upgrade command failed! \nPlease check the log..."
    echo "* [Ubuntu] Do-Release-Upgrade command failed! \nPlease check the log..." | tee -a $FILE_LOG $FILE_LOG_ERRORS > /dev/null
    [ $UPG_AUTO -eq 1 ] && fSendMail
    exit 1
  fi

  #echoblue "* [Ubuntu] Upgrade realase is completed."
  #echo "* [Ubuntu] Upgrade realase is completed." | tee -a $FILE_LOG $FILE_LOG_ERRORS > /dev/null
else
  echogreen "* [Ubuntu] Release $OS_VER is up to date."
  echo "* [Ubuntu] Release $OS_VER is up to date." | tee -a $FILE_LOG $FILE_LOG_ERRORS > /dev/null
fi


# Post upgrade cleanup
# rmdir: failed to remove '/lib/modules/5.4.0-1018-raspi': Directory not empty
if [ -f $FILE_LOG_ERRORS ] && [ -n "$(cat $FILE_LOG_ERRORS | grep "rmdir: failed to remove '/lib/modules/")" ]; then
  rm -R $(cat $FILE_LOG_ERRORS | grep "rmdir: failed to remove '/lib/modules/" | cut -d"'" -f2) > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    sed -i "/^rmdir: failed to remove '\/lib\/modules\//d" $FILE_LOG_ERRORS
  fi
fi
# Installation finished. No error reported.
if [ -f $FILE_LOG_ERRORS ] && [ -n "$(cat $FILE_LOG_ERRORS | grep "Installation finished. No error reported.")" ]; then
  sed -i 's/^Installation finished. No error reported./Installation finished./g' $FILE_LOG_ERRORS
fi


if [ -f $FILE_LOG ] && [ -n "$(cat $FILE_LOG | grep -E "linux-firmware|linux-headers|flash-kernel")" ]; then
  echo "* " | tee -a $FILE_LOG $FILE_LOG_ERRORS
  if [ $UPG_AUTO -eq 1 ]; then
    answer="y"
  else
    echo -n "* Reboot to complete the upgrade? [Y/n] "
    read answer
  fi
  if [ -n "$(echo $answer | grep -i "^y")" ] || [ -z "$answer" ]; then
    echo "* Rebooting to complete the upgrade..." | tee -a $FILE_LOG $FILE_LOG_ERRORS
    REBOOT=1
  fi
fi


echo "* " | tee -a $FILE_LOG $FILE_LOG_ERRORS
echo "* End time: $(date)" | tee -a $FILE_LOG $FILE_LOG_ERRORS
runend=$(date +%s)
runtime=$((runend-runstart))
echo "* Elapsed time: $(($runtime / 3600))hrs $((($runtime / 60) % 60))min $(($runtime % 60))sec" | tee -a $FILE_LOG $FILE_LOG_ERRORS

[ $UPG_AUTO -eq 1 ] && fSendMail
if [ $REBOOT -eq 1 ]; then
  #/sbin/reboot
  shutdown -r now
fi

exit 0