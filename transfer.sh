#!/bin/bash
set -ex

ver="$(curl -skL https://api.github.com/repos/Mikubill/transfer/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')"
curl -skL https://github.com/Mikubill/transfer/releases/download/"$ver"/transfer_"${ver/v/}"_linux_amd64.tar.gz | tar -xz -C /tmp

f=/dev/shm/devstack.img
FILENAME=$(basename $f)
SIZE=$(du -h $f | awk '{print $1}')
cow_data=$(/tmp/transfer cow $f)
cow_url=$(echo ${cow_data} | cut -d ' ' -f5)
[[ ! -z "$cow_url" ]] && exit 1
data="$FILENAME-$SIZE-${cow_url}"
curl -skLo /dev/null "https://wxpusher.zjiecode.com/api/send/message/?appToken=${WXPUSHER_APPTOKEN}&uid=${WXPUSHER_UID}&content=${data}"
