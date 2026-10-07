#!/usr/bin/env bash
set -Eeuo pipefail

source /root/arch_install_cfg.conf

log_info() {
	echo -e "\e[0;32m[INFO]\e[0m$*"
}

log_debug() {
	echo -e "\e[0;33m[DEBUG]\e[0m$*"
}

#creates users from a .csv file with columns [user] [group] [pwd]
create_users() {
	local file="$1"
	local -a headers
	local -A row

	#skip line 1 and read the output as user,group,pwd
	while IFS=',' read -r user group pwd; do

		[[ -z "$user" ]] && {
		    log_debug "Error: username is empty" >&2
		    exit 1
		}

		# Remove possible Windows carriage return
		pwd="${pwd%$'\r'}"

		# Default group if empty
		[[ -z "$group" ]] && group="$DEFAULT_GROUP"

		getent group "$group" >/dev/null || groupadd "$group"
			
		log_info "Creating user $user"

		if ! id -u "$user"; then
			useradd -m -g "$group" -s /bin/bash "$user"
		else
			log_debug "Already have user $user, skipping..."
		fi

		# Make the users of the SUDO group sudo-capable
		if [[ "$group" == "$SUDO_GROUP" ]]; then
			usermod -aG wheel "$user"
		fi

		echo "$user:$pwd" | chpasswd
	done < <(tail -n +2 "$file") 
}

ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

log_info "Setting hostname: $HOSTNAME"

echo "$HOSTNAME" > /etc/hostname

cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain   $HOSTNAME
HOSTS

log_info "Configuring sudo..."

if ! getent group $SUDO_GROUP; then
	groupadd --system $SUDO_GROUP
fi

mkdir -p /etc/sudoers.d

cat > /etc/sudoers.d/$SUDO_GROUP <<SUDOERS
%$SUDO_GROUP ALL=(root) ALL
SUDOERS

chmod 440 /etc/sudoers.d/$SUDO_GROUP

grep -q '^@includedir /etc/sudoers.d' /etc/sudoers || \
    echo '@includedir /etc/sudoers.d' >> /etc/sudoers

log_info "Creating users..."
create_users /root/users.csv

#NVIDIA fix
if pacman -Q nvidia; then
    log_info "NVIDIA driver detected, adding nvidia_drm.modeset=1"

    if ! grep -q 'nvidia_drm.modeset=1' /etc/default/grub; then
        if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub; then
            sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="/&nvidia_drm.modeset=1 /' /etc/default/grub
        else
            echo 'GRUB_CMDLINE_LINUX_DEFAULT="nvidia_drm.modeset=1"' >> /etc/default/grub
        fi
    fi
fi

log_info "Enabling sshd and iwd services..."

if [ -f /usr/lib/systemd/system/sshd.service ]; then
    systemctl enable --now sshd.service
else
    log_debug "sshd.service not found, skipping"
fi

if [ -f /usr/lib/systemd/system/iwd.service ]; then
    systemctl enable --now iwd.service
else
    log_debug "iwd.service not found, skipping"
fi

log_info "Installing grub files..."

mkinitcpio -P
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

log_info "Chroot configuration finished successfully. Continuing with the main script..."
