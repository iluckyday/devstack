#!/bin/bash

DEVSTACK_BRANCH=master

CLOUD_IMAGES_URL=http://cloud-images.ubuntu.com/releases
CLOUD_IMAGES_DOWNLOAD_URL=http://cloud-images.ubuntu.com
CLOUD_IMAGES_PAGE=$(curl -skL ${CLOUD_IMAGES_URL})
LTS_LATEST_VERSION=$(echo "${CLOUD_IMAGES_PAGE}" | grep -oP "Server \K(.*) (?=LTS)" | sort -r | head -n 1)
LTS_LATEST_NAME=$(echo "${CLOUD_IMAGES_PAGE}" | grep "${LTS_LATEST_VERSION}" | grep -oP "LTS \(\K([a-zA-Z]*)" | head -n 1 | tr [:upper:] [:lower:])
URL=${CLOUD_IMAGES_DOWNLOAD_URL}/${LTS_LATEST_NAME}/current/${LTS_LATEST_NAME}-server-cloudimg-amd64.img

DEST=/dev/shm/devstack-dev.img
WORKDIR=$(mktemp -d /tmp/devstack.XXXXXXXXX)

echo Install QEMU
rm -rf /etc/apt/sources.list.d
sed -i '/src/d' /etc/apt/sources.list
apt-get update
apt-get -o APT::Install-Recommends=0 -o APT::Install-Suggests=0 -y install qemu-system-x86 qemu-utils genisoimage

echo Get Cloud Image
echo URL: $URL
cd $WORKDIR
rm -rf devstack.img devstack0.img cloudinit.iso user-data meta-data
curl -kL -# -o devstack0.img $URL

qemu-img resize devstack0.img 10G

echo Generate cloudinit.iso
cat << "EOF" > user-data
#cloud-config
disable_ec2_metadata: true

system_info:
  default_user: ~

users:
  - name: stack
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    plain_text_passwd: stack
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDyuzRtZAyeU3VGDKsGk52rd7b/rJ/EnT8Ce2hwWOZWp

apt:
  preserve_sources_list: true

output:
  all: '| tee -a /dev/console'

