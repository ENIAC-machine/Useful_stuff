#!/usr/bin/env bash

set -Eeuo pipefail

#source config
source arch_install_cfg.conf
source pwds.conf

log_info() {
	echo -e "\e[0;32m[INFO]\e[0m$*"
}

log_debug() {
	echo -e "\e[0;33m[DEBUG]\e[0m$*"
}

load_packages() {
	local file="$1"
	local packages=($(grep -v '^#' $1))

	mapfile -t packages < <(
		sed 's/\r$//' "$file" | 
		grep -v '^[[:space:]]*#' | 
		grep -v '^[[:space:]]*$'
	)

	#Ok, I know that it is against the arch philosophy to not use the -K flag
	#but I would build LITERALLY THE SAME FILES
	#except for mirrors probably (VERY debatable btw)
	pacstrap -P /mnt "${packages[@]}"
}

log_debug "Config files loaded"

log_info "Starting..."

#check sys
cat /sys/firmware/efi/fw_platform_size

#make it so that the name resolution will be outsourced to systemd-resolve
cat > "/var/lib/iwd/main.conf" << EOF
[General]
EnableNetworkConfiguration=true

[Network]
NameResolvingService=systemd
EOF

if ! [ -n "$NETWORK_DEVICE" ]; then
	NETWORK_DEVICE=$(iwctl device list | awk 'NR==2 {print $2}')
fi

log_debug "Available devices"

iwctl device list

log_debug "Using device: $NETWORK_DEVICE"

log_debug "Scanning..." && iwctl station $NETWORK_DEVICE scan && sleep 5 

if [ -z "$NETWORK_LOGIN" ]; then
	iwctl station $NETWORK_DEVICE connect "$NETWORK_NAME" --passphrase $NETWORK_PWD

else
	#There's no built-in support of these types of networks, so we bootstrap our own
	log_info "Generating WPA2-EAP profile for $NETWORK_NAME..."

	mkdir -p /var/lib/iwd

	cat > "/var/lib/iwd/$NETWORK_NAME.8021x" << EOF
[Security]
EAP-Method=PEAP
EAP-Identity=anonymous
EAP-PEAP-Phase2-Method=MSCHAPV2
EAP-PEAP-Phase2-Identity=$NETWORK_LOGIN
EAP-PEAP-Phase2-Password=$NETWORK_PWD
EOF

	chmod 600 "/var/lib/iwd/$NETWORK_NAME.8021x"

	log_info "Connecting to WPA2-EAP network: $NETWORK_NAME"
	iwctl station "$NETWORK_DEVICE" connect "$NETWORK_NAME"

fi

log_info "Connected to Wi-Fi successfully"

log_info "Partitioning data..."

#get the disk names from lsblk that are NOT read-only and NOT removable (to exculde BIOS and the flash drive)
mapfile -t DISKS < <(lsblk -dl -o NAME,SIZE,RM,RO | awk '$3 == 0 && $4 == 0 {print $1}')

#Wipe all disks
for DISK in "${DISKS[@]}"; do
	wipefs -a "/dev/$DISK"
done

#allocate swap, if no swap is in the config file, then allocate RAM+2 GB of SWAP
if [ -z "$SWAP_SIZE" ]; then
	SWAP_SIZE=$(free --giga | awk 'NR==2 {print $2 + 2 "G"}')
fi

log_info "Partitioning data..."


# Identify the first SSD for EFI, Boot, Swap, and Root
SSD_DISK=""
OTHER_DISKS=()

for DISK in "${DISKS[@]}"; do
	rota=$(cat "/sys/block/$DISK/queue/rotational")
	if [ "$rota" == "0" ] && [ -z "$SSD_DISK" ]; then
	    SSD_DISK="$DISK"
	else
	    OTHER_DISKS+=("$DISK")
	fi

done

# Fallback if no SSD is detected (use the first disk as primary)
if [ -z "$SSD_DISK" ]; then
    SSD_DISK="${DISKS[0]}"
    OTHER_DISKS=("${DISKS[@]:1}")
fi

log_info "Using $SSD_DISK as the primary disk for system partitions."


