default:
	echo "Nothing to done, run make install"

install:
	cp tape /usr/sbin/tape && chmod 750 /usr/sbin/tape
	cp -nr etc/tape /etc
