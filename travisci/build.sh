#!/bin/bash
set -e

UBUNTU_RELEASE=bionic
WORKDIR=/tmp/devstack

sed -i '/src/d' /etc/apt/sources.list
rm -f /var/lib/dpkg/info/libc-bin.postinst /var/lib/dpkg/info/man-db.postinst /var/lib/dpkg/info/dbus.postinst

mkdir -p $WORKDIR/files $WORKDIR/files/home/stack $WORKDIR/files/etc/{systemd/system-environment-generators,profile.d,dpkg/dpkg.cfg.d,apt/apt.conf.d} $WORKDIR/files/etc/systemd/{system,network,journald.conf.d} $WORKDIR/elements/devstack/extra-data.d $WORKDIR/elements/devstack/cleanup.d

cat << "EOF" > $WORKDIR/elements/devstack/extra-data.d/99-zz-devstack
#!/bin/bash
sudo rm -f $TMP_HOOKS_PATH/*/*-cloud-init $TMP_HOOKS_PATH/*/*-debian-networking $TMP_HOOKS_PATH/*/*-baseline-environment
sudo sed -i 's/vga=normal/quiet ipv6.disable=1 intel_iommu=on/' $TMP_HOOKS_PATH/*/*-bootloader
EOF
chmod +x $WORKDIR/elements/devstack/extra-data.d/99-zz-devstack

cat << "EOF" > $WORKDIR/elements/devstack/cleanup.d/99-zz-devstack
#!/bin/bash
export TARGET_ROOT
export basedir=$(dirname ${ELEMENTS_PATH%%:*})
find ${basedir}/files -type f ! -name "authorized_keys" -exec bash -c 'dirname {} | sed -e "s@${basedir}/files@@" | xargs -I % bash -c "mkdir -p $TARGET_ROOT%; sudo cp {} $TARGET_ROOT%"' \;

sudo touch $TARGET_ROOT/home/${DIB_DEV_USER_USERNAME}/.hushlogin
echo -e "source .bash.conf\nsource .adminrc"| sudo tee -a $TARGET_ROOT/home/${DIB_DEV_USER_USERNAME}/.bashrc
echo devstack | sudo tee $TARGET_ROOT/etc/hostname
echo -e "\n\nnet.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr" | sudo tee -a $TARGET_ROOT/etc/sysctl.conf
sudo chroot $TARGET_ROOT ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
sed -i '/src/d' $TARGET_ROOT/etc/apt/sources.list

sudo chroot $TARGET_ROOT chown -R ${DIB_DEV_USER_USERNAME}:${DIB_DEV_USER_USERNAME} /home/${DIB_DEV_USER_USERNAME}
sudo chroot $TARGET_ROOT groupadd kvm
sudo chroot $TARGET_ROOT usermod -a -G kvm ${DIB_DEV_USER_USERNAME}
sudo chroot $TARGET_ROOT systemctl set-default last.target
sudo chroot $TARGET_ROOT systemctl enable systemd-networkd devstack-install.service
sudo chroot $TARGET_ROOT systemctl -f mask apt-daily.timer apt-daily-upgrade.timer fstrim.timer motd-news.timer

sudo chroot $TARGET_ROOT apt remove --purge -y networkd-dispatcher cpio crda iso-codes initramfs-tools initramfs-tools-bin initramfs-tools-core intel-microcode iucode-tool iw klibc-utils libklibc linux-firmware linux-modules-extra-* shared-mime-info wireless-regdb

