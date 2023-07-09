#!/usr/bin/env bash

# Parameters
VM_CT_ID="$1"          
PROXMOX_HOST="$2"  
USER="$3"
SSH_PRIVATE_KEY="${4:-id_rsa}"

## Vars
messages=()

## Functions
# catch_errors() {
#   set -Eeuo pipefail
#   trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
# }

echo_message() {
  local message="$1"
  local error="$2"
  local componentname="update-debian"
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

if [[ $VM_CT_ID == "0" || $VM_CT_ID -eq 0 ]]; then
  update_output=$(ssh -i "$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$USER"@"$PROXMOX_HOST" "apt-get update 2>&1")
  update_output+=$(ssh -i "$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$USER"@"$PROXMOX_HOST" "apt-get upgrade -y 2>&1")
else
  update_output=$(ssh -i "$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=no "$USER"@"$PROXMOX_HOST" "pct exec $VM_CT_ID -- bash -c 'echo \"$script_content\" | bash' 2>&1")
fi


  if echo "$pct_exec_output" | grep -iq "error"; then
      messages+=("$(echo_message "Error in script execution on container. Error: $pct_exec_output" true)")
      end_script 1
  else
      messages+=("$(echo_message "Update script successfully executed on container." false)")
      end_script 0
  fi
}

update() {

  messages+=("$(echo_message "Updated Successfully" false)")

  end_script 0
}

## Run
#catch_errors

script_content=$(cat <<EOF
$(declare -f catch_errors)
$(declare -f echo_message)
$(declare -f end_script)
$(declare -f update)
catch_errors
update
EOF
)

execute_script_on_container "$VM_CT_ID" "$script_content"

