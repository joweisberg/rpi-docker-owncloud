# ~/.profile: executed by the command interpreter for login shells.
# This file is not read by bash(1), if ~/.bash_profile or ~/.bash_login
# exists.
# see /usr/share/doc/bash/examples/startup-files for examples.
# the files are located in the bash-doc package.

# the default umask is set in /etc/profile; for setting the umask
# for ssh logins, install and configure the libpam-umask package.
#umask 022

# if running bash
if [ -n "$BASH_VERSION" ]; then
    # include .bashrc if it exists
    if [ -f "$HOME/.bashrc" ]; then
	. "$HOME/.bashrc"
    fi
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/bin" ] ; then
    PATH="$HOME/bin:$PATH"
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/.local/bin" ] ; then
    PATH="$HOME/.local/bin:$PATH"
fi

#
# Change welcome message
#

# Check internet status
echo
wget -q --spider http://www.google.com 2> /dev/null
if [ $? -eq 0 ]; then  # if Google website is available we update
  echo "You are connected to the internet."
else
  echo "You are not connected to the internet."
fi

# Show OS informations and status
echo
echo -n "* Show OS informations and status? [Y/n] "
read answer
if [ -n "$(echo $answer | grep -i '^y')" ] || [ -z "$answer" ]; then
  ~/os-info.sh
else
  echo "* You can use 'osinfo' command alias later."
  echo
fi
