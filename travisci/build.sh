#!/bin/bash
set -e

#DEVSTACK_BRANCH=master
DEVSTACK_BRANCH=stable/train
UBUNTU_RELEASE=bionic

mount_dir=/tmp/devstack
mkdir -p ${mount_dir}

base_apps="systemd,systemd-sysv,sudo,iproute2,bash-completion,openssh-server,tzdata"
exclude_apps="ifupdown,unattended-upgrades"
disable_services="e2scrub_reap.service \
systemd-timesyncd.service \
systemd-resolved.service \
apt-daily.timer \
apt-daily-upgrade.timer \
fstrim.timer \
e2scrub_all.timer \
motd-news.timer"

apt-config dump | grep -we Recommends -e Suggests | sed 's/1/0/' | tee /etc/apt/apt.conf.d/99norecommends

qemu-img create -f raw /tmp/devstack.raw 201G
loopx=$(losetup --show -f -P /tmp/devstack.raw)
mkfs.ext4 -F -L ubuntu-root -b 1024 -I 128 -O "^has_journal" $loopx
mount $loopx ${mount_dir}

sed -i 's/ls -A/ls --ignore=lost+found -A/' /usr/sbin/debootstrap
debootstrap --no-check-gpg --no-check-certificate --components=main,universe,restricted,multiverse --variant minbase --include "$base_apps" $UBUNTU_RELEASE ${mount_dir}

mount -t proc none ${mount_dir}/proc
mount -o bind /sys ${mount_dir}/sys
mount -o bind /dev ${mount_dir}/dev

chroot ${mount_dir} useradd -s /bin/bash -m stack

cat << EOF > ${mount_dir}/etc/fstab
LABEL=ubuntu-root /            ext4    defaults,noatime             0 0
tmpfs             /tmp         tmpfs   mode=1777,size=80%           0 0
EOF

cat << EOF > ${mount_dir}/etc/apt/apt.conf.d/99-freedisk
APT::Authentication "0";
APT::Get::AllowUnauthenticated "1";
Dir::Cache "/dev/shm";
Dir::State::lists "/dev/shm";
Dir::Log "/dev/shm";
DPkg::Post-Invoke {"/bin/rm -f /dev/shm/archives/*.deb || true";};
EOF

cat << EOF > ${mount_dir}/etc/apt/apt.conf.d/99norecommend
APT::Install-Recommends "1";
APT::Install-Suggests "0";
EOF

