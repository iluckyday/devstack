#!/bin/bash

DEVSTACK_BRANCH=master

CLOUD_IMAGES_URL=http://cloud-images.ubuntu.com
CLOUD_IMAGES_PAGE=$(curl -skL ${CLOUD_IMAGES_URL})
LTS_LATEST_VERSION=$(echo ${CLOUD_IMAGES_PAGE} | grep -oP "Server \K(.*) (?=LTS)" | sort -r | head -n 1)
LTS_LATEST_NAME=$(echo ${CLOUD_IMAGES_PAGE} | grep "${LTS_LATEST_VERSION}" | grep -oP "LTS \(\K([a-zA-Z]*)" | tr [:upper:] [:lower:])
URL=${CLOUD_IMAGES_URL}/${LTS_LATEST_NAME}/current/${LTS_LATEST_NAME}-server-cloudimg-amd64.img

DEST=/dev/shm/devstack-vm.img
WORKDIR=$(mktemp -d /tmp/devstack.XXXXXXXXX)

echo Install QEMU
rm -rf /etc/apt/sources.list.d
sed -i '/src/d' /etc/apt/sources.list
apt-get update
apt-get -o APT::Install-Recommends=0 -o APT::Install-Suggests=0 -y install qemu-system-x86 genisoimage

echo Get Cloud Image
echo URL: $URL
cd $WORKDIR
rm -rf devstack.img devstack0.img cloudinit.iso user-data meta-data
curl -kL -# -o devstack0.img $URL

qemu-img resize devstack0.img 200G

echo Generate cloudinit.iso
cat << EOF > user-data
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

timezone: Asia/Chongqing

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
	mode: 0755
  - content: |
        import readline
        import time

        readline.add_history("# " + time.asctime())
        readline.set_history_length(-1)
    path: /usr/lib/pythonstartup
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
         export HISTSIZE=1000 LESSHISTFILE=/dev/null HISTFILE=/dev/null PYTHONWARNINGS=ignore
    owner: stack:stack
    path: /home/stack/.bash.conf
  - content: |
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
    owner: stack:stack
    path: /home/stack/.adminrc
  - content: |
        #!/bin/sh
        DEBIAN_FRONTEND=noninteractive sudo apt-get -qqy update || sudo yum update -qy
        DEBIAN_FRONTEND=noninteractive sudo apt-get install -qqy git || sudo yum install -qy git
        sudo chown stack:stack /home/stack
        cd /home/stack
        git clone --depth=1 https://opendev.org/openstack/devstack
        cd devstack
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
        ./stack.sh
    path: /home/stack/start.sh
    permissions: 0755

bootcmd:
 - groupadd kvm
 - useradd -m -s /bin/bash -G kvm stack
 - touch /home/stack/.hushlogin
 - echo source .bash.conf >> /home/stack/.bashrc
 - echo source .adminrc >> /home/stack/.bashrc

runcmd:
  - touch /etc/cloud/cloud-init.disabled
  - grub-mkconfig -o /boot/grub/grub.cfg
  - systemctl -f mask apt-daily.timer apt-daily-upgrade.timer fstrim.timer motd-news.timer unattended-upgrades.service
  - su -l stack ./start.sh
  - rm -rf /var/lib/apt/lists /var/cache/apt /tmp/*
  - find /usr /opt -type d -name __pycache__ -prune -exec rm -rf {} +
  - rm -rf /home/stack/devstack

power_state:
 mode: poweroff
 timeout: 5
EOF

cat > meta-data <<EOF
local-hostname: devstack
EOF

genisoimage -quiet -output cloudinit.iso -volid cidata -joliet -rock user-data meta-data &>/dev/null

echo Building ...
qemu-system-x86_64 -machine q35,accel=kvm:hax:hvf:whpx:tcg -cpu kvm64 -smp "$(nproc)" -m 4G -boot c -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0 -drive file=devstack0.img,if=virtio,format=qcow2,media=disk -drive file=cloudinit.iso,if=virtio,media=cdrom -netdev user,id=n0,ipv6=off -device virtio-net,netdev=n0 -display none

echo Original image size:
du -h devstack0.img

echo Converting ...
qemu-img convert -f qcow2 -c -O qcow2 devstack0.img $DEST

echo Compressed image size:
du -h $DEST

#echo Clean ...
#cd $HOME
#rm -rf WORKDIR
