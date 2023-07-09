#!/usr/bin/env bash

# Parameters
VM_CT_ID="$1"          
PROXMOX_HOST="$2"  
USER="$3"
SSH_PRIVATE_KEY="${4:-id_rsa}"

## Vars
messages=()

## Functions
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

  for ((i=0; i<${#messages[@]}; i++)); do
    echo "${messages[i]}"
    echo ","
  done

  exit $status
}

execute_script_on_container() {
  local script_content="$1"

  pct_exec_output=$(ssh -i "$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$USER"@"$PROXMOX_HOST" "pct exec $VM_CT_ID -- bash -c 'echo \"$script_content\" | 2>&1")
      messages+=("$(echo_message "$pct_exec_output" false)")
  if echo "$pct_exec_output" | grep -iq "error"; then
      messages+=("$(echo_message "Error in script execution on container. Error: $pct_exec_output" true)")
      end_script 1
  else
      messages+=("$(echo_message "Update script successfully executed on container." false)")
      end_script 0
  fi
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

## Run
script_content=$(cat <<EOF
$(declare -f echo_message)
$(declare -f end_script)
$(declare -f update)
update
EOF
)

execute_script_on_container "$VM_CT_ID" "$script_content"
