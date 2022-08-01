#!/bin/bash

#-------------------
# Globals
#-------------------
declare -a CMD_FREE_ARGS
export CMD_FREE_ARGS
#bash less than 3.5 no asociative arrays -> 2 arrays to storage(key, val)
declare -a CMD_KEY_ARGS CMD_VAL_ARGS
export CMD_KEY_ARGS CMD_VAL_ARGS
declare -a CMD_FLAGS_ARGS
export CMD_FLAGS_ARGS

#this_file="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

function reset_args() {
    #todo reset all globals( eg. by reload process/env )
    return 0
}

function import_arguments() {
    #Processa o array como entrada de linha de comando. Neste método a metodologia considera pares key/value e argumentos livres e flags atomicas('-' como token )
    #Keys are case insensitive
    #flags are case sensitive
    #* Exemplo import_arguments "$@"
    #!bug: keynames as 'user' and 'pwd' are truncated to '' AVOID them
    #Como saída, teremos:
    # 1 - Os pares KEY='value' exportados globalmente(KEY uppercased)
    # 2 - Exportado FREE_ARGS com os argumentos avulsos pela ordem que aparecem
    reset_args
    for arg in "$@"; do
        if [[ "${arg}" == *'='* ]]; then
            #echo "KEY:VALUE -> ${arg}"
            parts=() #bug chato se não declarar
            IFS='=' read -r -a parts <<<"$arg"
            parts[0]=$(tr '[:lower:]' '[:upper:]' <<<"${parts[0]}") #uppercase bash less 4
            CMD_KEY_ARGS+=("${parts[0]}")
            CMD_VAL_ARGS+=("${parts[1]}")
        else
            if [[ "${arg:0:1}" == '-' ]]; then
                #store flag
                flags=()
                IFS='-' read -r -a flags <<<"$arg"
                CMD_FLAGS_ARGS+=("${flags[1]}")
            else
                CMD_FREE_ARGS+=("$arg")
            fi
        fi
    done
}

function resolve_arg_value() {
    #Resolve an input argument based at:
    #1 - key,value pair
    #2 - positional order
    #3 - default value
    # Use cases
    #a) Only $1 passed -> Only key lookup
    #b) With first char from $2 = '#' positional is used and $3 is considered as default value
    #c) To negative from (b), $2 is considered defaul value and $3...$n ignored
    local keyname
    keyname=$(tr '[:lower:]' '[:upper:]' <<<"$1") #uppercase bash less 4
    #try by key name only
    if [[ " ${CMD_KEY_ARGS[*]} " == *" ${keyname} "* ]]; then
        local arraylength=${#CMD_KEY_ARGS[@]}
        for ((i = 0; i < arraylength; i++)); do
            if [[ "${CMD_KEY_ARGS[$i]}" == "${keyname}" ]]; then #case sensitive too
                echo "${CMD_VAL_ARGS[$i]}"                       #return arg value
                return 0
            fi
        done
    fi
    local escapeArg2="${2//\\/\\\\}"
    if [[ -n "${escapeArg2}" ]]; then
        #try by positional, if $2[0] == '#'
        if [[ "${escapeArg2:0:1}" == '#' ]]; then
            #!bug linter next line
            P=$(("${escapeArg2##*#}")) #get string after last '#'(must be number only)
            if ((P < ${#CMD_KEY_ARGS[@]})); then
                echo "${CMD_VAL_ARGS[$P]}"
            else
                #positional arg exceeds informed, try default or error
                if [[ -n "${3}" ]]; then
                    echo "$3"
                    return 0
                else
                    return 1 #*error
                fi
            fi
        else
            #return by default value
            echo "$2"
            return 0
        fi
    else
        echo '' #Without default -> nothing
        return 0
    fi
}
