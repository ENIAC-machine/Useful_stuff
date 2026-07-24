#!/bin/bash

set -e 

#source config
source arch_install_cfg.conf
source pwds.conf

log_info() {
	echo "[INFO] $*"
}

log_debug() {
	echo "[DEBUG] $*"
}


load_packages() {
	local packages=($(grep -v '^#' $1))
	pacstrap -K /mnt "${packages[@]}"
}

#creates users from a .csv file with columns [user] [group] [pwd]
create_users() {
	local file="$1"
	local -a headers
	local -A row

	# Read header
	IFS=',' read -ra headers < <(head -n1 "$file")

	log_info "Creating users..."

	# Read the rest
	tail -n +2 "$file" | while IFS=',' read -ra values; do
		getent group ${values[1]} || groupadd ${values[1]} 
		useradd -m -g ${values[1]} -s /bin/bash ${values[0]}
		echo "${values[0]}:${values[2]}" | chpasswd
	done
}

log_debug "Config files loaded"

log_info "Starting..."

#check sys
cat /sys/firmware/efi/fw_platform_size

if ! [ -n "$DEVICE" ]; then
	DEVICE=$(iwctl device list | awk "NR==2 {print $2}")
fi

log_debug "Available devices"

iwctl device list

log_debug "Using device: $DEVICE"

log_debug "Scanning..." && iwctl station $DEVICE scan && sleep 5 

iwctl << EOF
station $DEVICE get-networks
station $DEVICE show
station $DEVICE connect "$NETWORK" --passphrase=$WIFI_PWD
EOF

log_info "Connected to Wi-Fi successfully"

#Wipe all disks
for DISK in "${DISKS[@]}"; do
	wipefs -a "$DISK"
done

if [ -z "$SWAP_SIZE" ]; then
	SWAP_SIZE=$(free --giga | awk 'NR==2 {print $2 + 2 "G"}')
fi

log_info "Partitioning data..."


# Identify the first SSD for EFI, Boot, Swap, and Root
SSD_DISK=""
OTHER_DISKS=()

for disk in "${DISKS[@]}"; do
    current_disk=$(basename "$disk")
    if [ -f "/sys/block/$current_disk/queue/rotational" ]; then
        rota=$(cat "/sys/block/$current_disk/queue/rotational")
        if [ "$rota" == "0" ] && [ -z "$SSD_DISK" ]; then
            SSD_DISK="$disk"
        else
            OTHER_DISKS+=("$disk")
        fi
    else
        OTHER_DISKS+=("$disk")
    fi
done

# Fallback if no SSD is detected (use the first disk as primary)
if [ -z "$SSD_DISK" ]; then
    SSD_DISK="${DISKS[0]}"
    OTHER_DISKS=("${DISKS[@]:1}")
fi

log_info "Using $SSD_DISK as the primary disk for system partitions."


#Allocate $BOOT_SIZE for EFI partition, $SWAP_SIZE for the SWAP partition and the rest for ext4
sfdisk "$SSD_DISK" <<EOF
label: gpt
size=$BOOT_SIZE, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="efi"
size=$SWAP_SIZE,   type=0657FD6D-A4AB-43C4-84E5-0933C84B4F4F, name="swap"
type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="main"
EOF

#wait for the procedure to finish
sleep 5

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

mkfs.vfat -F 32 $PART_BOOT
mkswap $PART_SWAP

for PART in $EXT4_PARTITIONS; do
	mkfs.ext4 $PART
done

log_info "Formatting finished, mounting..."

mount --mkdir $PART_BOOT /mnt/efi
swapon $PART_SWAP

for PART in $EXT4_PARTITIONS; do

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

arch-chroot /mnt << EOF

echo "Syncing the clock..."
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

echo "Filling root details..."
echo "$HOSTNAME" > /etc/hostname
echo "root:$ROOT_PWD" | chpasswd

echo "Installing grub files..."
mkinitcpio -P
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "Installation finished. Rebooting..."
reboot now
EOF
