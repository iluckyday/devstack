#!/bin/bash
set -e

DEVSTACK_BRANCH=master
#DEVSTACK_BRANCH=stable/ussuri
UBUNTU_RELEASE=focal

mount_dir=/tmp/devstack
mkdir -p ${mount_dir}

base_apps="systemd,systemd-sysv,sudo,iproute2,bash-completion,openssh-server,ca-certificates,busybox"
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

chroot ${mount_dir} useradd -s /bin/bash -m -G adm stack

cat << EOF > ${mount_dir}/etc/fstab
LABEL=ubuntu-root /            ext4    defaults,noatime             0 0
tmpfs             /tmp         tmpfs   mode=1777,size=80%           0 0
tmpfs             /var/log     tmpfs   defaults,noatime             0 0
EOF

cat << EOF > ${mount_dir}/etc/apt/apt.conf.d/99freedisk
APT::Authentication "0";
APT::Get::AllowUnauthenticated "1";
Dir::Cache "/dev/shm";
Dir::State::lists "/dev/shm";
Dir::Log "/dev/shm";
DPkg::Post-Invoke {"/bin/rm -f /dev/shm/archives/*.deb || true";};
EOF

cat << EOF > ${mount_dir}/etc/apt/apt.conf.d/99norecommend
APT::Install-Recommends "0";
APT::Install-Suggests "0";
EOF

