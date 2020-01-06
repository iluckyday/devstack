#!/bin/bash

ffsend_ver="$(curl -skL https://api.github.com/repos/timvisee/ffsend/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')"
curl -skL -o /bin/ffsend https://github.com/timvisee/ffsend/releases/download/"$ffsend_ver"/ffsend-"$ffsend_ver"-linux-x64-static
chmod +x /bin/ffsend

FFSEND_URL=$(ffsend -Ifyq --verbose upload $1)
curl -skL "http://wxpusher.zjiecode.com/api/send/message/?appToken=$WXPUSHER_APPTOKEN&uid=$WXPUSHER_UID&content=$FFSEND_URL"
