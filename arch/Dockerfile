FROM archlinux:latest


RUN pacman -Syu --noconfirm \
        archiso base-devel git reflector \
        squashfs-tools dosfstools mtools xorriso wget curl htop 


RUN reflector --latest 20 --sort rate --save /etc/pacman.d/mirrorlist
RUN pacman-key --init && pacman-key --populate archlinux

RUN mkdir -p /home/dev

WORKDIR /home

#clone the general iso to inject the script later
RUN git clone https://gitlab.archlinux.org/archlinux/archiso.git &&\
	mkdir my-arch &&\
	cp -r archiso/configs/releng my-arch &&\
	rm -rf archiso #to save space cause we don't need all of that

WORKDIR /home/my-arch/releng

#copy the pacman config cause it fails on the final stage otherwise
RUN mkdir -p airootfs/etc/pacman.d && \
    cp /etc/pacman.conf airootfs/etc/pacman.conf && \
    cp /etc/pacman.d/mirrorlist airootfs/etc/pacman.d/mirrorlist

#copy the script and the .txt and .conf configs
COPY ./dev/*.sh airootfs/usr/local/bin/
COPY ./dev/*.txt airootfs/usr/local/bin/
COPY ./dev/*.conf airootfs/usr/local/bin/
COPY ./dev/*.csv airootfs/usr/local/bin/

#make it executable (https://gitlab.archlinux.org/archlinux/archiso/-/blob/master/docs/README.profile.rst)
RUN sed -i '$i ["/usr/local/bin/arch_init_install.sh"]="0:0:755"' ./profiledef.sh 

#copy the systemd service script so that our .sh script runs at boot time
COPY ./dev/arch_init_install.service airootfs/etc/systemd/system/

#use symlinks cause we are GAY (we need to force the run for systemd so we resort to this)
RUN mkdir -p airootfs/etc/systemd/system/multi-user.target.wants &&\
	ln -sf ../arch_init_install.service airootfs/etc/systemd/system/multi-user.target.wants/arch_init_install.service

#remove broadcom-wl cause it sometimes causes build failures and isn't that important anyway
RUN sed -i '/broadcom-wl/d' /home/my-arch/releng/packages.x86_64

#make working dir and the out dir for arch iso 
RUN mkdir ../iso_in_progress && mkdir ../iso_out


CMD ["bash", "-c", "mkarchiso -v -C /etc/pacman.conf -w ../iso_in_progress -o ../iso_out . && mv /home/my-arch/iso_out/archlinux-*.iso /home/dev/archlinux.iso && echo 'Done'"]
#CMD ["mkarchiso", "-v", "-C", "/etc/pacman.conf" ,"-w" ,"../iso_in_progress", "-o", "../iso_out", "."]