cat << EOF > ${mount_dir}/etc/dpkg/dpkg.cfg.d/99nofiles
path-exclude *__pycache__*
path-exclude *.py[co]
path-exclude /usr/share/doc/*
path-exclude /usr/share/man/*
path-exclude /usr/share/bug/*
path-exclude /usr/share/groff/*
path-exclude /usr/share/info/*
path-exclude /usr/share/lintian/*
path-exclude /usr/share/linda/*
path-exclude /usr/share/locale/*
path-exclude /usr/lib/locale/*
path-include /usr/share/locale/en*
path-exclude /usr/include/*
#path-exclude /usr/lib/python3/dist-packages/*/tests*
path-exclude /usr/lib/x86_64-linux-gnu/perl/5.30.3/auto/Encode/CN*
path-exclude /usr/lib/x86_64-linux-gnu/perl/5.30.3/auto/Encode/JP*
path-exclude /usr/lib/x86_64-linux-gnu/perl/5.30.3/auto/Encode/KR*
path-exclude /usr/lib/x86_64-linux-gnu/perl/5.30.3/auto/Encode/TW*
path-exclude *bin/perror
path-exclude *bin/mysqlslap
path-exclude *bin/mysqlbinlog
path-exclude *bin/x86_64-linux-gnu-dwp
path-exclude *bin/mysql_embedded
path-exclude *bin/systemd-analyze
path-exclude *bin/resolve_stack_dump
path-exclude *bin/mysql_tzinfo_to_sql
path-exclude *bin/sqldiff
path-exclude *bin/etcdctl
path-exclude *bin/myisamlog
path-exclude *bin/mysqldump
path-exclude *bin/aria_dump_log
path-exclude *bin/mysqlimport
path-exclude *bin/pdata_tools
path-exclude /boot/System.map*
path-exclude /lib/modules/*/fs/ocfs2*
path-exclude /lib/modules/*/fs/nls*
path-exclude /lib/modules/*/fs/ceph*
path-exclude /lib/modules/*/fs/jffs2*
path-exclude /lib/modules/*/fs/orangefs*
path-exclude /lib/modules/*/fs/ufs*
path-exclude /lib/modules/*/net/wireless*
path-exclude /lib/modules/*/net/mpls*
path-exclude /lib/modules/*/net/wimax*
path-exclude /lib/modules/*/net/l2tp*
path-exclude /lib/modules/*/net/nfc*
path-exclude /lib/modules/*/net/tipc*
path-exclude /lib/modules/*/net/appletalk*
path-exclude /lib/modules/*/net/rds*
path-exclude /lib/modules/*/net/dccp*
path-exclude /lib/modules/*/net/netrom*
path-exclude /lib/modules/*/net/lapb*
path-exclude /lib/modules/*/net/mac80211*
path-exclude /lib/modules/*/net/6lowpan*
path-exclude /lib/modules/*/net/sunrpc*
path-exclude /lib/modules/*/net/rxrpc*
path-exclude /lib/modules/*/net/atm*
path-exclude /lib/modules/*/net/psample*
path-exclude /lib/modules/*/net/rose*
path-exclude /lib/modules/*/net/ax25*
path-exclude /lib/modules/*/net/8021q*
path-exclude /lib/modules/*/net/9p*
path-exclude /lib/modules/*/net/bluetooth*
path-exclude /lib/modules/*/net/ife*
path-exclude /lib/modules/*/net/ceph*
path-exclude /lib/modules/*/net/phonet*
path-exclude /lib/modules/*/drivers/media*
path-exclude /lib/modules/*/drivers/mfd*
path-exclude /lib/modules/*/drivers/hid*
path-exclude /lib/modules/*/drivers/nfc*
path-exclude /lib/modules/*/drivers/dca*
path-exclude /lib/modules/*/drivers/thunderbolt*
path-exclude /lib/modules/*/drivers/firmware*
path-exclude /lib/modules/*/drivers/xen*
path-exclude /lib/modules/*/drivers/spi*
path-exclude /lib/modules/*/drivers/uio*
path-exclude /lib/modules/*/drivers/hv*
path-exclude /lib/modules/*/drivers/ptp*
path-exclude /lib/modules/*/drivers/pcmcia*
path-exclude /lib/modules/*/drivers/isdn*
path-exclude /lib/modules/*/drivers/atm*
path-exclude /lib/modules/*/drivers/w1*
path-exclude /lib/modules/*/drivers/hwmon*
path-exclude /lib/modules/*/drivers/dax*
path-exclude /lib/modules/*/drivers/parport*
path-exclude /lib/modules/*/drivers/ssb*
path-exclude /lib/modules/*/drivers/infiniband*
path-exclude /lib/modules/*/drivers/gpu*
path-exclude /lib/modules/*/drivers/bluetooth*
path-exclude /lib/modules/*/drivers/video*
path-exclude /lib/modules/*/drivers/android*
path-exclude /lib/modules/*/drivers/nvme*
path-exclude /lib/modules/*/drivers/gnss*
path-exclude /lib/modules/*/drivers/firewire*
path-exclude /lib/modules/*/drivers/leds*
path-exclude /lib/modules/*/drivers/net/fddi*
path-exclude /lib/modules/*/drivers/net/hyperv*
path-exclude /lib/modules/*/drivers/net/xen-netback*
path-exclude /lib/modules/*/drivers/net/wireless*
path-exclude /lib/modules/*/drivers/net/ipvlan*
path-exclude /lib/modules/*/drivers/net/slip*
path-exclude /lib/modules/*/drivers/net/usb*
path-exclude /lib/modules/*/drivers/net/team*
path-exclude /lib/modules/*/drivers/net/ppp*
path-exclude /lib/modules/*/drivers/net/can*
path-exclude /lib/modules/*/drivers/net/phy*
path-exclude /lib/modules/*/drivers/net/vmxnet3*
path-exclude /lib/modules/*/drivers/net/ieee802154*
path-exclude /lib/modules/*/drivers/net/fjes*
path-exclude /lib/modules/*/drivers/net/hippi*
path-exclude /lib/modules/*/drivers/net/wan*
path-exclude /lib/modules/*/drivers/net/plip*
path-exclude /lib/modules/*/drivers/net/appletalk*
path-exclude /lib/modules/*/drivers/net/wimax*
path-exclude /lib/modules/*/drivers/net/arcnet*
path-exclude /lib/modules/*/drivers/net/hamradio*
path-exclude /lib/modules/*/sound*
EOF

