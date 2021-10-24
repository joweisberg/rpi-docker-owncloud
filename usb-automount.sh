#!/bin/bash
#
# Mount attached USB devices to /media/usb{1..9}
# Mount attached cdrom devices to /media/cdrom and then /media/cdrom{1..9}
# Unmout attached devices automatically
# Detect changes every 3s
#

USER_UID=$(id -u)
ROOT_UID=0
# Check if run as root
if [ $USER_UID -ne $ROOT_UID ] ; then
  echo "* "
  echo "* You must be root to do that!"
  echo "* "
  exit 1
fi

while true; do
  sleep 3

  # Detect umounted disk partitions
  # Loop on each mounted devices
  for i in {1..9}; do
    # Present on mounted partitions and not in connected partitions
    if [ -d /media/usb$i ] && [ -n "$(mount | grep "/media/usb$i")" ] && [ -z "$(lsblk | grep "/media/usb$i")" ]; then
      dev_part="$(mount | grep "/media/usb$i" | awk '{print $1}')"
      umount /media/usb$i
      [ $? -eq 0 ] && echo "* Partition $dev_part unmounted from /media/usb$i"
    fi
    # Cleaning unused mounted folders
    if [ -d /media/usb$i ] && [ -z "$(mount | grep "/media/usb$i")" ] && [ -z "$(lsblk | grep "/media/usb$i")" ]; then
      [ $(find /media/usb$i -maxdepth 5 -type f -print | wc -l) -eq 0 ] && rm -Rf /media/usb$i
    fi
  done

  # Detect umounted cdrom partitions
  # Not present on mounted partitions and not in connected partitions
  if [ -d /media/cdrom ] && [ -z "$(mount | grep "/media/cdrom")" ] && [ -z "$(lsblk | grep "/media/cdrom")" ]; then
    dev_part="$(mount | grep "/media/cdrom" | awk '{print $1}')"
    umount /media/cdrom > /dev/null 2>&1
    [ $? -eq 0 ] && echo "* Device $dev_part unmounted from /media/cdrom"
    [ $(find /media/cdrom -maxdepth 5 -type f -print | wc -l) -eq 0 ] && rm -Rf /media/cdrom
  fi
  # Loop on each mounted devices
  for i in {1..9}; do
    # Not present on mounted partitions and not in connected partitions
    if [ -d /media/cdrom$i ] && [ -z "$(mount | grep "/media/cdrom$i")" ] && [ -z "$(lsblk | grep "/media/cdrom$i")" ]; then
      dev_part="$(mount | grep "/media/cdrom$i" | awk '{print $1}')"
      umount /media/cdrom$i > /dev/null 2>&1
      [ $? -eq 0 ] && echo "* Device $dev_part unmounted from /media/cdrom$i"
      [ $(find /media/cdrom$i -maxdepth 5 -type f -print | wc -l) -eq 0 ] && rm -Rf /media/cdrom$i
    fi
  done
  
  
  
  
  # Loop on each connected disk devices
  for disk_name in $(lsblk | grep 'disk' | awk '/^sd[a-z] /{print $1}'); do
    #disk=$(lsblk -f | awk '/^sd[a-z] /{print $1}')
    #part=$(lsblk -f | grep '^[└├]─sd[a-z][1-9] ')
    
    # Loop on each device partitions
    for part in $(lsblk | grep 'part' | grep "$disk_name[1-9] " | sed -r 's/^.{2}//' | awk '{print $1"|"$7}'); do
      part_name=$(echo $part | awk -F'|' '{print $1}')
      fstype=$(lsblk -o NAME,FSTYPE | grep "$part_name " | sed -r 's/^.{2}//' | awk '{print $2}')
      label=$(lsblk -o NAME,LABEL | grep "$part_name " | sed -r 's/^.{2}//' | awk '{print $2}')
      mountpoint="$(echo $part | awk -F'|' '{print $2}')"
      
      # No mount point detected
      if [ -z "$mountpoint" ]; then
        # Mount on /media/usb1 or next available number
        for i in {1..9}; do
          if [ ! -d /media/usb$i ]; then
            mkdir -p /media/usb$i
            # Try to mount for fat, exFat or ntfs fs type
            uid=1000
            mount -t $fstype -o nosuid,noexec,nodev,noatime,umask=0077,uid=$uid,gid=$(id -g $uid),iocharset=utf8 /dev/$part_name /media/usb$i > /dev/null 2>&1
            if [ $? -eq 0 ]; then
              echo "* Partition /dev/$part_name mounted on /media/usb$i"
            else
              # Try to mount without options for others fs types, like ext2 or ext4
              mount -t $fstype -o noatime /dev/$part_name /media/usb$i > /dev/null
              if [ $? -eq 0 ]; then
                echo "* Partition /dev/$part_name mounted on /media/usb$i"
              else
                echo "* Error: mount -t $fstype /dev/$part_name /media/usb$i"
                #exit 1
              fi
            fi
            break
          fi
        done
      fi
    done
  done
  
  # Loop on each connected cdrom devices
  for disk_name in $(lsblk | grep 'rom' | awk '/^sr[0-9] /{print $1"|"$7}'); do
    name="$(echo $disk_name | awk -F'|' '{print $1}')"
    fstype="iso9660"
    mountpoint="$(echo $disk_name | awk -F'|' '{print $2}')"

    # No mount point detected
    if [ -z "$mountpoint" ]; then
      # Mount on /media/cdrom
      if [ ! -d /media/cdrom ]; then
        mkdir -p /media/cdrom
        res=$(mount -t $fstype -o ro /dev/$name /media/cdrom 2>&1)
        ret=$?
        # Remove unnecessary output
        res=$(echo $res | sed '/mounted on/d')
        res=$(echo $res | sed '/no medium found/d')
        if [ $ret -eq 0 ]; then
          echo "* Device /dev/$name mounted on /media/cdrom"
        elif [ -n "$res" ]; then
          echo "* Error: mount -t $fstype /dev/$name /media/cdrom => $res"
          #exit 1
        fi
        break
      fi
      # Mount on /media/cdrom1 or next available number
      for i in {1..9}; do
        if [ ! -d /media/cdrom$i ]; then
          mkdir -p /media/cdrom$i
          res=$(mount -t $fstype -o ro /dev/$name /media/cdrom$i 2>&1)
          ret=$?
          # Remove unnecessary output
          res=$(echo $res | sed '/mounted on/d')
          res=$(echo $res | sed '/no medium found/d')
          if [ $ret -eq 0 ]; then
            echo "* Device /dev/$name mounted on /media/cdrom$i"
          elif [ -n "$res" ]; then
            echo "* Error: mount -t $fstype /dev/$name /media/cdrom => $res"
            #exit 1
          fi
          break
        fi
      done
    fi
  done

done

exit 0