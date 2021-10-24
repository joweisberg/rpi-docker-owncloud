#!/bin/bash
#
# Launch command:
# sudo $HOME/owncloud.sh --install 2>&1 | tee /var/log/owncloud-install.log
# sudo $HOME/owncloud.sh --backup
# sudo $HOME/owncloud.sh --cleanup
# sudo $HOME/owncloud.sh --upgrade
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
FILE_NAME=$(basename $0)                #owncloud.sh
FILE_NAME=${FILE_NAME%.*}               #owncloud
FILE_DATE=$(date +'%Y%m%d-%H%M%S')
#FILE_LOG="${FILE_LOG:-/var/log/$FILE_NAME.log}"
#FILE_LOG_ERRORS="${FILE_LOG_ERRORS:-/var/log/$FILE_NAME.err}"

###############################################################################
### Functions

function fDockerBackup() {
  local NAME=$1 NAME_APP=$2 NAME_VER=$3

  echo "* [docker] Backup $NAME $NAME_VER" | tee -a $FILE_LOG $FILE_LOG_ERRORS
  docker stop $NAME > /dev/null 2>&1

  # /var/docker/owncloud-bkp
  BKP_PATH=$NAME_APP-bkp
  mkdir -p $BKP_PATH
  cd $BKP_PATH
  
  # Keep only the last 3 more recent backup files
  if [ $(ls -tr docker-$NAME-* 2> /dev/null | wc -l) -gt 3 ]; then
    NB=$(eval echo $(($(ls -tr docker-$NAME-* | wc -l) -3)))
    echo "* [fs] Keep only 3 last backup, then removing these old files under $BKP_PATH" | tee -a $FILE_LOG $FILE_LOG_ERRORS
    ls -tr docker-$NAME-* | head -n$NB | sed 's/^/** /' | tee -a $FILE_LOG $FILE_LOG_ERRORS
    ls -tr docker-$NAME-* | head -n$NB | xargs rm -f
  fi
  
  BKP_FILE="docker-$NAME-${NAME_VER}_$FILE_DATE.tar.gz"
  echo -n "* [tar] Archiving $NAME_APP into $BKP_FILE" | tee -a $FILE_LOG $FILE_LOG_ERRORS
  tar -czf $BKP_FILE $NAME_APP 2> /dev/null
  echo " [$(ls -hs $BKP_FILE | awk '{print $1}')]" | tee -a $FILE_LOG $FILE_LOG_ERRORS

  # Moves to the previous directory
  cd - > /dev/null
  
  docker start $NAME 2>&1 | tee -a $FILE_LOG_ERRORS
  echoblue "* [docker] Backup $NAME is completed."
  echo "* [docker] Backup $NAME is completed." | tee -a $FILE_LOG $FILE_LOG_ERRORS > /dev/null
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

###############################################################################
### Environment Variables

# Source under this script directory
cd $(readlink -f $(dirname $0))
. .bash_colors

# Source environment variables
. os-install.env

ROOT_UID=$(id -u root)
USER_UID=$(id -u)
USER=$(id -un)

HOST_NAME=$(host $HOSTNAME | awk '{print $1}' | awk -F. '{print $1}')
HOST_DOMAIN=$(host $HOSTNAME | awk '{print $1}' | awk -F. '{print $2}')

DOCK_PATH="$FILE_PATH/docker-media"
DOCK_ENV="$DOCK_PATH/.env"
export COMPOSE_INTERACTIVE_NO_CLI=1
# Run jq command via docker
#jq="docker run -i local/jq"
jq="jq"

NAME=owncloud
NAME_APP=/var/docker/$NAME
NAME_VER=$(cat $DOCK_ENV | awk -F= '/^OWNCLOUD_VERSION=/{print $2}')
DOMAIN=$(cat $DOCK_ENV | awk -F= '/^DOMAIN=/{print $2}')

###############################################################################
### Pre-Script

# Check if run as root
if [ $USER_UID -ne $ROOT_UID ] ; then
  echo "* "
  echored "* You must be root to do that!"
  echo "* "
  exit 1
fi

TEST=0
QUIET=1
TYPE=""
while [ $# -gt 0 ]; do
  case "$1" in 
    "-i"|"--install")
      TYPE="install"
      shift;;
    "-u"|"--upgrade")
      TYPE="upgrade"
      shift;;
    "-b"|"--backup")
      TYPE="backup"
      shift;;
    "-r"|"--rollback")
      TYPE="rollback"
      shift;;
    "-c"|"--cleanup")
      TYPE="cleanup"
      shift;;
    "-t"|"--test")
      TEST=1
      shift;;
    "-m"|"--noauto")
      QUIET=0
      shift;;
    *)
      echo "* "
      echo "* Unknown argument: $1"
      echo "* "
      echo "* Ubuntu script must have one sub-command argument"
      echo "* Usage: $(basename $0) [option]"
      echo "* where sub-command is one of:"
      echo "  -i, --install                   Install ownCloud"
      echo "  -u, --upgrade                   Upgrade ownCloud"
      echo "  -b, --backup                    Backup ownCloud"
      echo "  -r, --rollback                  Rollback ownCloud on previous version"
      echo "  -c, --cleanup                   Cleanup conflicted copy files"
      echo "  -t, --test                      Test cleanup mode"
      echo "  -m, --noauto                    Manual upgrade version"
      echo "* "
      echo "* Example:"
      echo "* $(dirname $(readlink -f $(basename $0)))/$(basename $0) --install 2>&1 | tee /var/log/$(basename $0)-install.log"
      echo "* $(dirname $(readlink -f $(basename $0)))/$(basename $0) --upgrade --noauto"
      echo "* $(dirname $(readlink -f $(basename $0)))/$(basename $0) --backup"
      echo "* $(dirname $(readlink -f $(basename $0)))/$(basename $0) --rollback"
      echo "* $(dirname $(readlink -f $(basename $0)))/$(basename $0) --cleanup --test"
      exit 1
      shift;; 
  esac
