#!/bin/bash

function test_not_empty() {
    local value="$1"
    if [[ -n "${value}" ]]; then
        return 0
    else
        return 1
    fi
}

function read_string() {
    local prompt="$1"
    shift
    local initValue="$1"
    shift
    local validator=${1?No function specified}
    shift
    local sameLine="$1"
    shift
    local readValue=''
    while ! $validator "${readValue}"; do
        #todo: Rodar a baiana para bash < 4 que não tem (-i) no read
        read -re -p "$prompt" -i "${initValue}" readValue
        if [[ -n "${sameLine}" ]]; then
            echo -n "$readValue"
        else
            echo "$readValue"
        fi
    done
}


function read_password(){
    local prompt="$1"
    shift
    local validator=${1?No function specified}
    shift
    local readPass=''
    while ! $validator "${readPass}"; do
        #todo: Rodar a baiana para bash < 4 que não tem (-i) no read
        read -res -p "$prompt" -i "${initValue}" readPass
        if [[ -n "${sameLine}" ]]; then
            echo -n "$readPass"
        else
            echo "$readPass"
        fi
    done
}
