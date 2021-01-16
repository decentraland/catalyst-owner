#!/bin/bash

# mounts the volume, run as root

source .env

set -u # break on unbound variables
set -x # verbose

mkdir -p "${CONTENT_SERVER_STORAGE}"

if ! fsck.ext4 -n /dev/xvdf; then
  mkfs.ext4 /dev/xvdf
else
  resize2fs /dev/xvdf
fi

until mount /dev/xvdf "${CONTENT_SERVER_STORAGE}"; do
  echo "Failed mounting volume; retrying in 10 seconds..."
  sleep 10
done

echo "Setting up automatic mounting of EBS volume..."
blkid | grep xvdf | awk '{print $2}' | sed s/\"//g | awk '{print $1" "'$CONTENT_SERVER_STORAGE'"  xfs  defaults,nofail  0  2"}' | cat >> /etc/fstab
