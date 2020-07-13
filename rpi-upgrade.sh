#!/bin/bash
#
# Launch command:
# sudo $HOME/rpi-upgrade.sh 2>&1 | tee /var/log/rpi-upgrade.log
# sudo $HOME/rpi-upgrade.sh --quiet |& tee /var/log/rpi-upgrade.log
#
# Restore backup data:
# sudo -i
# docker stop owncloud
# rm -Rf /var/docker/owncloud
# tar -zxf /var/docker/owncloud-bkp/docker-owncloud-10.1.0_20191026-222235.tar.gz -C /
# chown -R www-data:www-data /var/docker/owncloud
# exit
# cd ~/docker-media
# Update .env file with: OWNCLOUD_VERSION=10.1.0
# ./docker-run.sh
#

FILE_PATH=$(readlink -f $(dirname $0))  #/home/media
FILE_NAME=$(basename $0)                #rpi-upgrade.sh
FILE_NAME=${FILE_NAME%.*}               #rpi-upgrade
FILE_DATE=$(date +'%Y%m%d-%H%M%S')
FILE_LOG="/var/log/$FILE_NAME.log"
FILE_MAIL="/var/log/$FILE_NAME-mail.log"

DOCK_PATH="$FILE_PATH/docker-media"
DOCK_ENV="$DOCK_PATH/.env"
export COMPOSE_INTERACTIVE_NO_CLI=1
# Run jq command via docker
jq="docker run -i local/jq"
jq="jq"

REBOOT=0
QUIET=0
if [ "$1" == "-q" ] || [ "$1" == "--quiet" ]; then
  QUIET=1
fi

function fDockerBackup() {
  NAME=$1
  NAME_APP=$2
  NAME_VER=$3

  echo "* "
  echo "* [docker] Backup docker $NAME $NAME_VER"
  docker stop $NAME > /dev/null 2>&1
  echo "* [tar] Archiving $NAME_APP into docker-$NAME-${NAME_VER}_$FILE_DATE.tar.gz"
  # /var/docker/owncloud-bkp
  BKP_PATH=$NAME_APP-bkp
  mkdir -p $BKP_PATH
  cd $BKP_PATH
  
  # Keep only the last 3 more recent backup files
  if [ $(ls -tr docker-$NAME-* 2> /dev/null | wc -l) -gt 3 ]; then
    NB=$(eval echo $(($(ls -tr docker-$NAME-* | wc -l) -3)))
    echo "* [fs] Keep only 3 last backup, then removing these old files under $BKP_PATH"
    ls -tr docker-$NAME-* | head -n$NB
    ls -tr docker-$NAME-* | head -n$NB | xargs rm -f
  fi
  
  tar -czf docker-$NAME-${NAME_VER}_$FILE_DATE.tar.gz $NAME_APP 2> /dev/null
  # Moves to the previous directory
  cd - > /dev/null
  docker start $NAME > /dev/null 2>&1
  echo "* "
}

