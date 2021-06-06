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


wait_for_endpoints $@
