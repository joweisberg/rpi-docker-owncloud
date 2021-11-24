#!/bin/bash
#
# Launch command:
# sudo $HOME/os-backup.sh
# sudo $HOME/os-backup.sh --restore
#

# Add /sbin path for linux command
PATH=/usr/bin:/bin:/usr/sbin:/sbin

FILE_PATH=$(readlink -f $(dirname $0))  #/home/media
FILE_NAME=$(basename $0)                #os-backup.sh
FILE_NAME=${FILE_NAME%.*}               #os-backup
FILE_DATE=$(date +'%Y%m%d-%H%M%S')
FILE_LOG="${FILE_LOG:-/var/log/$FILE_NAME.log}"
FILE_LOG_ERRORS="${FILE_LOG_ERRORS:-/var/log/$FILE_NAME.err}"

###############################################################################
### Functions

###############################################################################
### Environment Variables

# Source under this script directory
cd $(readlink -f $(dirname $0))
. .bash_colors
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

# Run script in standalone, without heritage
# Or redirect output file to parent script (variables export)
STANDALONE=1
[ "$FILE_LOG" == "/var/log/$FILE_NAME.log" ] && rm -f $FILE_LOG $FILE_LOG_ERRORS || STANDALONE=0

###############################################################################
### Script

runstart=$(date +%s)
[ $STANDALONE -eq 1 ] && echo "* Command: $0 $@" | tee -a $FILE_LOG $FILE_LOG_ERRORS
[ $STANDALONE -eq 1 ] && echo "* Start time: $(date)" | tee -a $FILE_LOG $FILE_LOG_ERRORS
[ $STANDALONE -eq 1 ] && echo "* " | tee -a $FILE_LOG $FILE_LOG_ERRORS

BKP_PATH=$FILE_PATH/$FILE_NAME
BKP_BASE="backup-$HOSTNAME"
BKP_NAME="backup-$HOSTNAME-$(date +'%Y-%m-%d')"
BKP_FILE="backup-$HOSTNAME-$(date +'%Y-%m-%d').tar.gz"

if [ ! -f $FILE_NAME.conf ]; then
  echored "* File $FILE_NAME.conf is not found!"
  echo "* File $FILE_NAME.conf is not found!" | tee -a $FILE_LOG $FILE_LOG_ERRORS > /dev/null
  exit 1
fi

if [ -n "$(echo $1 | grep '\-r')" ] || [ -n "$(echo $1 | grep '\--restore')" ]; then
  
  BKP_RESTORE=1
  
  if [ $(ls -t $BKP_BASE-*.tar.gz 2> /dev/null | wc -l) -eq 0 ]; then
    echored "* No backup file found!"
    echo "* No backup file found!" | tee -a $FILE_LOG $FILE_LOG_ERRORS > /dev/null
    echo "* Please check in the current directory, if $BKP_BASE-*.tar.gz file exists..." | tee -a $FILE_LOG $FILE_LOG_ERRORS
    echo "* Or run: " | tee -a $FILE_LOG $FILE_LOG_ERRORS
    echoyellow "* sudo $FILE_PATH/$FILE_NAME.sh"
    echo "* sudo $FILE_PATH/$FILE_NAME.sh" | tee -a $FILE_LOG $FILE_LOG_ERRORS > /dev/null
    echo "* " | tee -a $FILE_LOG $FILE_LOG_ERRORS
    echo -n "* Force the default installation? [y/N] " | tee -a $FILE_LOG $FILE_LOG_ERRORS
    read answer
    if [ -n "$(echo $answer | grep -i '^y')" ]; then
      BKP_RESTORE=0
    else
      exit 1
    fi
  fi

  if [ $BKP_RESTORE -eq 1 ]; then
    echo "* [Ubuntu] Restoring backup" | tee -a $FILE_LOG $FILE_LOG_ERRORS
    BKP_FILE=$(ls -t $BKP_BASE-*.tar.gz | head -n1)
    ls -t $BKP_BASE-*.tar.gz | head -n5 | tee -a $FILE_LOG $FILE_LOG_ERRORS
    echo -n "* Enter backup file name to restore? <$BKP_FILE> " | tee -a $FILE_LOG $FILE_LOG_ERRORS
    read answer
    if [ -n "$answer" ]; then
      BKP_FILE=$answer
    fi
    echo "* [gunzip] UnCompressing data from $BKP_FILE" | tee -a $FILE_LOG $FILE_LOG_ERRORS
    gunzip -f $BKP_FILE 2>&1 | tee -a $FILE_LOG_ERRORS
    echo "* [tar] Extracting data from $BKP_NAME.tar" | tee -a $FILE_LOG $FILE_LOG_ERRORS
    tar -xzpf $BKP_NAME.tar -C / 2>&1 | tee -a $FILE_LOG_ERRORS
    
    echoblue "* [Ubuntu] Backup restored."
    echo "* [Ubuntu] Backup restored." | tee -a $FILE_LOG $FILE_LOG_ERRORS > /dev/null
  fi

