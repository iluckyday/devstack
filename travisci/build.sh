#!/bin/sh
set -ex

DEVSTACK_BRANCH=master

base_apps="sudo,bash-completion,openssh-server"
exclude_apps="ifupdown,unattended-upgrades"

mount_dir=/tmp/stack

qemu-img create -f raw /tmp/stack.raw 201G
loopx=$(losetup --show -f -P /tmp/stack.raw)

mkfs.ext4 -F -L debian-root -b 1024 -I 128 -O "^has_journal" $loopx

mkdir -p ${mount_dir}
mount $loopx ${mount_dir}

/usr/sbin/debootstrap --no-check-gpg --no-check-certificate --components=main,contrib,non-free --include="$base_apps" --exclude="$exclude_apps" sid ${mount_dir}

echo Config system ...
mount -t proc none ${mount_dir}/proc
mount -o bind /sys ${mount_dir}/sys
mount -o bind /dev ${mount_dir}/dev

chroot ${mount_dir} useradd -s /bin/bash -m stack

cat << EOF > ${mount_dir}/etc/fstab
LABEL=debian-root /            ext4    defaults,noatime             0 0
tmpfs             /tmp         tmpfs   mode=1777,size=80%           0 0
EOF

mkdir -p ${mount_dir}/etc/apt/apt.conf.d
cat << EOF > ${mount_dir}/etc/apt/apt.conf.d/99-freedisk
APT::Authentication "0";
APT::Get::AllowUnauthenticated "1";
Dir::Cache "/dev/shm";
Dir::State::lists "/dev/shm";
Dir::Log "/dev/shm";
DPkg::Post-Invoke {"/bin/rm -f /dev/shm/archives/*.deb || true";};
EOF

