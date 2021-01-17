#!/bin/bash

# mounts the volume, run as root

source .env

set -u # break on unbound variables
set -x # verbose

mkdir -p "${CONTENT_SERVER_STORAGE}"

MOUNT_DISK=${MOUNT_DISK:-}

# mount the disk $MOUNT_DISK to $CONTENT_SERVER_STORAGE
if [ "$MOUNT_DISK" ]; then

  # format if no XFS filesystem
  file -s "$MOUNT_DISK" | grep -o XFS
  if [ $? -ne 0 ]; then
    mkfs.xfs "$MOUNT_DISK"
  else
    resize2fs "$MOUNT_DISK"
  fi

  echo "Tryint to mount $MOUNT_DISK to ${CONTENT_SERVER_STORAGE}.."
  until mount | grep "${CONTENT_SERVER_STORAGE}"; do
    mount "$MOUNT_DISK" "${CONTENT_SERVER_STORAGE}";
    sleep 10
  done

  backupFile="/etc/fstab.$(date +%s)"

  # find the mounted disk in fstab
  presentInFstab=$(cat /etc/fstab | grep -o "$CONTENT_SERVER_STORAGE")

  if [ ! "$presentInFstab" ]; then
    echo "Configuring fstab"

    echo "Backing up to $backupFile"
    cp /etc/fstab $backupFile

    echo "Setting up automatic mounting of EBS volume..."
    blkid \
    | grep "$MOUNT_DISK" \
    | awk '{print $2}' \
    | sed s/\"//g \
    | awk '{print $1" '$CONTENT_SERVER_STORAGE'  xfs  defaults  0  2"}' \
    | cat >> /etc/fstab

    diff $backupFile /etc/fstab

    # unmount
    umount "$MOUNT_DISK"
    mount -a

    # this should work
    mount | grep "${CONTENT_SERVER_STORAGE}"

    if [ $? -ne 0 ]; then
      echo 'ERROR it was not possible to configure automatic mounting of the disk'
    fi
  fi
fi