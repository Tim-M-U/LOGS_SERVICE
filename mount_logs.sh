#!/usr/bin/env bash
set -u
IMAGE="/var/lib/logs_disk.img"
SIZE="100M"
MOUNT_POINT="/LOGS"

if (( EUID != 0 )); then
	echo "Need admin rights, run: sudo bash $0"
	exit 1
fi

if mountpoint -q "$MOUNT_POINT"; then
	echo "$MOUNT_POINT is already mounted"
	exit 0
fi

if ! [[ -f "$IMAGE" ]]; then
	echo "$IMAGE not found, creating new image with size $SIZE"
	fallocate -l "$SIZE" "$IMAGE" || exit 1
	mkfs.ext4 -q -F -m 0 -L LOGS "$IMAGE" || exit 1
fi

mkdir -p "$MOUNT_POINT"
mount -o loop "$IMAGE" "$MOUNT_POINT" || exit 1

mkdir -p "$MOUNT_POINT"/{auth_service,data_process_service,system_event_handler_service}

echo "Done, partition mounted:"
df -h "$MOUNT_POINT"