done

[ -z "$TYPE" ] && echoyellow "* " && echoyellow "* Please run sudo $0 --help" && echoyellow "* " && exit 1

FILE_LOG="${FILE_LOG:-/var/log/$FILE_NAME-$TYPE.log}"
FILE_LOG_ERRORS="${FILE_LOG_ERRORS:-/var/log/$FILE_NAME-$TYPE.err}"

# Run script in standalone, without heritage
# Or redirect output file to parent script (variables export)
STANDALONE=1
[ "$FILE_LOG" == "/var/log/$FILE_NAME-$TYPE.log" ] && rm -f $FILE_LOG $FILE_LOG_ERRORS || STANDALONE=0

###############################################################################
### Script

runstart=$(date +%s)
[ $STANDALONE -eq 1 ] && echo "* Command: $0 $@" | tee -a $FILE_LOG $FILE_LOG_ERRORS
[ $STANDALONE -eq 1 ] && echo "* Start time: $(date)" | tee -a $FILE_LOG $FILE_LOG_ERRORS

[ $STANDALONE -eq 1 ] && [ $TEST -eq 1 ] && echo -e "* \n* Test mode: enabled" | tee -a $FILE_LOG $FILE_LOG_ERRORS
[ $STANDALONE -eq 1 ] && echo -e "* \n* Command type: $TYPE" | tee -a $FILE_LOG $FILE_LOG_ERRORS

