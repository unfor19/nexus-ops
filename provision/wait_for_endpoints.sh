#!/bin/bash
set -e
set -o pipefail

error_msg(){
  local msg="$1"
  echo -e "[ERROR] $(date) :: $msg"
  exit 1
}

log_msg(){
  local msg="$1"
  echo -e "[LOG] $(date) :: $msg"
}

wait_for_endpoints(){
    declare endpoints=($@)
    for endpoint in "${endpoints[@]}"; do
        counter=1
        while [[ $(curl -s -o /dev/null -w ''%{http_code}'' "$endpoint") != "200" ]]; do 
            counter=$((counter+1))
            log_msg "Waiting for - ${endpoint}"
            if [[ $counter -gt 60 ]]; then
                error_msg "Not healthy - ${endpoint}"
            fi
            sleep 3
        done
        log_msg "Healthy endpoint - ${endpoint}"
    done    
}

wait_for_endpoints $@
