#!/bin/sh

set -e

SFTP_HOST=remote
SFTP_USER=root
SFTP_PASS=password

rclone config create remote sftp host $SFTP_HOST user $SFTP_USER pass $SFTP_PASS
rclone ls remote:/var/lib/tape

# Install tape
cd /opt/tape && make install && cp test/server/scripts.d/* /etc/tape/scripts.d && cd -
echo "password" > /etc/tape/key

# Mock mail command
printf '#!/bin/sh\necho $@\n' > /usr/bin/mail
chmod +x /usr/bin/mail

# Tests
echo "=== Test Init default repository in /var/lib/tape ==="
tape -v init

echo "=== Test Init repository in /tmp/tape ==="
tape -v init /tmp/tape

echo "=== Test Inits repository in remote:/var/lib/tape ==="
tape -v init rclone:remote:/var/lib/tape

echo "=== Test Backup all ==="
tape -v backup

echo "=== Test Backup sysconfig only ==="
echo "Hello, World!" >> /etc/motd
tape -v -n backup sysconfig 

echo "=== Report ==="
tape -v report