mkdir -p ${mount_dir}/etc/systemd/system-environment-generators
cat << EOF > ${mount_dir}/etc/systemd/system-environment-generators/20-python
#!/bin/sh
echo 'PYTHONDONTWRITEBYTECODE=1'
echo 'PYTHONSTARTUP=/usr/lib/pythonstartup'
EOF
chmod +x ${mount_dir}/etc/systemd/system-environment-generators/20-python

cat << EOF > ${mount_dir}/etc/profile.d/python.sh
#!/bin/sh
export PYTHONDONTWRITEBYTECODE=1 PYTHONSTARTUP=/usr/lib/pythonstartup
EOF

cat << EOF > ${mount_dir}/usr/lib/pythonstartup
import readline
import time

readline.add_history("# " + time.asctime())
readline.set_history_length(-1)
EOF

mkdir -p ${mount_dir}/etc/initramfs-tools/conf.d
cat << EOF > ${mount_dir}/etc/initramfs-tools/conf.d/custom
COMPRESS=xz
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

cat << EOF > ${mount_dir}/etc/systemd/system/devstack@var-log-dirs.service
[Unit]
Description=Create /var/log sub-directories for DevStack
After=var-log.mount
[Service]
Type=oneshot
ExecStart=/bin/bash -c "mkdir /var/log/{rabbitmq,apache2};chown rabbitmq:rabbitmq /var/log/rabbitmq"
RemainAfterExit=yes
[Install]
WantedBy=local-fs.target
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
VERBOSE=False
SYSLOG=True
ENABLE_DEBUG_LOG_LEVEL=False
DEBUG_LIBVIRT=False
GIT_BASE=https://github.com
EOF

cat << EOF > ${mount_dir}/home/stack/.devstack-install.sh
#!/bin/bash
set -e

ip address show
cat /etc/resolv.conf
nslookup www.google.com

sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt install -y git

git clone -b $DEVSTACK_BRANCH --depth=1 https://opendev.org/openstack/devstack /tmp/devstack
cp /home/stack/.devstack-local.conf /tmp/devstack/local.conf

sed -i '/postgresql-server-dev-all/d' /tmp/devstack/files/debs/neutron-common
sed -i 's/qemu-system/qemu-system-x86/' /tmp/devstack/lib/nova_plugins/functions-libvirt

/tmp/devstack/stack.sh
EOF

cat << "EOF" > ${mount_dir}/home/stack/.devstack-install-post.sh
#!/bin/bash
rm -rf /etc/resolv.conf
echo 'nameserver 1.1.1.1' > /etc/resolv.conf

systemctl set-default multi-user.target
systemctl enable devstack@var-log-dirs.service

