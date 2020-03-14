#!/bin/bash
set -ex

#DEVSTACK_BRANCH=stable/train
DEVSTACK_BRANCH=master
DEBIAN_RELEASE=buster
DEBIAN_RELEASE_NUM=10
WORKDIR=/tmp/devstack
MNTDIR=$WORKDIR/mnt

mkdir -p $MNTDIR
cd $WORKDIR

version=$(curl -skL https://cdimage.debian.org/cdimage/cloud/$DEBIAN_RELEASE/daily | awk '/href/ {s=$0} END {print s}' | awk -F'"' '{sub(/\//,"",$6);print $6}')
curl -skL https://cdimage.debian.org/cdimage/cloud/$DEBIAN_RELEASE/daily/${version}/debian-$DEBIAN_RELEASE_NUM-nocloud-amd64-daily-${version}.tar.xz | tar -xJ

qemu-img resize -f raw disk.raw 203G
loopx=$(losetup --show -f -P disk.raw)
parted $loopx print fix
resize2fs -f ${loopx}p1
tune2fs -O '^has_journal' ${loopx}p1
sleep 1
mount ${loopx}p1 $MNTDIR

chroot $MNTDIR useradd -s /bin/bash -m stack
chroot --userspec=stack:stack $MNTDIR /bin/bash -c "
touch /home/stack/.hushlogin
echo -e 'export HISTSIZE=1000 LESSHISTFILE=/dev/null HISTFILE=/dev/null\n\nsource .adminrc' >> /home/stack/.bashrc
mkdir -p /home/stack/.ssh
chmod 700 /home/stack/.ssh
echo ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDyuzRtZAyeU3VGDKsGk52rd7b/rJ/EnT8Ce2hwWOZWp > /home/stack/.ssh/authorized_keys
chmod 600 home/stack/.ssh/authorized_keys
"

( umask 226 && echo "stack ALL=(ALL) NOPASSWD:ALL" > $MNTDIR/etc/sudoers.d/50_stack_sh )
( umask 226 && echo 'Defaults env_keep+="PYTHONDONTWRITEBYTECODE PYTHONHISTFILE"' > $MNTDIR/etc/sudoers.d/env_keep )

mkdir -p $MNTDIR/etc/{systemd/system-environment-generators,sysctl.d,profile.d,dpkg/dpkg.cfg.d,apt/apt.conf.d,sudoers.d} $MNTDIR/etc/systemd/{system,network,journald.conf.d}

cat << EOF > $MNTDIR/etc/profile.d/python.sh
#!/bin/sh
export PYTHONDONTWRITEBYTECODE=1 PYTHONHISTFILE=/dev/null
EOF

cat << EOF > $MNTDIR/etc/systemd/system-environment-generators/20-python
#!/bin/sh
echo 'PYTHONDONTWRITEBYTECODE=1'
echo 'PYTHONHISTFILE=/dev/null'
EOF
chmod +x $MNTDIR/etc/systemd/system-environment-generators/20-python

cat << EOF > $MNTDIR/etc/apt/apt.conf.d/99-freedisk
APT::Authentication "0";
APT::Get::AllowUnauthenticated "1";
Dir::Cache "/dev/shm";
Dir::State::lists "/dev/shm";
Dir::Log "/dev/shm";
DPkg::Post-Invoke {"/bin/rm -f /dev/shm/archives/*.deb || true";};
EOF

cat << EOF > $MNTDIR/etc/dpkg/dpkg.cfg.d/99-nodoc
path-exclude /usr/share/doc/*
path-exclude /usr/share/man/*
path-exclude /usr/share/groff/*
path-exclude /usr/share/info/*
path-exclude /usr/share/lintian/*
path-exclude /usr/share/linda/*
path-exclude /usr/share/locale/*
path-include /usr/share/locale/en*
EOF

cat << EOF > $MNTDIR/etc/pip.conf
[global]
download-cache = /tmp
cache-dir = /tmp
EOF

cat << EOF > $MNTDIR/etc/sysctl.d/20-tcp-bbr.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

cat << EOF > $MNTDIR/etc/systemd/journald.conf.d/storage.conf
[Journal]
Storage=volatile
EOF

cat << EOF > $MNTDIR/etc/systemd/network/20-dhcp.network
[Match]
Name=en*
[Network]
DHCP=ipv4
EOF

cat << EOF > $MNTDIR/etc/systemd/network/30-br-ex.network
[Match]
Name=br-ex
[Network]
Address=172.24.4.1/24
EOF

cat << EOF > $MNTDIR/etc/systemd/system/last.target
[Unit]
Description=Last Target for Last Commands
Requires=multi-user.target
After=multi-user.target
Conflicts=rescue.service rescue.target
EOF

cat << EOF > $MNTDIR/etc/systemd/system/devstack-install.service
[Unit]
Description=DevStack Install Service
Wants=network-online.target
After=network-online.target
ConditionPathExists=!/etc/devstack-version
SuccessAction=poweroff
[Service]
Type=oneshot
User=stack
ExecStart=/bin/bash /home/stack/.devstack-install.sh
ExecStart=+/bin/bash /home/stack/.devstack-install-post.sh
EOF

cat << EOF > $MNTDIR/home/stack/.adminrc
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

cat << EOF > $MNTDIR/home/stack/.devstack-local.conf
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
LIBVIRT_TYPE=kvm
DOWNLOAD_DEFAULT_IMAGES=True
RECLONE=yes
FORCE=yes
VERBOSE=False
SYSLOG=True
ENABLE_DEBUG_LOG_LEVEL=False
DEBUG_LIBVIRT=False
EOF

cat << EOF > $MNTDIR/home/stack/.devstack-install.sh
#!/bin/bash
apt update
apt install -y git

git clone -b $DEVSTACK_BRANCH https://opendev.org/openstack/devstack /tmp/devstack
cp /home/stack/.devstack-local.conf /tmp/devstack/local.conf
/tmp/devstack/stack.sh
EOF

cat << EOF > $MNTDIR/home/stack/.devstack-install-post.sh
#!/bin/bash
systemctl set-default multi-user.target

find / ! -path /proc ! -path /sys -type d -name __pycache__ -delete 2>/dev/null
find /usr/share/locale -mindepth 1 -maxdepth 1 ! -name 'en' -delete 2>/dev/null
rm -rf /etc/libvirt/qemu/networks/autostart/default.xml /usr/share/doc/* /usr/local/share/doc/* /usr/share/man/* /tmp/* /var/tmp/* /var/cache/apt/*
rm -rf /home/stack/.devstack* /opt/stack/{devstack.subunit,requirements,logs} /opt/stack/{glance,horizon,keystone,logs,neutron,nova,placement}/{releasenotes,playbooks,.git,doc} /home/stack/.wget-hsts /etc/sudoers.d/50_stack_sh /etc/systemd/system/last.target /etc/systemd/system/last.target.wants /etc/systemd/system/devstack-install.service
EOF


ln -sf /usr/share/zoneinfo/Asia/Shanghai $MNTDIR/etc/localtime
echo -e 'nameserver 8.8.8.8\nnameserver 8.8.4.4' > $MNTDIR/etc/resolv.conf.ORIG
echo devstack > $MNTDIR/etc/hostname
echo -e '\n\nnet.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr' > $MNTDIR/etc/sysctl.conf
ln -sf /etc/systemd/system/last.target $MNTDIR/etc/systemd/system/default.target
ln -sf /etc/systemd/system/devstack-install.service $MNTDIR/etc/systemd/system/last.target.wants/devstack-install.service
ln -sf /lib/systemd/system/systemd-networkd.service $MNTDIR/etc/systemd/system/dbus-org.freedesktop.network1.service
ln -sf /lib/systemd/system/systemd-networkd.service $MNTDIR/etc/systemd/system/multi-user.target.wants/systemd-networkd.service
ln -sf /lib/systemd/system/systemd-networkd.socket $MNTDIR/etc/systemd/system/sockets.target.wants/systemd-networkd.socket
ln -sf /lib/systemd/system/systemd-networkd-wait-online.service $MNTDIR/etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service
for i in apt-daily.timer apt-daily-upgrade.timer man-db.timer e2scrub_all.timer logrotate.timer cron.service chrony.service apparmor.service e2scrub_reap.service unattended-upgrades.service ifup@.service
do
	ln -sf /dev/null $MNTDIR/etc/systemd/system/$i
done

for f in /var/log/* /usr/share/doc/* /usr/share/local/doc/* /usr/share/man/* /tmp/* /var/tmp/* /var/cache/apt/* ; do
    rm -rf $MNTDIR$f
done

find $MNTDIR/usr/share/zoneinfo -mindepth 1 -maxdepth 2 ! -name 'UTC' -a ! -name 'UCT' -a ! -name 'PRC' -a ! -name 'Asia' -a ! -name '*Shanghai' -exec rm -rf {} + || true

sed -i -e 's/defaults/defaults,noatime/' -e 's/discard/discard,noatime/' $MNTDIR/etc/fstab
echo tmpfs /tmp tmpfs rw,mode=1777,strictatime,nosuid,nodev,size=90% 0 0 >> $MNTDIR/etc/fstab
sed -i 'src/d' $MNTDIR/etc/apt/sources.list

cd /tmp
sync $MNTDIR
sleep 1
umount ${loopx}p1
sleep 1
losetup -d $loopx
sleep 1

qemu-system-x86_64 -name devstack-building -daemonize -machine q35,accel=kvm -cpu host -smp "$(nproc)" -m 6G -display none -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0 -boot c -drive file=$WORKDIR/disk.raw,if=virtio,format=qcow2,media=disk -netdev user,id=n0,ipv6=off -device virtio-net,netdev=n0

while pgrep -f "devstack-building" >/dev/null
do
    echo Building ...
    sleep 300
done

echo "Original image size:"
ls -lh $WORKDIR/disk.raw

echo Converting ...
qemu-img convert -f raw -c -O qcow2 $WORKDIR/disk.raw /dev/shm/devstack.cmp.img

echo "Compressed image size:"
ls -lh /dev/shm/devstack.cmp.img
