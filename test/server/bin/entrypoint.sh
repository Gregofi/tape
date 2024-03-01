#!/bin/sh

set -e

SFTP_HOST=remote
SFTP_USER=root
SFTP_PASS=password

rclone config create remote sftp host $SFTP_HOST user $SFTP_USER pass $SFTP_PASS
rclone ls remote:/var/lib/tape

# install tape
cd /opt/tape && make install && cp test/server/scripts.d/* /etc/tape/scripts.d && cd -
echo "password" > /etc/tape/key

# mock mail command
printf '#!/bin/sh\necho $@\n' > /usr/bin/mail
chmod +x /usr/bin/mail

echo "=== Inits default repository in /var/lib/tape ==="
tape -v init

echo "=== Inits repository in /tmp/tape ==="
tape -v init /tmp/tape

echo "=== Inits repository in remote:/var/lib/tape ==="
tape -v init rclone:remote:/var/lib/tape

echo "=== Backups all ==="
tape -v backup
sleep 5

echo "=== Backups sysconfig only ==="
tape -v backup sysconfig 

echo "=== Report ==="
tape -v report
