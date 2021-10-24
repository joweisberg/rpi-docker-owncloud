#!/bin/bash

FILE_PATH=$(readlink -f $(dirname $0))  #/home/media/docker-media
FILE_NAME=$(basename $0)                #docker-build.sh
FILE_NAME=${FILE_NAME%.*}               #docker-build
FILE_DATE=$(date +'%Y%m%d-%H%M%S')
FILE_LOG="/var/log/$FILE_NAME.log"

HOST=$(hostname -A | awk '{ print $1 }')
HOST_IP=$(hostname -I | awk '{ print $1 }')

# Force sudo prompt at the begining
sudo echo > /dev/null

#if [ $(docker images local/certs-extraction | wc -l) -ne 2 ]; then
#  echo "** Build image: local/certs-extraction"
#  cd ~/docker-certs-extraction/
#  docker build -t local/certs-extraction .
#fi
#if [ $(docker images local/glances | wc -l) -ne 2 ]; then
#  echo "** Build image: local/glances"
#  cd ~/docker-glances/
#  docker build -t local/glances .
#fi

# Overwrite host, ip and domain name on environment file
cd $FILE_PATH
sed -i "s/^HOST=.*/HOST=$HOST/" .env
sed -i "s/^HOST_IP=.*/HOST_IP=$HOST_IP/" .env
. .env > /dev/null 2>&1
sed -i "s/^OWNCLOUD_DOMAIN=.*/OWNCLOUD_DOMAIN=$DOMAIN/" .env
# Source .env file
. .env > /dev/null 2>&1

echo "* "
echo "* "
echo "* "
echo "* Environment Variables:"
echo "* HOST_IP = $HOST_IP"
echo "* HOST    = $HOST"
echo "* DOMAIN  = $DOMAIN"

echo "* "
echo "** Stop docker services"
echo "* "
docker-compose down
if [ $(docker ps -a -q | wc -l) -ne 0 ]; then
  echo "* "
  echo "* Force to stop docker services"
  docker stop $(docker ps -a -q)
  echo "* "
  echo "* Force to remove docker volumes"
  docker rm --volumes --force $(docker ps -a -q)
fi
sudo fuser --kill 80/tcp > /dev/null 2>&1
sudo fuser --kill 443/tcp > /dev/null 2>&1

echo "* "
echo "** Build and Start docker services"
echo "* "
docker-compose up -d --remove-orphans

echo "* "
echo -n "* Remove unused volumes and images? [Y/n] "
read answer
if [ -n "$(echo $answer | grep -i '^y')" ] || [ -z "$answer" ]; then
  echo "* "
  docker system prune --all --volumes --force
fi

cd - > /dev/null
exit 0