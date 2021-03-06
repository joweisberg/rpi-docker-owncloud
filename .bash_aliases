alias ll='ls -alFh --color=auto'
alias topfiles='f() { du -hsx $2/* 2> /dev/null | sort -rh | head -n $1; }; f'
alias cpsync-mini='rsync -rpthW --inplace --no-compress --exclude=.bin/ --delete --info=progress2'
alias cpsync-full='rsync -ahW --inplace --no-compress --exclude=.bin/ --delete --info=progress2'
alias osinfo='/home/media/os-info.sh'
alias osbackup='/home/media/os-install.sh --backup 2>&1 | tee /var/log/os-backup.log'
alias osupgrade='/home/media/os-upgrade.sh 2>&1 | tee /var/log/os-upgrade.log'
alias docrec='f() { cd /home/media/docker-media; docker-compose up -d --no-deps --force-recreate $1; cd - > /dev/null; }; f'
alias docps='docker ps --all --format "table {{.Image}}\t{{.RunningFor}}\t{{.Status}}\t{{.Ports}}"'
alias docstats='docker stats --all --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"'
alias doclog='docker logs'
alias docdf='docker system df'
alias docprune='docker system prune --all --volumes --force'