else

  echo "* [Ubuntu] Backup data from $FILE_NAME.conf" | tee -a $FILE_LOG $FILE_LOG_ERRORS

  mkdir -p $BKP_PATH
  cd $BKP_PATH
  # Keep only the last 3 more recent backup files
  if [ $(ls -tr $BKP_BASE-* 2> /dev/null | wc -l) -gt 3 ]; then
    NB=$(eval echo $(($(ls -tr $BKP_BASE-* | wc -l) -3)))
    echo "* [fs] Keep only 3 last backup, then removing these old files under $BKP_PATH" | tee -a $FILE_LOG $FILE_LOG_ERRORS
    ls -tr $BKP_BASE-* | head -n$NB | sed 's/^/*** /' | tee -a $FILE_LOG $FILE_LOG_ERRORS
    ls -tr $BKP_BASE-* | head -n$NB | xargs rm -f
  fi

  # Remove same existing file
  rm -f $BKP_NAME*

  echo -n "* [tar] Archiving data into $BKP_NAME.tar" | tee -a $FILE_LOG $FILE_LOG_ERRORS
  # Create archive w/ list of files/folders
  #tar -cf $BKP_NAME.tar -T $FILE_PATH/$FILE_NAME.conf > /dev/null 2>&1
  for obj in $(cat $FILE_PATH/$FILE_NAME.conf | grep -v -e "^#" -e "^[[:space:]]*$"); do
    # Skip line starting with # and empty line
    if [ -f "$BKP_NAME.tar" ]; then
      # Add file/folder into existing archive
      tar -uf $BKP_NAME.tar -C / $obj 2>&1 | tee -a $FILE_LOG_ERRORS
    else
      # Create archive w/ new file/folder
      tar -cf $BKP_NAME.tar -C / $obj 2>&1 | tee -a $FILE_LOG_ERRORS
    fi
  done
  echo " [$(ls -hs $BKP_NAME.tar | awk '{print $1}')]" | tee -a $FILE_LOG $FILE_LOG_ERRORS
  
  echo -n "* [gzip] Compressing data into $BKP_FILE" | tee -a $FILE_LOG $FILE_LOG_ERRORS
  gzip -f $BKP_NAME.tar 2>&1 | tee -a $FILE_LOG_ERRORS
  echo " [$(ls -hs $BKP_FILE | awk '{print $1}')]" | tee -a $FILE_LOG $FILE_LOG_ERRORS

  chown -R $USER:users $BKP_PATH

  # Moves to the previous directory
  cd - > /dev/null

  echoblue "* [Ubuntu] Backup data completed."
  echo "* [Ubuntu] Backup data completed." | tee -a $FILE_LOG $FILE_LOG_ERRORS > /dev/null
fi

[ $STANDALONE -eq 1 ] && echo "* " | tee -a $FILE_LOG $FILE_LOG_ERRORS
[ $STANDALONE -eq 1 ] && echo "* End time: $(date)" | tee -a $FILE_LOG $FILE_LOG_ERRORS
runend=$(date +%s)
runtime=$((runend-runstart))
[ $STANDALONE -eq 1 ] && echo "* Elapsed time: $(($runtime / 3600))hrs $((($runtime / 60) % 60))min $(($runtime % 60))sec" | tee -a $FILE_LOG $FILE_LOG_ERRORS

exit 0