# tape
Simple backup automation tool for your Linux services.

> **Note:** This tool is still in development, use at your own risk!

## Installation
Install the required dependencies:
- restic
- rclone

Then, clone the repository and run the following command to install the tool:
```
# make install
```

You can configure the backup location and the services to backup in the `tape.conf` file.

Next configure the rclone remote to use for the backup.

## Usage
Before running, you need to create a key for enryption at `/etc/tape/key` or in the location specified in the `tape.conf` file.

Then you can run the following command to backup your services.
```shell
# Create default backup repository, 
# as specified in tape.conf
tape init

# Create backup repository at the specified location.
tape init /path/to/backup/repository

# Create remote backup repository using rclone.
tape init rclone:remote:path
```

Write backup script for your services and run the following command to backup your services.
```shell
#!/bin/sh

files="/etc/ /var/www/ /var/lib/mysql/"

# When not specified, the backup repository is the default one. 
# repository="rclone:remote:path"

before() {
    service my-service stop
}

after() {
    service my-service start
}
```
