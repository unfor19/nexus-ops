#!/bin/bash

# trap ctrl-c and call ctrl_c()
trap ctrl_c INT
ctrl_c() {
    exit 0
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
    _NEXUS_OPS_VERBOSE="${_NEXUS_OPS_VERBOSE:-"false"}"
    _NEXUS_BASE_URL="http://localhost:8081"
    _NEXUS_BASE_API_PATH="service/rest/v1"
    _NEXUS_URL="${_NEXUS_BASE_URL}/${_NEXUS_BASE_API_PATH}"
    _NEXUS_DATA_PATH="/nexus-data"
    _NEXUS_OPS_PATH="${_NEXUS_DATA_PATH}/nexus-ops"
}


# Wait for Nexus to be healthy
wait_for_healthy_response(){
    "${_NEXUS_OPS_PATH}"/wait_for_endpoints.sh "${_NEXUS_URL}/status/writable"
    log_msg "Nexus API is ready to receive requests"
}


# Credentials
set_credentials(){
    _ADMIN_USERNAME="admin"
    if [[ -f "${_NEXUS_DATA_PATH}"/admin.password ]]; then
        _INITIAL_PASSWORD="$(head -n 1 "${_NEXUS_DATA_PATH}"/admin.password)"
    fi
    _ADMIN_PASSWORD="${ADMIN_PASSWORD:-"admin"}"
    _CREDENTIALS="${_ADMIN_USERNAME}:${_ADMIN_PASSWORD}"


    if [[ "$_NEXUS_OPS_VERBOSE" = "true" ]]; then
        _CURL_VERBOSE="-v"
    fi
}


change_initial_password(){
    log_msg "Initial password = ${_INITIAL_PASSWORD}"
    if [[ -n "${_INITIAL_PASSWORD}" ]]; then
        curl $_CURL_VERBOSE -u "${_ADMIN_USERNAME}:${_INITIAL_PASSWORD}" -X PUT "${_NEXUS_URL}/security/users/admin/change-password" -H "Content-Type: text/plain" -d "$_ADMIN_PASSWORD"
    else
        log_msg "admin password was set"
    fi
}


enable_anonymous_access(){
    log_msg "Enabling anonymous access to ${_NEXUS_URL}"
    curl $_CURL_VERBOSE -u "$_CREDENTIALS" -X PUT "${_NEXUS_URL}/security/anonymous"         -H "accept: application/json" -H "Content-Type: application/json" -d "{ \"enabled\": true, \"userId\": \"anonymous\", \"realmName\": \"NexusAuthorizingRealm\"}"
    log_msg "Successfully enabled anonymous access to ${_NEXUS_URL}"
}


realms_enable_docker_token(){
    log_msg "Adding DockerToken to Realms"
    curl $_CURL_VERBOSE -u "$_CREDENTIALS" -X PUT "${_NEXUS_URL}/security/realms/active"     -H "accept: application/json" -H "Content-Type: application/json" -d "[ \"NexusAuthenticatingRealm\", \"NexusAuthorizingRealm\", \"DockerToken\"]"
    log_msg "Successfully added DockerToken to Realms"
}


repositories_create_dockerhub_proxy(){
    log_msg "Creating the docker-proxy repository docker-hub"
    curl $_CURL_VERBOSE -u "$_CREDENTIALS" -X POST "${_NEXUS_URL}/repositories/docker/proxy" -H "accept: application/json" -H "Content-Type: application/json" -d "@${_NEXUS_OPS_PATH}/repositories/docker-proxy-dockerhub.json"
    log_msg "Successfully created the docker-proxy repository docker-hub"
}


repositories_create_ecrpublic_proxy(){
    log_msg "Creating the docker-proxy repository docker-ecrpublic"
    curl $_CURL_VERBOSE -u "$_CREDENTIALS" -X POST "${_NEXUS_URL}/repositories/docker/proxy" -H "accept: application/json" -H "Content-Type: application/json" -d "@${_NEXUS_OPS_PATH}/repositories/docker-proxy-ecrpublic.json"
    log_msg "Successfully created the docker-proxy repository docker-ecrpublic"
}


repositories_create_docker_group(){
    log_msg "Creating the docker-group repository docker-group"
    curl $_CURL_VERBOSE -u "$_CREDENTIALS" -X POST "${_NEXUS_URL}/repositories/docker/group" -H "accept: application/json" -H "Content-Type: application/json" -d "@${_NEXUS_OPS_PATH}/repositories/docker-group.json"
    log_msg "Successfully created the docker-group repository docker-group"
}


main(){
    start_nexus
    set_global_variables
    wait_for_healthy_response
    set_credentials
    change_initial_password
    enable_anonymous_access
    realms_enable_docker_token
    repositories_create_dockerhub_proxy
    repositories_create_ecrpublic_proxy
    repositories_create_docker_group
}

# Run
main

# Keeps Nexus running in the background
wait
