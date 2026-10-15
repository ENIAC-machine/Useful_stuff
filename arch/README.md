# Arch initialization script

# Quick start

To build and write your custom arch iso run

```bash
sudo bash ./build_and_run.sh --device {YOUR DISK}
```

Where `{YOUR DISK}` is the disk corresponding to the flash drive, for example `/dev/sda`


# Architecture

So basically I inject my custom scripts and their dependencies into the arch distro and rebuild
the image from there. The tree looks something like:

├── build_and_run.sh\
├── dev\
│   ├── amd_packages.txt\
│   ├── arch_chroot_script.sh\
│   ├── arch_init_install.service\
│   ├── arch_init_install.sh\
│   ├── arch_install_cfg.conf\
│   ├── intel_packages.txt\
│   ├── nvidia_packages.txt\
│   ├── packages.txt\
│   ├── pwds.conf\
│   └── users.csv\
├── Dockerfile\
├── image_write.sh\
└── run_container.sh

The **users.csv** file expects the following structure:

```csv
user,group,pwd
nerd,admins,FK_rules_3333
```
The **pwds.conf** expects 2 variables:
1. `NETWORK_PWD` - the password from the network you'll connect to
2. `ROOT_PWD` - the root password


* The current script assumes BTRFS FS as main, also makes XFS partition for data on SSD,
    all HDDs are XFS 
* I also set up the ability to connect to corporate networks cause the default iwctl doesn't
    support that but iwd does if configured (see docs for urself)
* There's a special `arch_init_install.service` for the script to start as soon as iwd is ready
* The tunable parameters are in the `dev/arch_install_cfg.conf` file 


Feel free to use as a starting point/ template for your own arch server. Keep in mind tho that this
    particular server is for AI computation (hence XFS for example)
