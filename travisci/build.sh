#!/bin/bash
set -ex

#DEVSTACK_BRANCH=stable/train
DEVSTACK_BRANCH=master
UBUNTU_RELEASE=bionic
WORKDIR=/tmp/devstack

mkdir -p $WORKDIR/elements/devstack/files/home/stack $WORKDIR/elements/devstack/files/etc/{systemd/system-environment-generators,profile.d,dpkg/dpkg.cfg.d,apt/apt.conf.d,sudoers.d} $WORKDIR/elements/devstack/files/etc/systemd/{system,network,journald.conf.d} $WORKDIR/elements/devstack/cleanup.d

cat << "EOF" > $WORKDIR/elements/devstack/cleanup.d/99-zz-devstack
#!/bin/bash
SCRIPTDIR=$(dirname $0)
cp -R $SCRIPTDIR/../files/* $TARGET_ROOT

chroot --userspec=${DIB_DEV_USER_USERNAME}:${DIB_DEV_USER_USERNAME} $TARGET_ROOT /bin/bash -c "
touch /home/${DIB_DEV_USER_USERNAME}/.hushlogin
echo -e 'export HISTSIZE=1000 LESSHISTFILE=/dev/null HISTFILE=/dev/null\n\nsource .adminrc' >> /home/${DIB_DEV_USER_USERNAME}/.bashrc
"

chroot $TARGET_ROOT /bin/bash -c "
chown -R ${DIB_DEV_USER_USERNAME}:${DIB_DEV_USER_USERNAME} /home/${DIB_DEV_USER_USERNAME}
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
echo -e 'nameserver 8.8.8.8\nnameserver 8.8.4.4' > /etc/resolv.conf.ORIG
echo devstack > /etc/hostname
echo -e '\n\nnet.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr' > /etc/sysctl.conf

groupadd kvm
usermod -a -G kvm ${DIB_DEV_USER_USERNAME}

systemctl set-default last.target
systemctl enable systemd-networkd devstack-install
systemctl disable e2scrub_reap.service
systemctl mask apt-daily.timer e2scrub_reap.service apt-daily-upgrade.timer e2scrub_all.timer fstrim.timer motd-news.timer

for f in /etc/dib-manifests /var/log/* /usr/share/doc/* /usr/share/local/doc/* /usr/share/man/* /tmp/* /var/tmp/* /var/cache/apt/* ; do
    rm -rf $TARGET_ROOT$f
done
find $TARGET_ROOT/usr/share/zoneinfo -mindepth 1 -maxdepth 2 ! -name 'UTC' -a ! -name 'UCT' -a ! -name 'PRC' -a ! -name 'Asia' -a ! -name '*Shanghai' -exec rm -rf {} +
"
EOF
chmod +x  $WORKDIR/elements/devstack/cleanup.d/99-zz-devstack

cat << EOF > $WORKDIR/elements/devstack/files/etc/fstab
LABEL=cloudimg-rootfs /    ext4  defaults,noatime                            0 0
tmpfs                 /tmp tmpfs mode=1777,strictatime,nosuid,nodev,size=90% 0 0
EOF

( umask 226 && echo 'Defaults env_keep+="PYTHONDONTWRITEBYTECODE PYTHONHISTFILE"' > $WORKDIR/elements/devstack/files/etc/sudoers.d/env_keep )

cat << EOF > $WORKDIR/elements/devstack/files/etc/profile.d/python.sh
#!/bin/sh

export PYTHONDONTWRITEBYTECODE=1 PYTHONHISTFILE=/dev/null
EOF

cat << EOF > $WORKDIR/elements/devstack/files/authorized_keys
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDyuzRtZAyeU3VGDKsGk52rd7b/rJ/EnT8Ce2hwWOZWp
EOF

cat << EOF > $WORKDIR/elements/devstack/files/etc/systemd/system-environment-generators/20-python
#!/bin/sh

echo 'PYTHONDONTWRITEBYTECODE=1'
echo 'PYTHONHISTFILE=/dev/null'
EOF
chmod +x $WORKDIR/elements/devstack/files/etc/systemd/system-environment-generators/20-python

cat << EOF > $WORKDIR/elements/devstack/files/etc/apt/apt.conf.d/99-freedisk
APT::Authentication "0";
APT::Get::AllowUnauthenticated "1";
Dir::Cache "/dev/shm";
Dir::State::lists "/dev/shm";
Dir::Log "/dev/shm";
DPkg::Post-Invoke {"/bin/rm -f /dev/shm/archives/*.deb || true";};
EOF

cat << EOF > $WORKDIR/elements/devstack/files/etc/dpkg/dpkg.cfg.d/99-nodoc
path-exclude /usr/share/doc/*
path-exclude /usr/share/man/*
path-exclude /usr/share/groff/*
path-exclude /usr/share/info/*
path-exclude /usr/share/lintian/*
path-exclude /usr/share/linda/*
path-exclude /usr/share/locale/*
path-include /usr/share/locale/en*
EOF

cat << EOF > $WORKDIR/elements/devstack/files/etc/pip.conf
[global]
download-cache = /tmp
cache-dir = /tmp
EOF

cat << EOF > $WORKDIR/elements/devstack/files/etc/systemd/journald.conf.d/storage.conf
[Journal]
Storage=volatile
EOF

cat << EOF > $WORKDIR/elements/devstack/files/etc/systemd/network/20-dhcp.network
[Match]
Name=en*

[Network]
DHCP=ipv4
EOF

cat << EOF > $WORKDIR/elements/devstack/files/etc/systemd/network/30-br-ex.network
[Match]
Name=br-ex

[Network]
Address=172.24.4.1/24
EOF

cat << EOF > $WORKDIR/elements/devstack/files/etc/systemd/system/last.target
[Unit]
Description=Last Target for Last Commands
Requires=multi-user.target
After=multi-user.target
Conflicts=rescue.service rescue.target
EOF

cat << EOF > $WORKDIR/elements/devstack/files/etc/systemd/system/devstack-install.service
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

[Install]
WantedBy=last.target
EOF

cat << EOF > $WORKDIR/elements/devstack/files/home/stack/.adminrc
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

cat << EOF > $WORKDIR/elements/devstack/files/home/stack/.devstack-local.conf
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

cat << EOF > $WORKDIR/elements/devstack/files/home/stack/.devstack-install.sh
#!/bin/bash

git clone -b $DEVSTACK_BRANCH https://opendev.org/openstack/devstack /tmp/devstack
cp /home/stack/.devstack-local.conf /tmp/devstack/local.conf
/tmp/devstack/stack.sh
EOF

cat << EOF > $WORKDIR/elements/devstack/files/home/stack/.devstack-install-post.sh
#!/bin/bash

systemctl set-default multi-user.target
apt-get remove --purge -y git git-man cpp g++ g++-7 gcc gcc-7 qemu-slof qemu-system-arm qemu-system-mips qemu-system-misc qemu-system-ppc qemu-system-s390x qemu-system-sparc
find /opt/stack /usr/lib/python* /usr/local/lib/python* /usr/share/python* /opt/stack -type f -name "*.py[co]" -delete -o -type d -name __pycache__ -delete 2>/dev/null
find /usr/share/locale -mindepth 1 -maxdepth 1 ! -name 'en' -delete 2>/dev/null
rm -rf /etc/libvirt/qemu/networks/autostart/default.xml /usr/share/doc/* /usr/local/share/doc/* /usr/share/man/*
rm -rf /home/stack/.devstack* /opt/stack/{devstack.subunit,requirements,logs} /opt/stack/{glance,horizon,keystone,logs,neutron,nova,placement}/{releasenotes,playbooks,.git,doc} /home/stack/.wget-hsts /etc/sudoers.d/50_stack_sh /etc/systemd/system/last.target /etc/systemd/system/last.target.wants /etc/systemd/system/devstack-install.service
EOF

PY_DIB_PATH=$(python3 -c "import os,diskimage_builder; print(os.path.dirname(diskimage_builder.__file__))")
sed -i 's/-i 4096/-i 16384 -O ^has_journal/' "$PY_DIB_PATH"/lib/disk-image-create
sed -i 's/linux-image-amd64/linux-image-cloud-amd64/' "$PY_DIB_PATH"/elements/debian-minimal/package-installs.yaml
sed -i 's/vga=normal/quiet ipv6.disable=1/' "$PY_DIB_PATH"/elements/bootloader/cleanup.d/51-bootloader
sed -i -e '/gnupg/d' "$PY_DIB_PATH"/elements/debian-minimal/root.d/75-debian-minimal-baseinstall
for i in cloud-init debian-networking baseline-environment baseline-tools write-dpkg-manifest copy-manifests-dir ; do
    rm -rf "$PY_DIB_PATH"/elements/*/*/*$i
done

DIB_QUIET=0 \
DIB_IMAGE_SIZE=200 \
DIB_JOURNAL_SIZE=0 \
DIB_EXTLINUX=1 \
ELEMENTS_PATH=$WORKDIR/elements \
DIB_IMAGE_CACHE=/dev/shm \
DIB_PYTHON_VERSION=3 \
DIB_RELEASE=$UBUNTU_RELEASE \
DIB_DEBIAN_COMPONENTS=main,restricted,universe,multiverse \
DIB_APT_MINIMAL_CREATE_INTERFACES=0 \
DIB_DEBOOTSTRAP_EXTRA_ARGS+=" --no-check-gpg" \
DIB_DEBOOTSTRAP_EXTRA_ARGS+=" --include=bash-completion,iproute2,tzdata,git" \
DIB_DEBOOTSTRAP_EXTRA_ARGS+=" --exclude=unattended-upgrades" \
DIB_DISTRIBUTION_MIRROR_UBUNTU_INSECURE=1 \
DIB_DEV_USER_USERNAME=stack \
DIB_DEV_USER_PASSWORD=stack \
DIB_DEV_USER_SHELL=/bin/bash \
DIB_DEV_USER_AUTHORIZED_KEYS=$WORKDIR/elements/devstack/files/authorized_keys \
DIB_DEV_USER_PWDLESS_SUDO=yes \
disk-image-create -o /tmp/devstack.qcow2 vm block-device-mbr cleanup-kernel-initrd devuser devstack ubuntu-minimal

qemu-system-x86_64 -name devstack-building -daemonize -machine q35,accel=kvm -cpu host -smp "$(nproc)" -m 6G -display none -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0 -boot c -drive file=/tmp/devstack.qcow2,if=virtio,format=qcow2,media=disk -netdev user,id=n0,ipv6=off -device virtio-net,netdev=n0

while pgrep -f "devstack-building" >/dev/null
do
    echo Building ...
    sleep 300
done

echo "Original image size:"
ls -lh /tmp/devstack.qcow2

echo Converting ...
qemu-img convert -f qcow2 -c -O qcow2 /tmp/devstack.qcow2 /dev/shm/devstack.cmp.img

echo "Compressed image size:"
ls -lh /dev/shm/devstack.cmp.img