function fDockerImageTagExists() {
  # apt -y install jq
  # Return true/false
  if [ $(curl -s H https://hub.docker.com/v2/repositories/$1/tags/?page_size=10000 | $jq -r "[.results | .[] | .name == \"$2\"] | any") == true ]; then
    echo 1
  else
    echo 0
  fi
}

function fSendMail() {
  
  if [ -f $FILE_LOG ]; then
    if [ -n "$(cat $FILE_LOG | grep -Ei "error|failed")" ]; then

      MSG_HEAD="Upgrade $HOSTNAME $OS_VER failed!\n\n$pkgInstalled packages are installed.\n$pkgUpgradable packages can be upgraded."
      #echo -e "Subject: [$HOSTNAME@$DOMAIN] Upgrade @ $rundate\n\n$MSG_HEAD\n\n$(cat $FILE_LOG)" | msmtp $(whoami)
      echo -e "$MSG_HEAD\n\n$(cat $FILE_LOG)" | mailx -s "[$HOSTNAME@$DOMAIN] Upgrade @ $rundate" -- $(whoami)

    elif [ -n "$(cat $FILE_LOG | grep "\[docker\] owncloud $OC_VER upgrade completed.")" ] || 
         [ -n "$(cat $FILE_LOG | grep "\[docker\] owncloud $OC_VER Third-Party Apps upgrade completed.")" ] || 
         [ -n "$(cat $FILE_LOG | grep "\[Ubuntu\] Upgrade completed.")" ] || 
         [ -n "$(cat $FILE_LOG | grep "\[Ubuntu\] Upgrade release")" ] || 
         [ -n "$(cat $FILE_LOG | grep "\[VBox\] Upgrade $VBOX_VER completed.")" ]; then
       
      MSG_HEAD="Upgrade $HOSTNAME $OS_VER completed.\n\n$pkgInstalled packages are installed.\n$pkgUpgradable packages can be upgraded."
      #echo -e "Subject: [$HOSTNAME@$DOMAIN] Upgrade @ $rundate\n\n$MSG_HEAD\n\n$(cat $FILE_LOG)" | msmtp $(whoami)
      echo -e "$MSG_HEAD\n\n$(cat $FILE_MAIL)" | mailx -s "[$HOSTNAME@$DOMAIN] Upgrade @ $rundate" -a $FILE_LOG -- $(whoami)
    fi
  fi
}

# Source syntax color script
cd $FILE_PATH
. .bash_colors

# Source environment variables
. $DOCK_ENV > /dev/null 2>&1

if [ ! -f $FILE_LOG ] || [ $(cat $FILE_LOG | wc -l) -gt 0 ] || [ "$(ls -l --time-style=long-iso $FILE_LOG | awk '{print $6" "$7}')" != "$(date +'%Y-%m-%d %H:%M')" ]; then
  echo "* "
  echored "* $FILE_LOG file not found!"
  echo "* "
  echo "* Please run:"
  echoyellow "* sudo $FILE_PATH/$FILE_NAME.sh --quiet 2>&1 | tee $FILE_LOG"
  exit 1
fi
rm -f $FILE_MAIL

runstart=$(date +%s)
rundate="$(date)"
echo "* Command: $0 $@" | tee -a $FILE_MAIL
echo "* Start time: $(date)" | tee -a $FILE_MAIL
echo "* " | tee -a $FILE_MAIL

NAME=owncloud
NAME_APP=/var/docker/owncloud
VER_OLD=$(cat $DOCK_ENV | grep "OWNCLOUD_VERSION" | cut -d'=' -f2)
VER_NEW=$(git ls-remote --tags --refs https://github.com/owncloud/core.git | cut -d'v' -f2 | grep -v -E "alpha|beta|RC" | sort -nr 2> /dev/null | head -n1)

echo "* " | tee -a $FILE_MAIL
echo "* [docker] $NAME Checking for updates, please wait..." | tee -a $FILE_MAIL

UPDATE=""
if [ "$VER_OLD" == "$VER_NEW" ] || [ $(fDockerImageTagExists owncloud/server $VER_NEW) -eq 0 ]; then
  UPDATE="NO"
  VER_NEW=$VER_OLD
  echogreen "* [docker] $NAME $VER_OLD is up to date!"
  echo "* [docker] $NAME $VER_OLD is up to date!" >> $FILE_MAIL
else

  echoblue "* [docker] Current version $NAME $VER_OLD"
  echo "* [docker] Current version $NAME $VER_OLD" >> $FILE_MAIL
  echo "* [git] Last found $NAME version:"
  git ls-remote --tags --refs https://github.com/owncloud/core.git | cut -d'v' -f2 | grep -v -E "alpha|beta|RC" | sort -nr 2> /dev/null | head -n5
  if [ $QUIET -eq 1 ]; then
    echo "* Enter $NAME version? <$VER_NEW> "
    answer=
  else
    echo -n "* Enter $NAME version? <$VER_NEW> "
    read answer
  fi
  echo "* Enter $NAME version? <$VER_NEW> $answer"
  if [ -z "$answer" ]; then
    UPDATE="OK"
  elif [ "$VER_OLD" == "$answer" ]; then
    UPDATE="NO"
    echored "* [docker] $NAME is still on $VER_OLD."
    echo "* [docker] $NAME is still on $VER_OLD." >> $FILE_MAIL
    VER_NEW=$VER_OLD
  elif [ $(git ls-remote --tags --refs https://github.com/owncloud/core.git | cut -d'v' -f2 | grep -v -E "alpha|beta|RC" | grep "^$answer") ]; then
    UPDATE="OK"
    VER_NEW=$answer
  else
    UPDATE="NO"
    echored "* [docker] $NAME is not updated to $VER_NEW."
    echo "* [docker] $NAME is not updated to $VER_NEW." >> $FILE_MAIL
    VER_NEW=$VER_OLD
  fi
fi
OC_VER=$VER_NEW


if [ "$UPDATE" == "OK" ]; then
  fDockerBackup $NAME $NAME_APP $VER_OLD
  
  echo "* [docker] $NAME Upgrading from $VER_OLD to $VER_NEW" | tee -a $FILE_MAIL
  
#  echo "* [docker] Disable $NAME Third-Party Apps:"
#  ls $NAME_APP/apps
#  for app in $(ls $NAME_APP/apps); do
#    docker exec -i $NAME /bin/bash -c "occ app:disable $app" 2>&1
#  done
#  echo "* [docker] Enable $NAME maintenance mode"
#  docker exec -i $NAME /bin/bash -c "occ maintenance:mode --on" 2>&1
  
  echo "* [docker] Building and Starting docker-compose for $NAME $VER_NEW" | tee -a $FILE_MAIL
  # docker pull owncloud/server:$VER_NEW
  sed -i "s/^OWNCLOUD_VERSION=.*/OWNCLOUD_VERSION=$VER_NEW/g" $DOCK_ENV 2>&1
  #$DOCK_PATH/docker-run.sh 2>&1
  cd $DOCK_PATH
  docker-compose up -d --no-deps --force-recreate $NAME
  cd ~

#  echo "* [docker] $NAME Upgrading to $VER_NEW"
#  docker exec -i $NAME /bin/bash -c "occ upgrade" 2>&1
  
#  echo "* [docker] $NAME Disable maintenance mode"
#  docker exec -i $NAME /bin/bash -c "occ maintenance:mode --off" 2>&1

#  echo "* [docker] $NAME Enable Third-Party Apps:"
#  ls $NAME_APP/apps
#  for app in $(ls $NAME_APP/apps); do
#    docker exec -i $NAME /bin/bash -c "occ app:enable $app" 2>&1
#  done

  echo "* [docker] Install p7zip package on $NAME" | tee -a $FILE_MAIL
  docker exec -i $NAME /bin/bash -c "apt update && apt -y install p7zip-full"

  echo "* " | tee -a $FILE_MAIL
  echo "* " | tee -a $FILE_MAIL
  echo "* " | tee -a $FILE_MAIL
  echo "* [docker] $NAME $VER_NEW upgrade completed." | tee -a $FILE_MAIL
fi

echo "* "
echo "* [healthcheck] Waiting for $NAME docker to be up and running, please wait..."
URL_TO_CHECK="http://$HOST/$NAME"
URL_PASSED=0
while [ $URL_PASSED -eq 0 ]; do
  for URL in $(echo $URL_TO_CHECK | tr "|" "\n"); do
    URL_MSG=$(curl -sSf --insecure $URL 2>&1)
    if [ $? -eq 0 ]; then
      URL_PASSED=1
      echo "* [healthcheck] Website is up $URL and running!"
    else
      URL_PASSED=0
      echo "* [healthcheck] Website is down $URL ..."
#      echo "* [healthcheck] Error: $URL_MSG"
      sleep 10
    fi
  done
done

echo "* " | tee -a $FILE_MAIL
echo "* [docker] $NAME Upgrade Third-Party Apps on Market, please wait..." | tee -a $FILE_MAIL
OCC_APPS_LOG="/var/log/occ-upgrade-apps.log"
rm -f $OCC_APPS_LOG
docker exec -i $NAME /bin/bash -c "occ market:upgrade files_mediaviewer" >> $OCC_APPS_LOG
for app in $(ls $NAME_APP/apps); do
  docker exec -i $NAME /bin/bash -c "occ market:upgrade $app" >> $OCC_APPS_LOG
done
if [ -f $OCC_APPS_LOG ] && [ $(cat $OCC_APPS_LOG | grep "App updated." | wc -l) -gt 0 ]; then
  cat $OCC_APPS_LOG | grep "App updated." | tee -a $FILE_MAIL
  echo "* " | tee -a $FILE_MAIL
  echo "* " | tee -a $FILE_MAIL
  echo "* " | tee -a $FILE_MAIL
  echo "* [docker] $NAME $VER_NEW Third-Party Apps upgrade completed." | tee -a $FILE_MAIL
else
  echogreen "* [docker] $NAME $VER_NEW Third-Party Apps are up to date!"
  echo "* [docker] $NAME $VER_NEW Third-Party Apps are up to date!" >> $FILE_MAIL
fi




if [ $(dpkg --list | grep -E "linux-image-[0-9]+|linux-headers-[0-9]+" | grep -v $(uname -r) | wc -l) -gt 0 ]; then
  echo "* " | tee -a $FILE_MAIL
  echo "* [dpkg] Remove All Unused Linux Kernel Headers and Images" | tee -a $FILE_MAIL
  dpkg --list | grep -E "linux-image-[0-9]+|linux-headers-[0-9]+" | grep -v $(uname -r) | awk '{print $2}' | sort -V | sed -n '/'`uname -r`'/q;p' | xargs sudo apt -y remove --purge
  #update-initramfs -u
fi

echo "* " | tee -a $FILE_MAIL
echo "* [apt] Ubuntu Checking for updates, please wait..." | tee -a $FILE_MAIL
sudo apt update > /dev/null 2>&1
pkgInstalled=$(apt list --installed 2> /dev/null | grep "installed" | wc -l)
pkgUpgradable=$(apt list --upgradable 2> /dev/null | grep "upgradable" | wc -l)
echo "* " | tee -a $FILE_MAIL
echo "* $pkgInstalled packages are installed." | tee -a $FILE_MAIL
echo "* $pkgUpgradable packages can be upgraded." | tee -a $FILE_MAIL
echo "* " | tee -a $FILE_MAIL
if [ $pkgUpgradable -gt 0 ] && [ $QUIET -eq 1 ]; then
  echo "* Upgrade Ubuntu packages? [Y/n] y"
  answer="y"
elif [ $pkgUpgradable -gt 0 ]; then
  echo -n "* Upgrade Ubuntu packages? [Y/n] "
  read answer
  echo "* Upgrade Ubuntu packages? [Y/n] $answer" >> $FILE_MAIL
fi
if [ $pkgUpgradable -eq 0 ]; then
    echogreen "* [Ubuntu] is up to date!"
    echo "* [Ubuntu] is up to date!" >> $FILE_MAIL
    
elif [ $(echo "$answer" | grep -i "^y") ] || [ -z "$answer" ]; then

  if [ $pkgUpgradable -gt 0 ]; then
    echo "* [apt] Upgrade packages" | tee -a $FILE_MAIL
    apt list --upgradable 2> /dev/null | grep "upgradable" >> $FILE_MAIL
    # Run upgrade packages
    sudo apt -y upgrade
    if [ $? -ne 0 ]; then
      echored "* [apt] Upgrade command failed! \nPlease check the log..."
      echo "* [apt] Upgrade command failed! \nPlease check the log..." >> $FILE_MAIL
      exit 1
    fi
    echo "* [apt] Upgrade system"
    # Run full-upgrade packages
    sudo apt -y full-upgrade
    if [ $? -ne 0 ]; then
      echored "* [apt] Full-Upgrade command failed! \nPlease check the log..."
      echo "* [apt] Full-Upgrade command failed! \nPlease check the log..." >> $FILE_MAIL
      exit 1
    fi

    # Remove unused packages
    sudo apt -y autoremove

    # Fix docker dependency w/ netfilter-persistent
    sudo sed -i 's/^After=.*/After=network-online.target netfilter-persistent.service containerd.service smbd.service/g' /lib/systemd/system/docker.service
    sudo systemctl daemon-reload
    sudo systemctl restart docker
    
    echo "* " | tee -a $FILE_MAIL
    echo "* " | tee -a $FILE_MAIL
    echo "* " | tee -a $FILE_MAIL
    echo "* [Ubuntu] Upgrade completed." | tee -a $FILE_MAIL
  else
    echogreen "* [Ubuntu] is up to date!"
    echo "* [Ubuntu] is up to date!" >> $FILE_MAIL
  fi
else
  echored "* [Ubuntu] is not updated."
  echo "* [Ubuntu] is not updated." >> $FILE_MAIL
fi


echo "* " | tee -a $FILE_MAIL
echo "* [Ubuntu] Checking for new release, please wait..." | tee -a $FILE_MAIL
# OS_VER="20.04.19"
OS_VER="$(do-release-upgrade -V | cut -d' ' -f3)"
LTS=""
if [ "$(cat /etc/update-manager/release-upgrades | grep "^Prompt" | cut -d'=' -f2)" == "lts" ]; then
  # OS_VER="20.04.19 LTS"
  OS_VER="$OS_VER LTS"
  LTS="LTS"
fi
if [ -n "$(do-release-upgrade -m server --devel-release -c | grep 'New release')" ]; then
  echo "* [Ubuntu] Upgrade release from $OS_VER to $(do-release-upgrade -m server --devel-release -c | grep 'New release' | cut -d"'" -f2) $LTS" | tee -a $FILE_MAIL
  echo "* " | tee -a $FILE_MAIL
  echo "* Please run: sudo do-release-upgrade -m server --devel-release --quiet" | tee -a $FILE_MAIL
  #sudo do-release-upgrade -m server --devel-release --quiet
  if [ $? -ne 0 ]; then
    echored "* [Ubuntu] Do-Release-Upgrade command failed! \nPlease check the log..."
    echo "* [Ubuntu] Do-Release-Upgrade command failed! \nPlease check the log..." | tee -a $FILE_MAIL
    exit 1
  fi

  #echo "* "
  #echo "* "
  #echo "* "
  #echo "* [Ubuntu] Upgrade realase completed."
else
  echogreen "* [Ubuntu] Release $OS_VER is up to date!"
  echo "* [Ubuntu] Release $OS_VER is up to date!" >> $FILE_MAIL
fi


if [ -f $FILE_LOG ] && [ -n "$(cat $FILE_LOG | grep -E "linux-firmware|linux-headers")" ]; then
  echo "* " | tee -a $FILE_MAIL
  echo "* " | tee -a $FILE_MAIL
  echo "* " | tee -a $FILE_MAIL
  if [ $QUIET -eq 1 ]; then
    echo "* Reboot to complete the upgrade? [Y/n] y"
    answer="y"
  else
    echo -n "* Reboot to complete the upgrade? [Y/n] "
    read answer
  fi
  echo "* Reboot to complete the upgrade? [Y/n] $answer" >> $FILE_MAIL
  if [ -n "$(echo $answer | grep -i '^y')" ] || [ -z "$answer" ]; then
    REBOOT=1
  fi
fi


echo "* " | tee -a $FILE_MAIL
echo "* End time: $(date)" | tee -a $FILE_MAIL
runend=$(date +%s)
runtime=$((runend-runstart))
echo "* Elapsed time: $(($runtime / 3600))hrs $((($runtime / 60) % 60))min $(($runtime % 60))sec" | tee -a $FILE_MAIL

fSendMail
if [ $REBOOT -eq 1 ]; then
  sudo reboot
fi
exit 0