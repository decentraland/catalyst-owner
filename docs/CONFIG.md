# Config
## `userdata.sh`

Base file to run in the `user data` section of a cloud-init enabled instance like AWS EC2.

It configures the minimum necessary environment to run the catalyst.

## `bootstrap.sh`

This file is automatically configured by `userdata.sh` to run when the instance starts. It mounts the volumes if necessary (MOUNT_DISK env var) and starts the services.

## `mount.sh`

This file must be executed as root. Its only responsibiliy is to mount the MOUNT_DISK volume to the CONTENT_SERVER_STORAGE folder if necessary.
