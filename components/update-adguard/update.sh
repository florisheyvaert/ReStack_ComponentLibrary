#!/usr/bin/env bash

## Vars
APP="Nginx Proxy Manager"
YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"
BFR="\\r\\033[K"
HOLD="-"

## Functions 
catch_errors() {
  set -Eeuo pipefail
  trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
}

msg_info() {
  local msg="$1"
  echo -ne " ${HOLD} ${YW}${msg}..."
}

msg_ok() {
  local msg="$1"
  echo -e "${BFR} ${CM} ${GN}${msg}${CL}"
}

msg_error() {
  local msg="$1"
  echo -e "${BFR} ${CROSS} ${RD}${msg}${CL}"
}

function update() {
if [[ ! -d /opt/AdGuardHome ]]; then msg_error "No ${APP} Installation Found!"; exit; fi
wget -qL https://static.adguard.com/adguardhome/release/AdGuardHome_linux_amd64.tar.gz
msg_info "Stopping AdguardHome"
systemctl stop AdGuardHome
msg_ok "Stopped AdguardHome"

msg_info "Updating AdguardHome"
tar -xvf AdGuardHome_linux_amd64.tar.gz &>/dev/null
mkdir -p adguard-backup
cp -r /opt/AdGuardHome/AdGuardHome.yaml /opt/AdGuardHome/data adguard-backup/
cp AdGuardHome/AdGuardHome /opt/AdGuardHome/AdGuardHome
cp -r adguard-backup/* /opt/AdGuardHome/
msg_ok "Updated AdguardHome"

msg_info "Starting AdguardHome"
systemctl start AdGuardHome
msg_ok "Started AdguardHome"

msg_info "Cleaning Up"
rm -rf AdGuardHome_linux_amd64.tar.gz AdGuardHome adguard-backup
msg_ok "Cleaned"
msg_ok "Updated Successfully"
exit
}


## Run
catch_errors
update