echo "* " | tee -a $FILE_LOG $FILE_LOG_ERRORS
case "$TYPE" in
  "install")
    # Do not interprate space in variable during for loop
    SAVEIFS=$IFS
    IFS=$'\n'

    echo "* [owncloud] Reset configuration"
    docker stop $NAME > /dev/null 2>&1
    rm -f $NAME_APP/files/owncloud.db
    rm -f $NAME_APP/config/config.php
    find $NAME_APP/files/*/files_*/ -delete 2> /dev/null
    find $NAME_APP/files/*/thumbnails/* -delete 2> /dev/null
    find $NAME_APP/files/*/uploads/* -delete 2> /dev/null
    find $NAME_APP/files/*/cache/* -delete 2> /dev/null
    docker start $NAME > /dev/null 2>&1
    
    sleep 30

    echo "* "
    echo "* [owncloud] Set configuration"
    echo "* "
    docker exec -i $NAME /bin/bash -c "occ config:system:set logtimezone --value='Europe/Paris'" | sed 's/^/** /'
    sed -i "/^);/i \  'mail_domain' => 'gmail.com',\n  'mail_from_address' => 'no-reply',\n  'mail_smtpmode' => 'smtp',\n  'mail_smtphost' => 'smtp.gmail.com',\n  'mail_smtpport' => '587',\n  'mail_smtpsecure' => 'tls',\n  'mail_smtpauthtype' => 'LOGIN',\n  'mail_smtpauth' => 1,\n  'mail_smtpname' => 'jo.weisberg',\n  'mail_smtppassword' => 'J@hn2711.'," $NAME_APP/config/config.php
    # These files will be copied to the data directory of new users. Leave this directory empty if you do not want to copy any skeleton files.
    sed -i "/^);/i \  'skeletondirectory' => ''," $NAME_APP/config/config.php
    
    # Enable/Disable app based on default setup
    docker exec -i $NAME /bin/bash -c "occ app:disable firstrunwizard" | sed 's/^/** /'
    docker exec -i $NAME /bin/bash -c "occ app:enable activity" | sed 's/^/** /'
    docker exec -i $NAME /bin/bash -c "occ app:enable files_clipboard" | sed 's/^/** /'
    docker exec -i $NAME /bin/bash -c "occ app:enable extract" | sed 's/^/** /'
    docker exec -i $NAME /bin/bash -c "occ app:enable files_mediaviewer" | sed 's/^/** /'
    docker exec -i $NAME /bin/bash -c "occ market:install metadata" | sed 's/^/** /'
    docker exec -i $NAME /bin/bash -c "occ app:enable files_pdfviewer" | sed 's/^/** /'
    docker exec -i $NAME /bin/bash -c "occ app:enable files_texteditor" | sed 's/^/** /'
    docker exec -i $NAME /bin/bash -c "occ app:enable onlyoffice" | sed 's/^/** /'
    docker exec -i $NAME /bin/bash -c "occ app:enable files_external" | sed 's/^/** /'
    docker exec -i $NAME /bin/bash -c "occ app:enable user_external" | sed 's/^/** /'
    
    echo "* "
    echo "* Please connect on https://$DOMAIN/owncloud/settings/admin?sectionid=storage"
    echo "** Tick \"Enable external storage\""
    echo "** Tick \"Allow users to mount external storage\""
    echo "* "
    echo "* Please connect on https://$DOMAIN/owncloud/settings/admin?sectionid=sharing"
    echo "** Tick \"Set default expiration date\""
    echo "* "
    echo "* Please connect on https://$DOMAIN/owncloud/settings/admin?sectionid=additional"
    echo "** Set \"Document Editing Service address\": https://$DOMAIN:8095"
    echo "** Click on Save"
    echo "** Tick on \"default application\": csv, doc, xls, ppt, rtf"
    echo "** UnTick all on \"Open the file for editing\""
    echo "** Click on Save"
    echo "* "
    echo -n "** Press <enter to continue>..."
    read answer

    echo "* "
    echo "* [owncloud] Create users and shares"
    echo "* "
    docker exec -i $NAME /bin/bash -c "occ group:add users" | sed 's/^/** /'
    for L in $(cat $FILE_NAME.env | grep "^USER"); do
      # Get the value after =
      V=${L#*=}
      # Evaluate variable inside the line
      V=$(eval echo $V)
      # Remove " from string
      #V=${V//\"}

      U_NAME=$(echo $V | cut -d'|' -f1)   # User login
      U_PWD=$(echo $V | cut -d'|' -f2)    # Password
      U_DESC="$(echo $V | cut -d'|' -f3)" # Description
      U_MAIL=$(echo $V | cut -d'|' -f4)   # Email

      # User login to lowercase
      U_NAME_LC=$(echo $U_NAME | awk '{print tolower($0)}')

      echo "** Add user $U_NAME"
      if [ -n "$(docker exec -i $NAME /bin/bash -c "occ user:list" | grep $U_NAME)" ]; then
        docker exec -i $NAME /bin/bash -c "occ user:delete --force $U_NAME" > /dev/null 2>&1
      fi
      (
      echo $U_PWD # New password
      echo $U_PWD # Retype new password
      ) | docker exec -i $NAME /bin/bash -c "occ user:add --display-name=\"$U_DESC\" --group=users --email=$U_MAIL $U_NAME" > /dev/null 2>&1
      
      echo "** Add share [$U_NAME] -> \\\\$HOST_NAME.$HOST_DOMAIN\\$U_NAME$"
      #docker exec -i $NAME /bin/bash -c "occ files_external:create -c host=$HOST_NAME.$HOST_DOMAIN -c share=$U_NAME$ -c domain="" $U_NAME smb password::sessioncredentials" > /dev/null 2>&1
      cat << EOF > $NAME_APP/out.json
[
    {
        "mount_point": "\/$U_NAME",
        "storage": "\\\\OCA\\\\Files_External\\\\Lib\\\\Storage\\\\SMB",
        "authentication_type": "password::password",
        "configuration": {
            "host": "$HOST_NAME.$HOST_DOMAIN",
            "share": "$U_NAME$",
            "root": "",
            "domain": "",
            "user": "$U_NAME",
            "password": "$U_PWD"
        },
        "options": "previews: true, enable_sharing: true",
        "applicable_users": [
            "$U_NAME"
        ],
        "applicable_groups": []
    }
]
EOF
      docker exec -i $NAME /bin/bash -c "occ files_external:import /mnt/data/out.json"
      rm -f $NAME_APP/out.json
    done
    
    for L in $(cat $FILE_NAME.env | grep "^OC_SHARE"); do
      # Get the value after =
      V=${L#*=}
      # Evaluate variable inside the line
      V=$(eval echo $V)
      # Remove " from string
      #V=${V//\"}

      OC_NAME=$(echo $V | cut -d'|' -f1)    # mount_point
      OC_SHARE=$(echo $V | cut -d'|' -f2)   # share_name
      OC_ROOT=""                            # root_name
      if [ -z "$(echo $OC_SHARE | grep /)" ]; then
        # Split share and root
        # OC_SHARE="Public/Users/Jeremie"
        OC_ROOT=${OC_SHARE:$(expr index "$OC_SHARE" /):$(expr length "$OC_SHARE")}
        # OC_ROOT="Users/Jeremie"
        OC_SHARE=${OC_SHARE:0:$(expr $(expr index "$OC_SHARE" /) - 1)}
        # OC_SHARE="Public"
      fi
      OC_USERS=$(echo $V | cut -d'|' -f3)   # applicable_users (comma separator)
      OC_GROUPS=$(echo $V | cut -d'|' -f4)  # applicable_groups (comma separator)

      echo "** Add global share [Users:$OC_USERS ; Groups:$OC_GROUPS] -> \\\\$HOST_NAME.$HOST_DOMAIN\\$OC_SHARE\$OC_ROOT"
      cat << EOF > $NAME_APP/out.json
[
    {
        "mount_point": "\/$OC_NAME",
        "storage": "\\\\OCA\\\\Files_External\\\\Lib\\\\Storage\\\\SMB",
        "authentication_type": "password::password",
        "configuration": {
            "host": "$HOST_NAME.$HOST_DOMAIN",
            "share": "$OC_SHARE",
            "root": "$OC_ROOT",
            "domain": "",
            "user": "www-data",
            "password": "www-data"
        },
        "options": "previews: true, enable_sharing: true",
        "applicable_users": [
EOF
      if [ -n "$OC_USERS" ]; then
        cat << EOF >> $NAME_APP/out.json
            "$OC_USERS"
EOF
      fi
      cat << EOF >> $NAME_APP/out.json
        ],
        "applicable_groups": [
EOF
      if [ -n "$OC_GROUPS" ]; then
        cat << EOF >> $NAME_APP/out.json
            "$OC_GROUPS"
EOF
      fi
      cat << EOF >> $NAME_APP/out.json
        ]
    }
]
EOF
      docker exec -i $NAME /bin/bash -c "occ files_external:import /mnt/data/out.json"
      rm -f $NAME_APP/out.json
    done

    # Restore Internal Field Separator
    IFS=$SAVEIFS
    
    shift;;




  "upgrade")
    VER_OLD=$NAME_VER
    VER_NEW=$(git ls-remote --tags --refs https://github.com/owncloud/core.git | cut -d'v' -f2 | grep -v -E "alpha|beta|RC" | sort -nr 2> /dev/null | head -n1)

    echo "* [docker] $NAME Checking for updates, please wait..." | tee -a $FILE_LOG $FILE_LOG_ERRORS

    UPDATE=""
    if [ "$VER_OLD" == "$VER_NEW" ] || [ $(fDockerImageTagExists owncloud/server $VER_NEW) -eq 0 ]; then
      UPDATE="NO"
      VER_NEW=$VER_OLD
      echogreen "* [docker] $NAME $VER_OLD is up to date."
      echo "* [docker] $NAME $VER_OLD is up to date." | tee -a $FILE_LOG $FILE_LOG_ERRORS > /dev/null
    else

      echoblue "* [docker] $NAME Current version $VER_OLD"
      echo "* [docker] $NAME Current version $VER_OLD" | tee -a $FILE_LOG $FILE_LOG_ERRORS > /dev/null
      echo "* [git] $NAME Last found version:" | tee -a $FILE_LOG $FILE_LOG_ERRORS
      git ls-remote --tags --refs https://github.com/owncloud/core.git | cut -d'v' -f2 | grep -v -E "alpha|beta|RC" | sort -nr 2> /dev/null | head -n5 | tee -a $FILE_LOG $FILE_LOG_ERRORS
      if [ $QUIET -eq 1 ]; then
        #echo "* Enter $NAME version? <$VER_NEW> "
        answer=
      else
        echo -n "* Enter $NAME version? <$VER_NEW> "
        read answer
      fi
      if [ -z "$answer" ]; then
        UPDATE="OK"
      elif [ "$VER_OLD" == "$answer" ]; then
        UPDATE="NO"
        echogreen "* [docker] $NAME is still on $VER_OLD."
        echo "* [docker] $NAME is still on $VER_OLD." | tee -a $FILE_LOG $FILE_LOG_ERRORS > /dev/null
        VER_NEW=$VER_OLD
      elif [ $(git ls-remote --tags --refs https://github.com/owncloud/core.git | cut -d'v' -f2 | grep -v -E "alpha|beta|RC" | grep "^$answer") ] && [ $(fDockerImageTagExists owncloud/server $answer) -eq 1 ]; then
        UPDATE="OK"
        VER_NEW=$answer
      else
        UPDATE="NO"
        echored "* [docker] $NAME is not updated to $VER_NEW!"
        echo "* [docker] $NAME is not updated to $VER_NEW!" | tee -a $FILE_LOG $FILE_LOG_ERRORS
        VER_NEW=$VER_OLD
      fi
    fi


    if [ "$UPDATE" == "OK" ]; then
      fDockerBackup $NAME $NAME_APP $NAME_VER
      
      echo "* [docker] $NAME Upgrading from $VER_OLD to $VER_NEW" | tee -a $FILE_LOG $FILE_LOG_ERRORS
      # docker pull owncloud/server:$VER_NEW
      sed -i "s/^OWNCLOUD_VERSION=.*/OWNCLOUD_VERSION=$VER_NEW/g" $DOCK_ENV
      cd $DOCK_PATH
      docker-compose up -d --no-deps --force-recreate $NAME 2>&1 | tee -a $FILE_LOG_ERRORS
      cd ~

      echo "* [docker] $NAME Restart the container" | tee -a $FILE_LOG $FILE_LOG_ERRORS
      docker restart $NAME 2>&1 | tee -a $FILE_LOG_ERRORS
      sleep 30

      echo "* [docker] $NAME Install p7zip package" | tee -a $FILE_LOG $FILE_LOG_ERRORS
      docker exec -i $NAME /bin/bash -c "apt update && apt -y install p7zip-full" 2>&1 | tee -a $FILE_LOG_ERRORS
      
      echo "* [docker] $NAME Disable maintenance mode" | tee -a $FILE_LOG $FILE_LOG_ERRORS
      docker exec -i $NAME /bin/bash -c "occ maintenance:mode --off" 2>&1 | tee -a $FILE_LOG_ERRORS

      echoblue "* [docker] $NAME $VER_NEW upgrade is completed."
      echo "* [docker] $NAME $VER_NEW upgrade is completed." | tee -a $FILE_LOG $FILE_LOG_ERRORS > /dev/null
    fi

    echo "* [healthcheck] Waiting for $NAME docker to be up and running, please wait..."
    URL_TO_CHECK="http://$HOST_NAME.$HOST_DOMAIN/$NAME"
    URL_PASSED=0
    COUNT=0
    while [ $URL_PASSED -eq 0 ] && [ $COUNT -lt 3 ]; do
      for URL in $(echo $URL_TO_CHECK | tr "|" "\n"); do
        URL_MSG=$(curl -sSf --insecure $URL 2>&1)
        if [ $? -eq 0 ]; then
          URL_PASSED=1
          echo "* [healthcheck] Website $URL is up and running!"
        else
          URL_PASSED=0
          echo "* [healthcheck] Website is down $URL ..."
          # echo "* [healthcheck] Error: $URL_MSG"
          [ $COUNT -eq 0 ] && echo "* [docker] $NAME Restart the container" && docker restart $NAME > /dev/null
          sleep 30
        fi
      done
      COUNT=$(($COUNT + 1))
    done

    if [ $URL_PASSED -eq 0 ]; then
      sed -i "s/^OWNCLOUD_VERSION=.*/OWNCLOUD_VERSION=$VER_OLD/g" $DOCK_ENV
      
      echored "* [docker] $NAME Upgrade $VER_NEW failed! Please check the log..."
      echo "* [docker] $NAME Upgrade $VER_NEW failed! Please check the log..." | tee -a $FILE_LOG $FILE_LOG_ERRORS > /dev/null
    else
      echo "* [docker] $NAME Upgrade Third-Party Apps on Market, please wait..." | tee -a $FILE_LOG $FILE_LOG_ERRORS
      OCC_APPS_LOG="/var/log/owncloud-upgrade-apps.log"
      rm -f $OCC_APPS_LOG

      # Upgrade app based on default setup
      docker exec -i $NAME /bin/bash -c "occ market:upgrade files_texteditor --major" 2>&1 | tee -a $FILE_LOG_ERRORS $OCC_APPS_LOG
      docker exec -i $NAME /bin/bash -c "occ market:upgrade files_mediaviewer --major" 2>&1 | tee -a $FILE_LOG_ERRORS $OCC_APPS_LOG
      # Upgrade app addedd
      for app in $(ls $NAME_APP/apps); do
        docker exec -i $NAME /bin/bash -c "occ market:upgrade $app --major" 2>&1 | tee -a $FILE_LOG_ERRORS $OCC_APPS_LOG
      done
      if [ -f $OCC_APPS_LOG ] && [ $(cat $OCC_APPS_LOG | grep "App updated." | wc -l) -gt 0 ]; then
        cat $OCC_APPS_LOG | grep "App updated." | sed 's/^/  /' | tee -a $FILE_LOG $FILE_LOG_ERRORS
        echoblue "* [docker] $NAME $VER_NEW Third-Party Apps upgrade are completed."
        echo "* [docker] $NAME $VER_NEW Third-Party Apps upgrade are completed." | tee -a $FILE_LOG $FILE_LOG_ERRORS > /dev/null
      else
        echogreen "* [docker] $NAME $VER_NEW Third-Party Apps are up to date."
        echo "* [docker] $NAME $VER_NEW Third-Party Apps are up to date." | tee -a $FILE_LOG $FILE_LOG_ERRORS > /dev/null
      fi
    fi
    shift;;




  "backup")
    fDockerBackup $NAME $NAME_APP $NAME_VER
    shift;;




  "rollback")
    echo "* [docker] $NAME Current version $NAME_VER" | tee -a $FILE_LOG $FILE_LOG_ERRORS

    # docker-owncloud-10.4.0_20200313-171641.tar.gz
    VER_NEW=$(ls $NAME_APP-bkp | cut -d'_' -f1 | cut -d'-' -f3 | sort -nur 2> /dev/null | head -n1)
    ls $NAME_APP-bkp | cut -d'_' -f1 | cut -d'-' -f3 | sort -nur 2> /dev/null | head -n5 | tee -a $FILE_LOG $FILE_LOG_ERRORS
    echo -n "* Please enter $NAME rollback version? <$VER_NEW> " | tee -a $FILE_LOG $FILE_LOG_ERRORS
    read answer
    [ -n "$answer" ] && VER_NEW=$answer
    FILE_BKP=$(ls $NAME_APP-bkp/*$VER_NEW* | sort -nur 2> /dev/null | head -n1)
    echo "* [tar] Extracting archive $FILE_BKP" | tee -a $FILE_LOG $FILE_LOG_ERRORS
    rm -Rf $NAME_APP/*
    tar -xzf $FILE_BKP -C / 2>&1 | tee -a $FILE_LOG_ERRORS
    
    echo "* [docker] $NAME Downgrading to $VER_NEW" | tee -a $FILE_LOG $FILE_LOG_ERRORS
    # docker pull owncloud/server:$VER_NEW
    sed -i "s/^OWNCLOUD_VERSION=.*/OWNCLOUD_VERSION=$VER_NEW/g" $DOCK_ENV
    cd $DOCK_PATH
    docker-compose up -d --no-deps --force-recreate $NAME 2>&1 | tee -a $FILE_LOG_ERRORS
    cd ~

    echo "* [docker] $NAME Restart the container" | tee -a $FILE_LOG $FILE_LOG_ERRORS
    docker restart $NAME 2>&1 | tee -a $FILE_LOG_ERRORS
    sleep 30
    
    echo "* [docker] $NAME Install p7zip package" | tee -a $FILE_LOG $FILE_LOG_ERRORS
    docker exec -i $NAME /bin/bash -c "apt update && apt -y install p7zip-full" 2>&1 | tee -a $FILE_LOG_ERRORS
    
    echoblue "* [docker] $NAME Downgrading $VER_NEW is completed."
    echo "* [docker] $NAME Downgrading $VER_NEW is completed." | tee -a $FILE_LOG $FILE_LOG_ERRORS > /dev/null
    shift;;




  "cleanup")
    echo "* [owncloud] Cleanup unused files" | tee -a $FILE_LOG $FILE_LOG_ERRORS
    docker exec -i $NAME /bin/bash -c "occ trashbin:cleanup" | sed 's/^/** /' 2>&1 | tee -a $FILE_LOG_ERRORS
    find $NAME_APP/files/*/files_*/ -delete 2> /dev/null
    find $NAME_APP/files/*/thumbnails/* -delete 2> /dev/null
    find $NAME_APP/files/*/uploads/* -delete 2> /dev/null
    find $NAME_APP/files/*/cache/* -delete 2> /dev/null

    # Overwirte with the latest synchronized file and remove "(conflicted copy" files
    dir=/mnt/data
    pattern=" (conflicted copy"
    echo "* [owncloud] Cleanup synchronized \"$pattern\" files in $dir" | tee -a $FILE_LOG $FILE_LOG_ERRORS
    for f in $(find $dir -type f -name "*$pattern*" -print); do
      dname="$(dirname "$f")"
      filename="$(basename "$f")"
      fname="${filename%.*}"
      fext=""
      [ -n "$(echo $filename | grep '\.')" ] && fext="${filename##*.}"

      # filename = "ANNIV ERIC 60ANS - Raccourci (1) (conflicted copy Sylvie 2019-11-17 191604).lnk"
      bname="$(echo $filename | awk -F'conflicted copy' '{print $1}' | sed 's/ ($//g')"
      # bname = "ANNIV ERIC 60ANS - Raccourci "
      
      # Remove white space from the end of line
      bname="$(echo $bname | sed 's/ *$//')"
      
      # Find duplicate conflicted files and keep the latest file
      if [ $(find $dname -name "$bname*" -print | wc -l) -gt 0 ]; then
        [ -n "$fext" ] && fext=".$fext"
        echo "** mv $(find $dname -name "$bname$pattern*" -print0 | xargs -0 ls -r | head -n1) --> $bname$fext" 2>&1 | tee -a $FILE_LOG_ERRORS
        [ $TEST -eq 0 ] && mv "$(find $dname -name "$bname$pattern*" -print0 | xargs -0 ls -r | head -n1)" "$dname/$bname$fext" 2>&1 | tee -a $FILE_LOG_ERRORS
        [ $TEST -eq 0 ] && find $dname -name "$bname$pattern*" -delete 2>&1 | tee -a $FILE_LOG_ERRORS
      fi
    done
    shift;;
esac

[ $STANDALONE -eq 1 ] && echo "* " | tee -a $FILE_LOG $FILE_LOG_ERRORS
[ $STANDALONE -eq 1 ] && echo "* End time: $(date)" | tee -a $FILE_LOG $FILE_LOG_ERRORS
runend=$(date +%s)
runtime=$((runend-runstart))
[ $STANDALONE -eq 1 ] && echo "* Elapsed time: $(($runtime / 3600))hrs $((($runtime / 60) % 60))min $(($runtime % 60))sec" | tee -a $FILE_LOG $FILE_LOG_ERRORS

exit 0