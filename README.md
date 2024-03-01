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
tape init
```