apt remove -y --purge git git-man
find /usr /opt -type d -name __pycache__ -prune -exec rm -rf {} +
find /usr/*/locale -mindepth 1 -maxdepth 1 ! -name 'en' -a ! -name 'en_US' -prune -exec rm -rf {} +
find /usr/share/zoneinfo -mindepth 1 -maxdepth 2 ! -name 'UTC' -a ! -name 'UCT' -a ! 'Etc' -a ! '*UTC' -a ! '*UCT' -a ! -name 'PRC' -a ! -name 'Asia' -a ! -name '*Shanghai' -prune -exec rm -rf {} +
rm -rf /var/lib/mysql/ib_logfile* /opt/stack/data/etcd/member/wal/0.tmp
rm -rf /usr/share/doc /usr/local/share/doc /usr/share/man /usr/share/icons /usr/share/fonts /usr/share/X11 /usr/share/AAVMF /usr/share/OVMF /tmp/* /var/tmp/* /var/cache/apt/* /var/lib/apt/lists/* /usr/lib/x86_64-linux-gnu/dri
rm -rf /etc/libvirt/qemu/networks/autostart/default.xml
rm -rf /home/stack/.devstack* /opt/stack/{devstack.subunit,requirements,logs} /opt/stack/{glance,horizon,keystone,neutron,nova,placement}/{releasenotes,playbooks,.git,doc} /home/stack/.wget-hsts /etc/systemd/system/last.target /etc/systemd/system/last.target.wants /etc/systemd/system/devstack-install.service
EOF

rm -f ${mount_dir}/etc/resolv.conf
echo 'nameserver 1.1.1.1' > ${mount_dir}/etc/resolv.conf
echo 'nameserver 1.1.1.1' > ${mount_dir}/etc/resolv.conf.ORIG
echo devstack > ${mount_dir}/etc/hostname
echo 127.0.0.1 localhost devstack >> ${mount_dir}/etc/hosts

mkdir -p ${mount_dir}/boot/syslinux
cat << EOF > ${mount_dir}/boot/syslinux/syslinux.cfg
PROMPT 0
TIMEOUT 0
DEFAULT ubuntu

LABEL ubuntu
	LINUX /boot/vmlinuz
	INITRD /boot/initrd.img
	APPEND root=LABEL=ubuntu-root console=ttyS0 quiet
EOF

( umask 226 && echo "stack ALL=(ALL) NOPASSWD:ALL" > ${mount_dir}/etc/sudoers.d/50_stack_sh && echo 'Defaults env_keep+="PYTHONDONTWRITEBYTECODE"' > ${mount_dir}/etc/sudoers.d/env_keep )

chroot ${mount_dir} /bin/bash -c "
export PATH=/bin:/sbin:/usr/bin:/usr/sbin PYTHONDONTWRITEBYTECODE=1 DEBIAN_FRONTEND=noninteractive
sed -i 's/root:\*:/root::/' etc/shadow
echo stack:stack | chpasswd
sed -i '/src/d' /etc/apt/sources.list
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
systemctl set-default last.target
systemctl enable devstack-install.service systemd-networkd.service
systemctl disable $disable_services

apt update
apt install -y -o APT::Install-Recommends=0 -o APT::Install-Suggests=0 linux-image-kvm extlinux initramfs-tools
dd if=/usr/lib/EXTLINUX/mbr.bin of=$loopx
extlinux -i /boot/syslinux
rm -rf /var/log/* /tmp/* /var/tmp/*
"

chroot --userspec=stack:stack ${mount_dir} /bin/bash -c "
touch /home/stack/.hushlogin
echo -e 'export HISTSIZE=1000 LESSHISTFILE=/dev/null HISTFILE=/dev/null PYTHONWARNINGS=ignore\n\nsource .adminrc' >> /home/stack/.bashrc
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
# /tmp/ngrok tcp 22 --log stdout --log-level debug

#qemu-system-x86_64 -name devstack-building -machine q35,accel=kvm -cpu host -smp "$(nproc)" -m 6G -nographic -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0 -boot c -drive file=/tmp/devstack.raw,if=virtio,format=raw,media=disk -netdev user,id=n0,ipv6=off -device virtio-net,netdev=n0
qemu-system-x86_64 -name devstack-building -machine q35,accel=kvm -cpu kvm64 -smp "$(nproc)" -m 6G -nographic -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0 -boot c -drive file=/tmp/devstack.raw,if=virtio,format=raw,media=disk -netdev user,id=n0,ipv6=off -device virtio-net,netdev=n0

sleep 1
sync
sleep 1
sync
sleep 1

echo "Original image size:"
du -h /tmp/devstack.raw

echo Converting ...
qemu-img convert -f raw -c -O qcow2 /tmp/devstack.raw /dev/shm/devstack.img

echo "Compressed image size:"
du -h /dev/shm/devstack.img
# /tmp/ngrok tcp 22 --log stdout --log-level debug

exit 0