#Allocate $BOOT_SIZE for EFI partition, $SWAP_SIZE for the SWAP partition and the $SYS_SIZE for BTRFS filesys 
sfdisk "/dev/$SSD_DISK" <<EOF
label: gpt
size=$BOOT_SIZE, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="efi"
size=$SWAP_SIZE,   type=0657FD6D-A4AB-43C4-84E5-0933C84B4F4F, name="swap"
size=$SYS_SIZE, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="btrfs_root"
size=$DATA_SYS_SIZE, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="tmp_data"
EOF

# Partition each HDD as a single ext4 data partition
for DISK in "${OTHER_DISKS[@]}"; do
    sfdisk "/dev/$DISK" <<EOF
label: gpt
type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="data"
EOF
done

#wait for the procedure to finish
sleep 5

if [[ "$SSD_DISK" =~ "nvme" ]]; then
    PART_BOOT="${SSD_DISK}p1"
    PART_SWAP="${SSD_DISK}p2"
    PART_BTRFS="${SSD_DISK}p3"
    PART_DATA_STORAGE="${SSD_DISK}p4"
else
    PART_BOOT="${SSD_DISK}1"
    PART_SWAP="${SSD_DISK}2"
    PART_BTRFS="${SSD_DISK}3"
    PART_DATA_STORAGE="${SSD_DISK}4"
fi


log_info "Formatting data..."

mkfs.vfat -F 32 "/dev/$PART_BOOT"
mkswap "/dev/$PART_SWAP"
mkfs.btrfs -f "/dev/$PART_BTRFS"
mkfs.xfs -f "/dev/$PART_DATA_STORAGE"

# Format all HDD partitions as ext4
DATA_PARTS=()
for DISK in "${OTHER_DISKS[@]}"; do
    if [[ "$DISK" =~ "nvme" ]]; then
        PART_DATA="/dev/${DISK}p1"
    else
        PART_DATA="/dev/${DISK}1"
    fi
    DATA_PARTS+=("$PART_DATA")
    mkfs.xfs -f "$PART_DATA"
done

log_info "Formatting finished, mounting..."

swapon "/dev/$PART_SWAP"
mount "/dev/$PART_BTRFS" /mnt
mount --mkdir "/dev/$PART_BOOT" /mnt/efi


for PART in "${DATA_PARTS[@]}"; do

	PART_NAME=$(basename "$PART")
    
	MOUNT_POINT="/mnt/$PART_NAME"

	log_info "Mounting disk $PART_NAME..."

	#make mount point
	if mount -t ext4 "$PART" --mkdir "$MOUNT_POINT"; then
		log_info "Mounted successfully $PART -> $MOUNT_POINT"
	fi
	
done

log_info "Mounting done, installing all the necessary packages..."

#All the neccesary packages (not accounting for GPU-related stuff)
load_packages packages.txt

shopt -s nocasematch

# Capture PCI info 
gpu_info=$(lspci)

case "$gpu_info" in
	*nvidia*)
		log_info "NVIDIA GPU detected. Installing proprietary drivers..."

		# Choose the right NVIDIA package based on your kernel
		load_packages nvidia_packages.txt
		;;
	*amd*)
		log_info "AMD GPU detected. Installing open‑source drivers..."
		load_packages amd_packages.txt
        	;;

	*intel*)
		log_info "Intel GPU detected. Installing open‑source drivers..."
		load_packages intel_packages.txt
		;;

	*)
		log_info "Unknown GPU vendor or no GPU detected"
		;;
esac

shopt -u nocasematch

#generate file sys table to remember how all the disks are partitioned
genfstab -U /mnt >> /mnt/etc/fstab

#Move the chroot script and cfg files to the appropriate dir and make it executable
mkdir -p /mnt/root

sed 's/\r$//' "$CHROOT_SCRIPT" > /mnt/root/"$CHROOT_SCRIPT"
chmod 755 /mnt/root/"$CHROOT_SCRIPT"

cp ./arch_install_cfg.conf /mnt/root/arch_install_cfg.conf
cp ./users.csv /mnt/root/users.csv

log_info "Running chroot configuration..."

arch-chroot /mnt /root/"$CHROOT_SCRIPT"

log_info "Setting root password..."

printf 'root:%s\n' "$ROOT_PWD" | arch-chroot /mnt chpasswd

log_info "Cleaning up..."

rm -f /mnt/root/arch_chroot_script.sh
rm -f /mnt/root/arch_install_cfg.sh
rm -f /mnt/root/users.csv

sync

sleep 3

log_info "Installation finished."

umount -R /mnt

reboot