sudo rm -rf $TARGET_ROOT/etc/dib-manifests $TARGET_ROOT/var/log/* $TARGET_ROOT/usr/share/doc/* $TARGET_ROOT/usr/share/man/* $TARGET_ROOT/tmp/* $TARGET_ROOT/var/tmp/* $TARGET_ROOT/var/cache/apt/*
sudo find $TARGET_ROOT/usr/lib/python* $TARGET_ROOT/usr/local/lib/python* $TARGET_ROOT/usr/share/python* -type f -name "*.py[co]" -o -type d -name __pycache__ -exec rm -rf {} +
sudo find $TARGET_ROOT/usr/share/locale -mindepth 1 -maxdepth 1 ! -name 'en' -exec rm -rf {} +
sudo find $TARGET_ROOT/usr/share/zoneinfo -mindepth 1 -maxdepth 2 ! -name 'UTC' -a ! -name 'UCT' -a ! -name 'PRC' -a ! -name 'Asia' -a ! -name '*Shanghai' -exec rm -rf {} +
EOF

chmod +x $WORKDIR/elements/devstack/cleanup.d/99-zz-devstack

cat << EOF > $WORKDIR/files/authorized_keys
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDyuzRtZAyeU3VGDKsGk52rd7b/rJ/EnT8Ce2hwWOZWp
EOF

cat << EOF > $WORKDIR/files/etc/fstab
LABEL=cloudimg-rootfs /    ext4  defaults,noatime                            0 0
tmpfs                 /tmp tmpfs mode=1777,strictatime,nosuid,nodev,size=90% 0 0
EOF

cat << EOF > /etc/profile.d/python.sh
export PYTHONDONTWRITEBYTECODE=1
EOF

cat << EOF > $WORKDIR/files/etc/systemd/system-environment-generators/20-python
#!/bin/sh

echo 'PYTHONDONTWRITEBYTECODE=1'
EOF
chmod +x $WORKDIR/files/etc/systemd/system-environment-generators/20-python

cat << EOF > $WORKDIR/files/etc/apt/apt.conf.d/99-freedisk
APT::Authentication "0";
APT::Get::AllowUnauthenticated "1";
Dir::Cache "/dev/shm";
Dir::State::lists "/dev/shm";
Dir::Log "/dev/shm";
DPkg::Post-Invoke {"/bin/rm -f /dev/shm/archives/*.deb || true";};
EOF

cat << EOF > $WORKDIR/files/etc/dpkg/dpkg.cfg.d/99-nodoc
path-exclude /usr/share/doc/*
path-exclude /usr/share/man/*
path-exclude /usr/share/groff/*
path-exclude /usr/share/info/*
path-exclude /usr/share/lintian/*
path-exclude /usr/share/linda/*
path-exclude /usr/share/locale/*
path-include /usr/share/locale/en*
EOF

cat << EOF > $WORKDIR/files/etc/pip.conf
[global]
download-cache = /tmp
cache-dir = /tmp
no-cache-dir = true
EOF

cat << EOF > $WORKDIR/files/etc/systemd/journald.conf.d/storage.conf
[Journal]
Storage=volatile
EOF

cat << EOF > $WORKDIR/files/etc/systemd/network/20-dhcp.network
[Match]
Name=en*

[Network]
DHCP=ipv4
EOF

cat << EOF > $WORKDIR/files/etc/systemd/network/30-br-ex.network
[Match]
Name=br-ex

[Network]
Address=172.24.4.1/24
EOF

cat << EOF > $WORKDIR/files/etc/systemd/system/last.target
[Unit]
Description=Last Target for Last Commands
Requires=multi-user.target
After=multi-user.target
Conflicts=rescue.service rescue.target
EOF

cat << EOF > $WORKDIR/files/etc/systemd/system/devstack-install.service
[Unit]
Description=DevStack Install Service
Wants=network-online.target
After=network-online.target
ConditionPathExists=!/etc/devstack-version
SuccessAction=poweroff

[Service]
Type=oneshot
User=stack
StandardOutput=journal+console
ExecStart=/bin/bash /home/stack/.devstack-install.sh
ExecStart=+/bin/bash /home/stack/.devstack-install-post.sh

[Install]
WantedBy=last.target
EOF

cat << EOF > $WORKDIR/files/home/stack/.bash.conf
export HISTSIZE=1000
export LESSHISTFILE=/dev/null
unset HISTFILE
EOF

cat << EOF > $WORKDIR/files/home/stack/.adminrc
export OS_USERNAME=admin
export OS_PASSWORD=devstack
export OS_AUTH_URL=http://10.0.2.15/identity
export OS_AUTH_TYPE=password
export OS_TENANT_NAME=admin
export OS_PROJECT_NAME=admin
export OS_REGION_NAME=RegionOne
export OS_IDENTITY_API_VERSION=3
export OS_VOLUME_API_VERSION=3
export OS_USER_DOMAIN_ID=default
export OS_PROJECT_DOMAIN_ID=default
EOF

cat << EOF > $WORKDIR/files/home/stack/.local.conf
[[local|localrc]]
disable_service tempest dstat
disable_service c-sch c-api c-vol
#disable_service horizon
ADMIN_PASSWORD=devstack
DATABASE_PASSWORD=devstack
SERVICE_PASSWORD=devstack
RABBIT_PASSWORD=devstack
PIP_UPGRADE=True
USE_PYTHON3=True
ENABLE_IDENTITY_V2=False
IP_VERSION=4
SERVICE_IP_VERSION=4
HOST_IP=10.0.2.15
LIBVIRT_TYPE=kvm
DOWNLOAD_DEFAULT_IMAGES=False
RECLONE=yes
FORCE=yes
# VERBOSE=False
VERBOSE=True
SYSLOG=True
ENABLE_DEBUG_LOG_LEVEL=False
DEBUG_LIBVIRT=False
EOF

cat << EOF > $WORKDIR/files/home/stack/.devstack-install.sh
#!/bin/bash

dpkg -l

git clone https://opendev.org/openstack/devstack /tmp/devstack
cp /home/stack/.local.conf /tmp/devstack/local.conf
/tmp/devstack/stack.sh
EOF

cat << EOF > $WORKDIR/files/home/stack/.devstack-install-post.sh
#!/bin/bash

find /opt/stack /usr/lib/python* /usr/local/lib/python* /usr/share/python* -type f -name "*.py[co]" -delete -o -type d -name __pycache__ -delete 2>/dev/null
find /usr/share/locale -mindepth 1 -maxdepth 1 ! -name 'en' -delete 2>/dev/null
rm -rf /etc/libvirt/qemu/networks/autostart/default.xml /usr/share/doc/* /usr/share/man/*
EOF

sed -i 's/4096/16384 -O ^has_journal/' `python3 -c "import os,diskimage_builder; print(os.path.dirname(diskimage_builder.__file__))"`/lib/disk-image-create


cat $WORKDIR/elements/devstack/extra-data.d/99-zz-devstack

DIB_QUIET=1 \
DIB_IMAGE_SIZE=200 \
DIB_JOURNAL_SIZE=0 \
DIB_EXTLINUX=1 \
ELEMENTS_PATH=$WORKDIR/elements \
DIB_RELEASE=$UBUNTU_RELEASE \
DIB_DEBIAN_COMPONENTS=main,restricted,universe,multiverse \
DIB_APT_MINIMAL_CREATE_INTERFACES=0 \
DIB_DEBOOTSTRAP_EXTRA_ARGS+=" --no-check-gpg" \
DIB_DEBOOTSTRAP_EXTRA_ARGS+=" --include=bash-completion,iproute2,tzdata,git,python3-distutils" \
DIB_DEBOOTSTRAP_EXTRA_ARGS+=" --exclude=unattended-upgrades" \
DIB_DISTRIBUTION_MIRROR_UBUNTU_INSECURE=1 \
DIB_DEV_USER_USERNAME=stack \
DIB_DEV_USER_PASSWORD=stack \
DIB_DEV_USER_SHELL=/bin/bash \
DIB_DEV_USER_AUTHORIZED_KEYS=$WORKDIR/files/authorized_keys \
DIB_DEV_USER_PWDLESS_SUDO=yes \
disk-image-create -o $WORKDIR vm block-device-mbr cleanup-kernel-initrd devuser devstack ubuntu-minimal

qemu-system-x86_64 -name devstack-building -machine q35,accel=kvm -cpu host -smp "$(nproc)" -m 6G -nographic -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0 -boot c -drive file=$WORKDIR.qcow2,if=virtio,format=qcow2,media=disk -netdev user,id=n0,ipv6=off -device virtio-net,netdev=n0
#qemu-system-x86_64 -name devstack-building -daemonize -machine q35,accel=kvm -cpu host -smp "$(nproc)" -m 6G -display none -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0 -boot c -drive file=$WORKDIR.qcow2,if=virtio,format=qcow2,media=disk -netdev user,id=n0,ipv6=off -device virtio-net,netdev=n0

while pgrep -f "devstack-building" >/dev/null
do
    echo Building...
    sleep 60
done

echo converting...

qemu-img convert -f qcow2 -c -O qcow2 $WORKDIR.qcow2 $WORKDIR.cmp.img

exit 0