cat << EOF > ${mount_dir}/etc/dpkg/dpkg.cfg.d/99-nodoc
path-exclude /usr/share/doc/*
path-exclude /usr/share/man/*
path-exclude /usr/share/groff/*
path-exclude /usr/share/info/*
path-exclude /usr/share/lintian/*
path-exclude /usr/share/linda/*
path-exclude /usr/share/locale/*
path-exclude /usr/lib/locale/*
path-include /usr/share/locale/en*
EOF

mkdir -p ${mount_dir}/etc/systemd/journald.conf.d
cat << EOF > ${mount_dir}/etc/systemd/journald.conf.d/storage.conf
[Journal]
Storage=volatile
EOF

mkdir -p ${mount_dir}/etc/systemd/system-environment-generators
cat << EOF > ${mount_dir}/etc/systemd/system-environment-generators/20-python
#!/bin/sh
echo 'PYTHONDONTWRITEBYTECODE=1'
echo 'PYTHONHISTFILE=/dev/null'
EOF
chmod +x ${mount_dir}/etc/systemd/system-environment-generators/20-python

cat << EOF > ${mount_dir}/etc/profile.d/python.sh
#!/bin/sh
export PYTHONDONTWRITEBYTECODE=1 PYTHONHISTFILE=/dev/null
EOF

cat << EOF > ${mount_dir}/etc/pip.conf
[global]
download-cache=/tmp
cache-dir=/tmp
EOF

cat << EOF > ${mount_dir}/etc/systemd/network/20-dhcp.network
[Match]
Name=en*
[Network]
DHCP=ipv4
EOF

cat << EOF > ${mount_dir}/etc/systemd/network/30-br-ex.network
[Match]
Name=br-ex
[Network]
Address=172.24.4.1/24
EOF

cat << EOF > ${mount_dir}/etc/systemd/system/last.target
[Unit]
Description=Last Target for Last Commands
Requires=multi-user.target
After=multi-user.target
Conflicts=rescue.service rescue.target
EOF

cat << EOF > ${mount_dir}/etc/systemd/system/devstack-install.service
[Unit]
Description=DevStack Install Service
ConditionPathExists=!/etc/devstack-version
SuccessAction=poweroff-force

[Service]
Type=oneshot
User=stack
StandardOutput=journal+console
ExecStart=/bin/bash /home/stack/.devstack-install.sh
ExecStart=+/bin/bash /home/stack/.devstack-install-post.sh

[Install]
WantedBy=last.target
EOF

cat << EOF > ${mount_dir}/home/stack/.adminrc
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

cat << EOF > ${mount_dir}/home/stack/.devstack-local.conf
[[local|localrc]]
disable_service tempest dstat
disable_service c-sch c-api c-vol
disable_service horizon
ADMIN_PASSWORD=devstack
DATABASE_PASSWORD=devstack
SERVICE_PASSWORD=devstack
RABBIT_PASSWORD=devstack
PIP_UPGRADE=True
USE_PYTHON3=True
ENABLE_IDENTITY_V2=False
IP_VERSION=4
GIT_DEPTH=1
SERVICE_IP_VERSION=4
HOST_IP=10.0.2.15
MYSQL_SERVICE_NAME=mariadb
LIBVIRT_TYPE=kvm
#DOWNLOAD_DEFAULT_IMAGES=True
RECLONE=yes
FORCE=yes
VERBOSE=True
SYSLOG=True
ENABLE_DEBUG_LOG_LEVEL=False
DEBUG_LIBVIRT=False
EOF

cat << EOF > ${mount_dir}/home/stack/.devstack-install.sh
#!/bin/bash
set -e

sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt install -y git

git clone -b $DEVSTACK_BRANCH --depth=1 https://opendev.org/openstack/devstack /tmp/devstack
cp /home/stack/.devstack-local.conf /tmp/devstack/local.conf

sed -i '/postgresql-server-dev-all/d' /tmp/devstack/files/debs/neutron-common
sed -i 's/qemu-system/qemu-system-x86/' /tmp/devstack/lib/nova_plugins/functions-libvirt

/tmp/devstack/stack.sh

sleep 5
dpkg -l
EOF

cat << EOF > ${mount_dir}/home/stack/.devstack-install-post.sh
#!/bin/bash
systemctl set-default multi-user.target

dpkg -P --force-depends git git-man iw crda wireless-regdb linux-firmware linux-modules-extra-$(uname -r) cpp g++ g++-7 gcc gcc-7
find /usr -type d -name __pycache__ -prune -exec rm -rf {} +
find /usr/*/locale -mindepth 1 -maxdepth 1 ! -name 'en' -a ! -name 'en_US' -prune -exec rm -rf {} +
find /usr/share/zoneinfo -mindepth 1 -maxdepth 2 ! -name 'UTC' -a ! -name 'UCT' -a ! -name 'PRC' -a ! -name 'Asia' -a ! -name '*Shanghai' -prune -exec rm -rf {} +
rm -rf /etc/resolv.conf /usr/share/doc /usr/local/share/doc /usr/share/man /usr/share/icons /usr/share/fonts /usr/share/X11 /usr/share/AAVMF /usr/share/OVMF /tmp/* /var/tmp/* /var/cache/apt/* /var/lib/apt/lists/* /usr/lib/x86_64-linux-gnu/dri
rm -rf /etc/libvirt/qemu/networks/autostart/default.xml
rm -rf /home/stack/.devstack* /opt/stack/{devstack.subunit,requirements,logs} /opt/stack/{glance,horizon,keystone,logs,neutron,nova,placement}/{releasenotes,playbooks,.git,doc} /home/stack/.wget-hsts /etc/sudoers.d/50_stack_sh /etc/systemd/system/last.target /etc/systemd/system/last.target.wants /etc/systemd/system/devstack-install.service
EOF

rm -f ${mount_dir}/etc/resolv.conf
echo -e 'nameserver 8.8.8.8\nnameserver 8.8.4.4' > ${mount_dir}/etc/resolv.conf
echo -e 'nameserver 8.8.8.8\nnameserver 8.8.4.4' > ${mount_dir}/etc/resolv.conf.ORIG
echo devstack > ${mount_dir}/etc/hostname
echo 127.0.0.1 devstack >> ${mount_dir}/etc/hosts

mkdir -p ${mount_dir}/boot/syslinux
cat << EOF > ${mount_dir}/boot/syslinux/syslinux.cfg
PROMPT 0
TIMEOUT 0
DEFAULT ubuntu

LABEL ubuntu
	LINUX /vmlinuz
	INITRD /initrd.img
	APPEND root=LABEL=ubuntu-root console=ttyS0 quiet
EOF

( umask 226 && echo "stack ALL=(ALL) NOPASSWD:ALL" > ${mount_dir}/etc/sudoers.d/50_stack_sh && echo 'Defaults env_keep+="PYTHONDONTWRITEBYTECODE"' > ${mount_dir}/etc/sudoers.d/env_keep )

chroot ${mount_dir} /bin/bash -c "
export PATH=/bin:/sbin:/usr/bin:/usr/sbin PYTHONDONTWRITEBYTECODE=1 DEBIAN_FRONTEND=noninteractive
sed -i 's/root:\*:/root::/' etc/shadow
sed -i '/src/d' /etc/apt/sources.list
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
systemctl set-default last.target
systemctl enable devstack-install.service systemd-networkd.service
systemctl disable $disable_services

apt update
apt install -y -o APT::Install-Recommends=0 -o APT::Install-Suggests=0 linux-image-generic extlinux initramfs-tools
dd if=/usr/lib/EXTLINUX/mbr.bin of=$loopx
extlinux -i /boot/syslinux
rm -rf /lib/modules/*/kernel/sound /lib/modules/*/kernel/net/wireless /lib/modules/*/kernel/drivers/net/wireless /lib/modules/*/kernel/drivers/gpu /lib/modules/*/kernel/drivers/media /lib/modules/*/kernel/drivers/hid /lib/modules/*/kernel/drivers/usb /lib/modules/*/kernel/drivers/isdn /lib/modules/*/kernel/drivers/infiniband /lib/modules/*/kernel/drivers/video
"

chroot --userspec=stack:stack ${mount_dir} /bin/bash -c "
touch /home/stack/.hushlogin
echo -e 'export HISTSIZE=1000 LESSHISTFILE=/dev/null HISTFILE=/dev/null\n\nsource .adminrc' >> /home/stack/.bashrc
mkdir -p /home/stack/.ssh
chmod 700 /home/stack/.ssh
echo ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDyuzRtZAyeU3VGDKsGk52rd7b/rJ/EnT8Ce2hwWOZWp > /home/stack/.ssh/authorized_keys
chmod 600 home/stack/.ssh/authorized_keys
"

sync ${mount_dir}
umount ${mount_dir}/dev ${mount_dir}/proc ${mount_dir}/sys
sleep 1
umount ${mount_dir}
sleep 1
losetup -d $loopx

echo "travis:travis" | sudo chpasswd
curl -skL -o /tmp/ngrok.zip https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-amd64.zip
unzip -d /tmp /tmp/ngrok.zip
chmod +x /tmp/ngrok
/tmp/ngrok authtoken $NGROK_TOKEN
#/tmp/ngrok tcp 22 --log stdout --log-level debug

qemu-system-x86_64 -name devstack-building -machine q35,accel=kvm -cpu host -smp "$(nproc)" -m 6G -nographic -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0 -boot c -drive file=/tmp/devstack.raw,if=virtio,format=raw,media=disk -netdev user,id=n0,ipv6=off -device virtio-net,netdev=n0

sleep 1
sync
sleep 1

echo "Original image size:"
du -h /tmp/devstack.raw
/tmp/ngrok tcp 22 --log stdout --log-level debug

echo Converting ...
qemu-img convert -f raw -c -O qcow2 /tmp/devstack.raw /dev/shm/devstack.img

echo "Compressed image size:"
du -h /dev/shm/devstack.img
exit 1