mkdir -p ${mount_dir}/etc/dpkg/dpkg.cfg.d
cat << EOF > ${mount_dir}/etc/dpkg/dpkg.cfg.d/99-nodoc
path-exclude /usr/share/doc/*
path-exclude /usr/share/man/*
path-exclude /usr/share/groff/*
path-exclude /usr/share/info/*
path-exclude /usr/share/lintian/*
path-exclude /usr/share/linda/*
path-exclude /usr/share/locale/*
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
Wants=network-online.target
After=network-online.target
ConditionPathExists=!/etc/devstack-version
SuccessAction=poweroff-force

[Service]
Type=oneshot
User=stack
StandardOutput=journal+console
ExecStart=/bin/bash /home/stack/.devstack-install.sh
ExecStart=+/bin/bash /home/stack/.devstack-install-post.sh
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
DOWNLOAD_DEFAULT_IMAGES=True
RECLONE=yes
FORCE=yes
VERBOSE=True
SYSLOG=True
ENABLE_DEBUG_LOG_LEVEL=False
DEBUG_LIBVIRT=False
EOF

cat << EOF > ${mount_dir}/home/stack/.devstack-install.sh
#!/bin/bash
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt install -y git python3-distutils

git clone -b $DEVSTACK_BRANCH https://opendev.org/openstack/devstack /tmp/devstack
cp /home/stack/.devstack-local.conf /tmp/devstack/local.conf

sed -i -e 's/libmysqlclient-dev/default-libmysqlclient-dev/' -e 's/mysql-server/mariadb-server/' /tmp/devstack/files/debs/{nova,neutron-common,general}

/tmp/devstack/stack.sh
EOF

cat << EOF > ${mount_dir}/home/stack/.devstack-install-post.sh
#!/bin/bash
systemctl set-default multi-user.target

find /usr -type d -name __pycache__ -prune -exec rm -rf {} +
find /usr/*/locale -mindepth 1 -maxdepth 1 ! -name 'en' -prune -exec rm -rf {} +
find /usr/share/zoneinfo -mindepth 1 -maxdepth 2 ! -name 'UTC' -a ! -name 'UCT' -a ! -name 'PRC' -a ! -name 'Asia' -a ! -name '*Shanghai' -prune -exec rm -rf {} +
rm -rf /etc/resolv.conf /usr/share/doc /usr/local/share/doc /usr/share/man /tmp/* /var/log/* /var/tmp/* /var/cache/apt/* /var/lib/apt/lists/*
rm -rf /lib/modules/*/kernel/sound /lib/modules/*/kernel/net/wireless /lib/modules/*/kernel/drivers/net/wireless /lib/modules/*/kernel/drivers/gpu /lib/modules/*/kernel/drivers/media /lib/modules/*/kernel/drivers/hid /lib/modules/*/kernel/drivers/usb /lib/modules/*/kernel/drivers/isdn /lib/modules/*/kernel/drivers/infiniband /lib/modules/*/kernel/drivers/video

rm -rf /etc/libvirt/qemu/networks/autostart/default.xml
rm -rf /home/stack/.devstack* /opt/stack/{devstack.subunit,requirements,logs} /opt/stack/{glance,horizon,keystone,logs,neutron,nova,placement}/{releasenotes,playbooks,.git,doc} /home/stack/.wget-hsts /etc/sudoers.d/50_stack_sh /etc/systemd/system/last.target /etc/systemd/system/last.target.wants /etc/systemd/system/devstack-install.service
EOF

echo -e 'nameserver 8.8.8.8\nnameserver 8.8.4.4' > ${mount_dir}/etc/resolv.conf.ORIG
echo devstack > ${mount_dir}/etc/hostname
mkdir ${mount_dir}/etc/systemd/system/last.target.wants ${mount_dir}/etc/systemd/system/sockets.target.wants ${mount_dir}/etc/systemd/system/network-online.target.wants
ln -sf /etc/systemd/system/last.target ${mount_dir}/etc/systemd/system/default.target
ln -sf /etc/systemd/system/devstack-install.service ${mount_dir}/etc/systemd/system/last.target.wants/devstack-install.service
ln -sf /lib/systemd/system/systemd-networkd.service ${mount_dir}/etc/systemd/system/dbus-org.freedesktop.network1.service
ln -sf /lib/systemd/system/systemd-networkd.service ${mount_dir}/etc/systemd/system/multi-user.target.wants/systemd-networkd.service
ln -sf /lib/systemd/system/systemd-networkd.socket ${mount_dir}/etc/systemd/system/sockets.target.wants/systemd-networkd.socket
ln -sf /lib/systemd/system/systemd-networkd-wait-online.service ${mount_dir}/etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service
for i in apt-daily.timer apt-daily-upgrade.timer man-db.timer e2scrub_all.timer logrotate.timer cron.service apparmor.service e2scrub_reap.service
do
	ln -sf /dev/null ${mount_dir}/etc/systemd/system/$i
done

mkdir -p ${mount_dir}/boot/syslinux
cat << EOF > ${mount_dir}/boot/syslinux/syslinux.cfg
PROMPT 0
TIMEOUT 0
DEFAULT debian

LABEL debian
	LINUX /vmlinuz
	INITRD /initrd.img
	APPEND root=LABEL=debian-root console=ttyS0 quiet
EOF

( umask 226 && echo "stack ALL=(ALL) NOPASSWD:ALL" > ${mount_dir}/etc/sudoers.d/50_stack_sh && echo 'Defaults env_keep+="PYTHONDONTWRITEBYTECODE"' > ${mount_dir}/etc/sudoers.d/env_keep )

chroot ${mount_dir} /bin/bash -c "
export PATH=/bin:/sbin:/usr/bin:/usr/sbin PYTHONDONTWRITEBYTECODE=1 DEBIAN_FRONTEND=noninteractive
useradd -s /bin/bash -m stack
sed -i '/src/d' /etc/apt/sources.list
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
apt update
apt install -y linux-image-amd64 extlinux
dd if=/usr/lib/syslinux/mbr/mbr.bin of=$loopx
extlinux -i /boot/syslinux
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

qemu-system-x86_64 -name devstack-building -machine q35,accel=kvm -cpu host -smp "$(nproc)" -m 6G -nographic -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0 -boot c -drive file=/tmp/stack.raw,if=virtio,format=raw,media=disk -netdev user,id=n0,ipv6=off -device virtio-net,netdev=n0

while pgrep -f "devstack-building" >/dev/null
do
	echo Building ...
	sleep 300
done

echo "Original image size:"
ls -lh /tmp/stack.raw

echo Converting ...
qemu-img convert -f raw -c -O qcow2 /tmp/stack.raw /dev/shm/devstack.cmp.img

echo "Compressed image size:"
ls -lh /dev/shm/devstack.cmp.img
exit 1
