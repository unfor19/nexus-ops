#!/bin/bash

# trap ctrl-c and call ctrl_c()
trap ctrl_c INT
ctrl_c() {
    exit 0
}


# Helper Functions
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
            log_msg "WAIT FOR ENDPOINTS :: Waiting for - ${endpoint}"
            if [[ $counter -gt 60 ]]; then
                error_msg "WAIT FOR ENDPOINTS :: Not healthy - ${endpoint}"
            fi
            sleep 3
        done
        log_msg "WAIT FOR ENDPOINTS :: Healthy endpoint - ${endpoint}"
    done    
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
    wait_for_endpoints "${_NEXUS_URL}/status/writable"
    log_msg "WAIT FOR HEALTHY RESPONSE :: Nexus API is ready to receive requests"
}


# Credentials
set_credentials(){
    _NEXUS_ADMIN_USERNAME="${NEXUS_ADMIN_USERNAME:-"admin"}"
    _INITIAL_PASSWORD=""
    if [[ -f "${_NEXUS_DATA_PATH}"/admin.password ]]; then
        _INITIAL_PASSWORD="$(head -n 1 "${_NEXUS_DATA_PATH}"/admin.password)"
    fi
    _NEXUS_ADMIN_PASSWORD="${NEXUS_ADMIN_PASSWORD:-"admin"}"
    _CREDENTIALS="${_NEXUS_ADMIN_USERNAME}:${_NEXUS_ADMIN_PASSWORD}"

    if [[ "$_NEXUS_OPS_VERBOSE" = "true" ]]; then
        _CURL_VERBOSE="-v"
    fi
}


### --------------------------------------------------
### Functions ----------------------------------------
### --------------------------------------------------
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
        log_msg "CHANGE INITIAL PASSWORD :: Changing ..."
        if curl $_CURL_VERBOSE -u "${_NEXUS_ADMIN_USERNAME}:${_INITIAL_PASSWORD}" -X PUT "${_NEXUS_URL}/security/users/admin/change-password" -H "Content-Type: text/plain" -d "$_NEXUS_ADMIN_PASSWORD" ; then
            log_msg "CHANGE INITIAL PASSWORD :: Successfully changed initial admin password"
        else
            error_msg "CHANGE INITIAL PASSWORD :: Failed to set initial password"
        fi
    else
        log_msg "CHANGE INITIAL PASSWORD :: Admin password was set"
    fi
}


enable_anonymous_access(){
    if [[ "${_INITIAL_PASSWORD}" != "" ]]; then
        log_msg "ENABLE ANONYMOUS ACCESS :: Enabling anonymous access to ${_NEXUS_URL} ..."
        if curl $_CURL_VERBOSE -u "$_CREDENTIALS" -X PUT "${_NEXUS_URL}/security/anonymous"         -H "accept: application/json" -H "Content-Type: application/json" -d "{ \"enabled\": true, \"userId\": \"anonymous\", \"realmName\": \"NexusAuthorizingRealm\"}"; then
            log_msg "ENABLE ANONYMOUS ACCESS :: Successfully enabled anonymous access to ${_NEXUS_URL}"
        else
            error_msg "ENABLE ANONYMOUS ACCESS :: Failed to enable anonymous access to ${_NEXUS_URL}"
        fi
    fi
}


realms_enable_docker_token(){
    if [[ "${_INITIAL_PASSWORD}" != "" ]]; then
        log_msg "REALMS ENABLE DOCKER TOKEN :: Adding DockerToken to Realms ..."
        if curl $_CURL_VERBOSE -u "$_CREDENTIALS" -X PUT "${_NEXUS_URL}/security/realms/active"     -H "accept: application/json" -H "Content-Type: application/json" -d "[ \"NexusAuthenticatingRealm\", \"NexusAuthorizingRealm\", \"DockerToken\"]"; then
            log_msg "REALMS ENABLE DOCKER TOKEN :: Successfully added DockerToken to Realms"
        else
            error_msg "REALMS ENABLE DOCKER TOKEN :: Failed to added DockerToken to Realms"
        fi
    fi
}


repositories_create_repository(){
    local repository_type="$1"
    local repository_name="$2"
    local json_path="$3"
    if curl $_CURL_VERBOSE -u "$_CREDENTIALS" -X POST "${_NEXUS_URL}/repositories/docker/${repository_type}" -H "accept: application/json" -H "Content-Type: application/json" -d "@${json_path}"; then
        log_msg "REPOSITORIES CREATE REPOSITORY :: Successfully created the repository - ${repository_type}/${repository_name} - ${json_path}"
    else
        error_msg "REPOSITORIES CREATE REPOSITORY :: Failed to create the repository - ${repository_type}/${repository_name} - ${json_path}"
    fi
}


repositories_create_repository_wrapper(){
    local repository_type="$1"
    local repository_name="$2"
    local json_path="$3"
    local repo_exists
    repo_exists=$(repositories_get_docker_repository "$repository_type" "$repository_name")
    if [[ "$repo_exists" = "true" ]]; then
        log_msg "REPOSITORIES CREATE REPOSITORY :: Repository exists - $repository_type/$repository_name"
    elif [[ "$repo_exists" = "404" ]]; then
        log_msg "REPOSITORIES CREATE REPOSITORY :: Repository not found - $repository_type/$repository_name"
        log_msg "REPOSITORIES CREATE REPOSITORY :: Creating the repository - $repository_type/$repository_name ..."
        repositories_create_repository "$repository_type" "$repository_name" "$json_path"
    elif [[ "$repo_exists" = "403" ]]; then
        error_msg "REPOSITORIES CREATE REPOSITORY :: Authorization error [403] - $repository_type/$repository_name"
    elif [[ "$repo_exists" = "401" ]]; then
        error_msg "REPOSITORIES CREATE REPOSITORY :: Authentication error [401] - $repository_type/$repository_name"
    else
        error_msg "REPOSITORIES CREATE REPOSITORY :: Unknown error [$repo_exists] - $repository_type/$repository_name"
    fi
}
### --------------------------------------------------


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
