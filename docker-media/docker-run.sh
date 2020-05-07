#!/bin/bash

FILE_PATH=$(readlink -f $(dirname $0))  #/home/media/docker-media
FILE_NAME=$(basename $0)                #docker-run.sh
FILE_NAME=${FILE_NAME%.*}               #docker-run
FILE_DATE=$(date +'%Y%m%d-%H%M%S')
FILE_LOG="/var/log/$FILE_NAME.log"

HOST=$(hostname -A | awk '{ print $1 }')
HOST_IP=$(hostname -I | awk '{ print $1 }')

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
echo "* DOMAIN = $DOMAIN"

echo "* "
echo "** Build and Start docker services"
docker-compose down
if [ $(docker ps -a -q | wc -l) -ne 0 ]; then
  docker stop $(docker ps -a -q)
  docker rm --volumes --force $(docker ps -a -q)
fi
kill $(fuser 80/tcp) > /dev/null 2>&1
kill $(fuser 443/tcp) > /dev/null 2>&1
docker-compose up -d --remove-orphans
docker system prune --all --volumes --force

cd - > /dev/null
exit 0
