#!/usr/bin/env bash

# Parameters
VM_CT_ID="$1"
PROXMOX_HOST="$2"
USER="$3"
SSH_PRIVATE_KEY="${4:-id_rsa}"

# Vars
messages=()

# Functions
echo_message() {
  local message="$1"
  local error="$2"
  local componentname="update-adguard"
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")

  echo '{
      "timestamp": "'"$timestamp"'",
      "componentName": "'"$componentname"'",
      "message": "'"$message"'",
      "error": '$error'
  }'
}

end_script() {
  local status="$1"

  for ((i = 0; i < ${#messages[@]}; i++)); do
    echo "${messages[i]}"
    echo ","
  done

  exit $status
}

execute_script_on_container() {
  local script_content="$1"

  pct_exec_output=$(ssh -i "$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$USER"@"$PROXMOX_HOST" "pct exec $VM_CT_ID -- bash -c 'bash -s' --" <<<"$script_content" 2>&1)
  if [[ $? -eq 0 ]]; then
    messages+=("$(echo_message "Script execution completed." false)")
  else
    messages+=("$(echo_message "Script execution failed." true)")
  fi
  messages+=("$(echo_message "$pct_exec_output" false)")
}

update() {
  if [[ ! -d /opt/AdGuardHome ]]; then
    messages+=("$(echo_message "No Adguard Installation Found!" true)")
    end_script 1
  fi

  wget -qL https://static.adguard.com/adguardhome/release/AdGuardHome_linux_amd64.tar.gz
  messages+=("$(echo_message "Stopping AdguardHome" false)")
  systemctl stop AdGuardHome

  messages+=("$(echo_message "Stopped AdguardHome" false)")

  messages+=("$(echo_message "Updating AdguardHome" false)")
  tar -xvf AdGuardHome_linux_amd64.tar.gz &>/dev/null
  mkdir -p adguard-backup
  cp -r /opt/AdGuardHome/AdGuardHome.yaml /opt/AdGuardHome/data adguard-backup/
  cp AdGuardHome/AdGuardHome /opt/AdGuardHome/AdGuardHome
  cp -r adguard-backup/* /opt/AdGuardHome/

  messages+=("$(echo_message "Updated AdguardHome" false)")

  messages+=("$(echo_message "Starting AdguardHome" false)")
  systemctl start AdGuardHome

  messages+=("$(echo_message "Started AdguardHome" false)")

  messages+=("$(echo_message "Cleaning Up" false)")
  rm -rf AdGuardHome_linux_amd64.tar.gz AdGuardHome adguard-backup

  messages+=("$(echo_message "Cleaned" false)")
  messages+=("$(echo_message "Updated Successfully" false)")
}

# Run
script_content=$(declare -f echo_message)
script_content+="\n"
script_content+=$(declare -f end_script)
script_content+="\n"
script_content+=$(declare -f update)
script_content+="\n"
script_content+="update"

messages+=("$(echo_message "$script_content" false)")
execute_script_on_container "$script_content"
