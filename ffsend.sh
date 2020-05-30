#!/bin/bash
set -e

ffsend_ver="$(curl -skL https://api.github.com/repos/timvisee/ffsend/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')"
curl -skL -o /tmp/ffsend https://github.com/timvisee/ffsend/releases/download/"$ffsend_ver"/ffsend-"$ffsend_ver"-linux-x64-static
chmod +x /tmp/ffsend

cd /dev/shm
split -d -b 800M devstack.img devstack.img.

FFSEND_URL=$(/tmp/ffsend -Ifyq upload /dev/shm/devstack.img.*)

echo $FFSEND_URL

#echo $data
#data+=${data/\#/%23}
#curl -skL "http://wxpusher.zjiecode.com/api/send/message/?appToken=$WXPUSHER_APPTOKEN&uid=$WXPUSHER_UID&content=$data" >/dev/null &2>1
