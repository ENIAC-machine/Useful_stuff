#!/bin/bash

#source config
source arch_install_cfg.conf

log_info() {
	echo "[INFO] $*"
}

log_debug() {
	echo "[DEBUG] $*"
}


log_debug "Config file read, starting..."

#check sys
cat /sys/firmware/efi/fw_platform_size

if ! [ -n "$DEVICE" ]; then
	DEVICE=$(iwctl device list | awk "NR==2 {print $2}")
fi

log_info "Available devices"

iwctl device list

log_debug "Using device: $DEVICE"

log_info "Scanning..." && iwctl station $DEVICE scan && sleep 5 

iwctl << EOF
station $DEVICE get-networks
station $DEVICE show
station $DEVICE connect $NETWORK 
EOF

log_info "Connected to Wi-Fi successfully"

#In case of several disks
for DISK in "${DISKS[@]}"; do
	wipesf -a "$DISK"
done

if [ -n "$SWAP_SIZE" ]; then
	SWAP_SIZE=$(free --giga | awk 'NR==2 {print $2 * 2 "G"}')
fi

log_info "Partitioning data..."

#Allocate $BOOT_SIZE for EFI partition, $SWAP_SIZE for the SWAP partition and the rest for ext4
sfdisk "$DISK" <<EOF
label: gpt
size=$BOOT_SIZE, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="efi"
size=$SWAP_SIZE,   type=0657FD6D-A4AB-43C4-84E5-0933C84B4F4F, name="swap"
type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="main"
EOF

#wait for the procedure to finish
sleep 2

for DISK in "${DISKS[@]}"; do

	if [[ "$DISK" =~ "nvme" ]]; then
	    PART_BOOT="${DISK}p1"
	    PART_SWAP="${DISK}p2"
	else
	    PART_BOOT="${DISK}1"
	    PART_SWAP="${DISK}2"
	fi

	#boot and swap partitions are only on SSD, which is expected to be the first one
	break

EXT4_PARTITIONS=$(blkid -t TYPE=ext4 -o device)

log_info "Formatting data..."

mkfs.vfat -F 32 PART_BOOT
mkswap PART_SWAP

for PART in $EXT4_PARTITIONS; do
	mkfs.ext4 PART
done

log_info "Formatting finished, mounting..."

mount --mkdir $PART_BOOT /efi
swapon $PART_SWAP

for PART in $EXT4_PARTITIONS; do

	PART_NAME=$(basename "$PART")
    
	MOUNT_POINT="/mnt/$PART_NAME"

	log_info "Mounting disk $PART_NAME..."

	#make mount point
	mkdir -p "$MOUNT_POINT"
	if mount -t ext4 "$PART" "$MOUNT_POINT"; then
		log_info "Mounted successfully $PART -> $MOUNT_POINT"
	fi
	
done

#generate file sys table to remember how all the disks are partitioned
genfstab -U /mnt >> /mnt/etc/fstab

log_info "Mounting done, installing all the necessary packages..."

#All the neccesary packages
pacstrap -K /mnt $(grep -v '^#' packages.txt)

arch-chroot /mnt << EOF
ln -sf /usr/share/zoneinfo/Region/City /etc/localtime
hwclock --systohc
echo "$HOSTNAME" > etc/hostname
echo "root:$ROOT_PWD" | chpasswd
mkinitcpio -P
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
EOF


