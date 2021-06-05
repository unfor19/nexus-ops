#!/bin/bash

# trap ctrl-c and call ctrl_c()
trap ctrl_c INT
ctrl_c() {
    exit 0
}


error_msg(){
  local msg="$1"
  echo -e "[ERROR] $(date) :: $msg"
  exit 1
}


log_msg(){
  local msg="$1"
  echo -e "[LOG] $(date) :: $msg"
}


# Start Nexus
start_nexus(){
    /opt/sonatype/start-nexus-repository-manager.sh &
}


# Set Global Variables
set_global_variables(){
    _NEXUS_OPS_VERBOSE="${NEXUS_OPS_VERBOSE:-"false"}"
    _NEXUS_BASE_URL="${NEXUS_BASE_URL:-"http://localhost:8081"}"
    _NEXUS_BASE_API_PATH="${NEXUS_BASE_API_PATH:-"service/rest/v1"}"
    _NEXUS_URL="${NEXUS_URL:-"${_NEXUS_BASE_URL}/${_NEXUS_BASE_API_PATH}"}"
    _NEXUS_DATA_PATH="${NEXUS_DATA_PATH:-"/nexus-data"}"
    _NEXUS_OPS_PATH="${NEXUS_OPS_PATH:-"${_NEXUS_DATA_PATH}/nexus-ops"}"
}


# Wait for Nexus to be healthy
wait_for_healthy_response(){
    "${_NEXUS_OPS_PATH}"/wait_for_endpoints.sh "${_NEXUS_URL}/status/writable"
    log_msg "Nexus API is ready to receive requests"
}


# Credentials
set_credentials(){
    _ADMIN_USERNAME="admin"
    _INITIAL_PASSWORD=""
    if [[ -f "${_NEXUS_DATA_PATH}"/admin.password ]]; then
        _INITIAL_PASSWORD="$(head -n 1 "${_NEXUS_DATA_PATH}"/admin.password)"
    fi
    _ADMIN_PASSWORD="${ADMIN_PASSWORD:-"admin"}"
    _CREDENTIALS="${_ADMIN_USERNAME}:${_ADMIN_PASSWORD}"

    if [[ "$_NEXUS_OPS_VERBOSE" = "true" ]]; then
        _CURL_VERBOSE="-v"
    fi
}


repositories_get_docker_repository(){
    local repository_type="$1"
    local repository_name="$2"
    local endpoint="${_NEXUS_URL}/repositories/docker/${repository_type}/${repository_name}"
    local response
    response="$(curl -u "$_CREDENTIALS" -s -o /dev/null -X GET -w ''%{http_code}'' "$endpoint" -H "accept: application/json")"
    if [[ "$response" = "200" ]] ; then
        echo "true"
    else
        echo "$response"
    fi
}


change_initial_password(){
    if [[ -n "${_INITIAL_PASSWORD}" ]]; then
        log_msg "Initial password = ${_INITIAL_PASSWORD}"
        curl $_CURL_VERBOSE -u "${_ADMIN_USERNAME}:${_INITIAL_PASSWORD}" -X PUT "${_NEXUS_URL}/security/users/admin/change-password" -H "Content-Type: text/plain" -d "$_ADMIN_PASSWORD"
    else
        log_msg "Password was set"
    fi
}


enable_anonymous_access(){
    if [[ "${_INITIAL_PASSWORD}" != "" ]]; then
        log_msg "Enabling anonymous access to ${_NEXUS_URL}"
        curl $_CURL_VERBOSE -u "$_CREDENTIALS" -X PUT "${_NEXUS_URL}/security/anonymous"         -H "accept: application/json" -H "Content-Type: application/json" -d "{ \"enabled\": true, \"userId\": \"anonymous\", \"realmName\": \"NexusAuthorizingRealm\"}"
        log_msg "Successfully enabled anonymous access to ${_NEXUS_URL}"
    fi
}


realms_enable_docker_token(){
    if [[ "${_INITIAL_PASSWORD}" != "" ]]; then
        log_msg "Adding DockerToken to Realms"
        curl $_CURL_VERBOSE -u "$_CREDENTIALS" -X PUT "${_NEXUS_URL}/security/realms/active"     -H "accept: application/json" -H "Content-Type: application/json" -d "[ \"NexusAuthenticatingRealm\", \"NexusAuthorizingRealm\", \"DockerToken\"]"
        log_msg "Successfully added DockerToken to Realms"
    fi
}


repositories_create_repository(){
    local repository_type="$1"
    local repository_name="$2"
    local json_path="$3"
    curl $_CURL_VERBOSE -u "$_CREDENTIALS" -X POST "${_NEXUS_URL}/repositories/docker/${repository_type}" -H "accept: application/json" -H "Content-Type: application/json" -d "@${json_path}"
}


repositories_create_repository_wrapper(){
    local repository_type="$1"
    local repository_name="$2"
    local json_path="$3"
    repo_exists=$(repositories_get_docker_repository "$repository_type" "$repository_name")
    if [[ "$repo_exists" = "true" ]]; then
        log_msg "Repository exists - $repository_type $repository_name"
    elif [[ "$repo_exists" = "404" ]]; then
        log_msg "$repo_exists - $repository_type $repository_name, creating it ..."
        repositories_create_repository "$repository_type" "$repository_name" "$json_path"
    elif [[ "$repo_exists" = "403" ]]; then
        log_msg "Authorization error - 403"
    elif [[ "$repo_exists" = "401" ]]; then
        log_msg "Authentication error - 401"
    else
        log_msg "Unknown error - $repo_exists"
    fi
}


main(){
    start_nexus
    set_global_variables
    wait_for_healthy_response
    set_credentials
    change_initial_password
    enable_anonymous_access
    realms_enable_docker_token
    repositories_create_repository_wrapper "proxy" "docker-hub" "${_NEXUS_OPS_PATH}/repositories/docker-proxy-dockerhub.json"
    repositories_create_repository_wrapper "proxy" "docker-ecrpublic" "${_NEXUS_OPS_PATH}/repositories/docker-proxy-ecrpublic.json"
    repositories_create_repository_wrapper "group" "docker-group" "${_NEXUS_OPS_PATH}/repositories/docker-group.json"
    log_msg "Finished executing - ${_NEXUS_OPS_PATH}/entrypoint.sh"
}

# Run
main

# Keeps Nexus running in the background
wait
