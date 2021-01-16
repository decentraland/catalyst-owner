#!/bin/bash

# mounts the volume, run as root

source .env

set -u # break on unbound variables
set -x # verbose

mkdir -p "${CONTENT_SERVER_STORAGE}"

MOUNT_DISK=${MOUNT_DISK:-}

# mount the disk $MOUNT_DISK to $CONTENT_SERVER_STORAGE
if [ "$MOUNT_DISK" -ne "" ]; then
  if ! fsck.ext4 -n "$MOUNT_DISK"; then
    mkfs.ext4 "$MOUNT_DISK"
  else
    resize2fs "$MOUNT_DISK"
  fi

  until mount | grep /opt/ebs; do
    echo "Tryint to mount ${CONTENT_SERVER_STORAGE}.."
    mount "$MOUNT_DISK" "${CONTENT_SERVER_STORAGE}";
    sleep 10
  done

  echo "Setting up automatic mounting of EBS volume..."
  blkid | grep "$MOUNT_DISK" | awk '{print $2}' | sed s/\"//g | awk '{print $1" '$CONTENT_SERVER_STORAGE'  xfs  defaults,nofail  0  2"}' | cat >> /etc/fstab
fi