write_files:
  - content: |
        LABEL=cloudimg-rootfs   /               ext4    defaults,noatime                                     0 0
        LABEL=UEFI              /boot/efi       vfat    defaults,noatime                                     0 0
        tmpfs                   /tmp            tmpfs   rw,mode=1777,strictatime,nosuid,nodev,size=90%       0 0
    path: /etc/fstab
  - content: |
        APT::Authentication "0";
        APT::Get::AllowUnauthenticated "1";
        Dir::Cache "/dev/shm";
        Dir::State::lists "/dev/shm";
        Dir::Log "/dev/shm";
        DPkg::Post-Invoke {"/bin/rm -f /dev/shm/archives/*.deb || true";};
    path: /etc/apt/apt.conf.d/90-freedisk
  - content: |
        APT::Install-Recommends "0";
        APT::Install-Suggests "0";
    path: /etc/apt/apt.conf.d/99norecommend
  - content: |
        path-exclude *__pycache__*
        path-exclude *.py[co]
        path-exclude /usr/share/doc/*
        path-exclude /usr/share/man/*
        path-exclude /usr/share/bug/*
        path-exclude /usr/share/groff/*
        path-exclude /usr/share/info/*
        path-exclude /lib/modules/*/sound*
    path: /etc/dpkg/dpkg.cfg.d/99nofiles
  - content: |
        [Match]
        Name=en*

        [Network]
        DHCP=ipv4
    path: /etc/systemd/network/20-dhcp.network
  - content: |
        [Match]
        Name=br-ex

        [Network]
        Address=172.24.4.1/24
    path: /etc/systemd/network/30-br-ex.network
  - content: |
        network: {config: disabled}
    path: /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
  - content: |
        export PYTHONDONTWRITEBYTECODE=1 PYTHONSTARTUP=/usr/lib/pythonstartup
    path: /etc/profile.d/python.sh
  - content: |
        #!/bin/sh
        echo 'PYTHONDONTWRITEBYTECODE=1'
        echo 'PYTHONSTARTUP=/usr/lib/pythonstartup'
    path: /etc/systemd/system-environment-generators/20-python
    permissions: 0755
  - content: |
        import readline
        import time

        readline.add_history("# " + time.asctime())
        readline.set_history_length(-1)
    path: /usr/lib/pythonstartup
    permissions: 0755
  - content: |
        GRUB_CMDLINE_LINUX_DEFAULT="\$GRUB_CMDLINE_LINUX_DEFAULT intel_iommu=on"
    path: /etc/default/grub.d/90-intel_iommu.cfg
  - content: |
        [global]
        download-cache=/tmp
        cache-dir=/tmp
    path: /etc/pip.conf
  - content: |
        [Manager]
        DefaultTimeoutStartSec=20min
        DefaultTimeoutStopSec=20min
    path: /etc/systemd/system.conf.d/timeout.conf
  - content: |
        syntax on
        filetype on
        set nu
        set history=0
        set autoread
        set backupdir=/dev/shm//
        set directory=/dev/shm//
        set undodir=/dev/shm//
        set nobackup
        set nowritebackup
        set cursorline
        highlight CursorLine   cterm=NONE ctermbg=darkred ctermfg=white guibg=darkred guifg=white
        highlight CursorColumn cterm=NONE ctermbg=darkred ctermfg=white guibg=darkred guifg=white
        set showmatch
        set ignorecase
        set hlsearch
        set incsearch
        set tabstop=4
        set softtabstop=4
        set shiftwidth=4
        set nowrap
        set viminfo=""
    owner: stack:stack
    path: /home/stack/.vimrc
  - content: |
         [Journal]
         Storage=volatile
    path: /etc/systemd/journald.conf.d/storage.conf
  - content: |
         [Service]
         TimeoutSec=600
         PIDFile=
    path: /etc/systemd/system/pmlogger.service.d/opt.conf
  - content: |
         export HISTSIZE=1000 LESSHISTFILE=/dev/null HISTFILE=/dev/null PYTHONWARNINGS=ignore
         alias osadmin='openstack --os-cloud=devstack-admin --os-region-name=RegionOne'
    owner: stack:stack
    path: /home/stack/.bash.conf
  - content: |
         [Unit]
         Description = Devstack loop and mount be ready
         After=local-fs.target
         Before=devstack@c-vol.service devstack@s-account.service devstack@s-container.service devstack@s-object.service devstack@s-proxy.service
         
         [Service]
         Type=oneshot
         ExecStart=/home/stack/loopmount.sh
         RemainAfterExsit=yes
         
         [Install]
         WantedBy = multi-user.target
    path: /etc/systemd/system/devstack@loopmount.service
         
  - content: |
         #!/bin/sh
         
         if ! losetup -a | grep -q /opt/stack/data/stack-volumes
         then
         	for f in $(ls /opt/stack/data/stack-volumes-*-backing-file)
         	do
         		losetup -f --show --direct-io=on $f
         	done
         fi
         
         mount -t xfs -o loop,noatime,nodiratime,logbufs=8  /opt/stack/data/swift/drives/images/swift.img /opt/stack/data/swift/drives/sdb1
         
         exit 0
    path: /home/stack/loopmount.sh
    owner: stack:stack
    permissions: 0755
  - content: |
         #!/bin/sh
         set -x

         # apt remove -y --purge git git-man
         # gv=$(dpkg -l | grep "GNU C compiler" | awk '/gcc-/ {gsub("gcc-","",$2);print $2}')
         # lv=$(dpkg -l | awk '/llvm-/ {gsub("llvm-","",$2);print $2;exit}')
         # dpkg -P --force-depends gcc-$gv libgcc-$gv-dev g++-$gv cpp cpp-$gv iso-codes llvm-$lv
         
         find /usr/*/locale -mindepth 1 -maxdepth 1 ! -name locale-archive -prune -exec rm -rf {} +
         find /usr/share/zoneinfo -mindepth 1 -maxdepth 2 ! -name 'UTC' -a ! -name 'UCT' -a ! -name 'Etc' -a ! -name '*UTC' -a ! -name '*UCT' -a ! -name 'PRC' -a ! -name 'Asia' -a ! -name '*Shanghai' -prune -exec rm -rf {} +
         find /usr /opt -type d -name __pycache__ -prune -exec rm -rf {} +
        
         rm -rf /etc/libvirt/qemu/networks/autostart/default.xml
         rm -rf /root/.cache /home/stack/.cache
         rm -rf /usr/share/doc /usr/local/share/doc /usr/share/man /usr/share/icons /usr/share/fonts /usr/share/X11 /usr/share/AAVMF /usr/share/OVMF /usr/lib/x86_64-linux-gnu/dri /usr/share/misc/pci.ids /usr/share/ieee-data /usr/share/sphinx /usr/share/python-wheels /usr/share/fonts/truetype /usr/lib/udev/hwdb.d /usr/lib/udev/hwdb.bin /usr/include/* /usr/src/*
         rm -rf /var/lib/*/*.sqlite /tmp/* /var/tmp/* /var/cache/apt/* /var/lib/apt/lists/*
         rm -rf /opt/stack/*/*/locale /opt/stack/*/docs /opt/stack/*/*/docs /opt/stack/{devstack.subunit,requirements,logs/*} /opt/stack/*/{releasenotes,playbooks,.git,doc} /opt/stack/data/etcd/member/wal/0.tmp /opt/stack/bin/etcdctl
         rm -rf /usr/bin/systemd-analyze /usr/bin/perl*.* /usr/bin/sqlite3

         rm -rf /home/stack/devstack/files/*

         exit 0
    path: /home/stack/cleanup.sh
    owner: stack:stack
    permissions: 0755
  - content: |
        #!/bin/sh
        DEBIAN_FRONTEND=noninteractive sudo apt-get -qqy update || sudo yum update -qy
        DEBIAN_FRONTEND=noninteractive sudo apt-get install -qqy git || sudo yum install -qy git
        sudo chown stack:stack /home/stack
        cd /home/stack
        git config --global http.sslverify false
        git config --global https.sslverify false
        git clone --depth=1 https://opendev.org/openstack/devstack
        cd devstack
        sed -i 's/qemu-system/qemu-system-x86/' lib/nova_plugins/functions-libvirt
        sed -i 's/sleep 1/sleep 300/' lib/neutron_plugins/ovn_agent
        echo '[[local|localrc]]' > local.conf
        echo ADMIN_PASSWORD=devstack >> local.conf
        echo DATABASE_PASSWORD=devstack >> local.conf
        echo RABBIT_PASSWORD=devstack >> local.conf
        echo SERVICE_PASSWORD=devstack >> local.conf
        echo PIP_UPGRADE=True >> local.conf
        echo USE_PYTHON3=True >> local.conf
        echo ENABLE_IDENTITY_V2=False >> local.conf
        echo SERVICE_IP_VERSION=4 >> local.conf
        echo HOST_IP=10.0.2.15 >> local.conf
        echo LIBVIRT_TYPE=kvm >> local.conf
        echo API_WORKERS=1 >> local.conf
        echo GIT_DEPTH=1 >> local.conf
        echo VOLUME_BACKING_FILE_SIZE=1T >> local.conf
        echo SERVICE_TIMEOUT=600 >> local.conf
        echo DOWNLOAD_DEFAULT_IMAGES=True >> local.conf
        echo NEUTRON_CREATE_INITIAL_NETWORKS=True >> local.conf
        echo VERBOSE=True >> local.conf
        echo SYSLOG=True >> local.conf
        echo ENABLE_DEBUG_LOG_LEVEL=True >> local.conf
        echo DEBUG_LIBVIRT=True >> local.conf
        # disable services
        echo disable_service tempest >> local.conf
        echo disable_service mysql >> local.conf
        echo enable_service postgresql >> local.conf
        # more services
        echo enable_service n-novnc n-spice n-sproxy >> local.conf
        echo enable_service s-proxy s-object s-container s-account >> local.conf
        echo SWIFT_HASH=d90042a57d537bd2ce9ed43535fc90ac >> local.conf
        echo SWIFT_REPLICAS=1 >> local.conf
        echo SWIFT_LOOPBACK_DISK_SIZE=1T >> local.conf
        # other services
        echo enable_plugin neutron-vpnaas https://opendev.org/openstack/neutron-vpnaas >> local.conf
        echo enable_plugin barbican https://opendev.org/openstack/barbican >> local.conf
        echo enable_plugin manila https://opendev.org/openstack/manila >> local.conf
        echo enable_plugin manila-ui https://opendev.org/openstack/manila-ui >> local.conf
        echo MANILA_SERVICE_IMAGE_ENABLED=False >> local.conf
        echo enable_plugin designate https://opendev.org/openstack/designate >> local.conf
        echo enable_plugin freezer https://opendev.org/openstack/freezer >> local.conf
        echo enable_plugin freezer-api https://opendev.org/openstack/freezer-api >> local.conf
        echo enable_plugin freezer-web-ui https://opendev.org/openstack/freezer-web-ui >> local.conf
        echo FREEZER_BACKEND='sqlalchemy' >> local.conf
        ./stack.sh
    path: /home/stack/start.sh
    owner: stack:stack
    permissions: 0755

bootcmd:
  - groupadd kvm
  - useradd -m -s /bin/bash -G kvm,adm,systemd-journal stack
  - echo 'source ~/devstack/openrc admin admin' >> /home/stack/.bashrc
  - echo 'Defaults env_keep+="PYTHONDONTWRITEBYTECODE"' > /etc/sudoers.d/env_keep
  - chmod 440 /etc/sudoers.d/env_keep

runcmd:
  - su -l stack ./start.sh
  - sed -i 's/virt_type = qemu/virt_type = kvm/' /etc/nova/nova.conf
  - touch /etc/cloud/cloud-init.disabled
  - systemctl -f mask apt-daily.timer apt-daily-upgrade.timer e2scrub_all.timer fstrim.timer fwupd-refresh.timer logrotate.timer man-db.timer motd-news.timer unattended-upgrades.service
  - systemctl enable devstack@loopmount.service
  - bash /home/stack/cleanup.sh

power_state:
 mode: poweroff
 timeout: 5
EOF

cat > meta-data <<EOF
local-hostname: devstack
EOF

echo Genisoimage cloudinit.iso
genisoimage -quiet -output cloudinit.iso -volid cidata -joliet -rock user-data meta-data &>/dev/null

echo Building ...
qemu-system-x86_64 -machine q35,accel=kvm:hax:hvf:whpx:tcg -cpu kvm64 -smp "$(nproc)" -m 24G -boot c -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0 -drive file=devstack0.img,if=virtio,format=qcow2,media=disk -drive file=cloudinit.iso,if=virtio,media=cdrom -netdev user,id=n0,ipv6=off -device virtio-net,netdev=n0 -nographic

echo Original image size:
du -h devstack0.img

echo Converting ...
qemu-img convert -f qcow2 -c -O qcow2 devstack0.img $DEST

echo Compressed image size:
du -h $DEST
