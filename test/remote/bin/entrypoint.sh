#!/bin/sh

printf "root:password" | chpasswd
sed -i "s/#PermitRootLogin prohibit-password/PermitRootLogin yes/" /etc/ssh/sshd_config
ssh-keygen -A
mkdir -p /var/lib/tape
/usr/sbin/sshd -D
