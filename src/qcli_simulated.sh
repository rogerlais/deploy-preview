#!/bin/bash

#Contador de etapas para simulação de instalação de apps
declare -i CLI_QPKG_INSTALL=-1
declare -i GLOBAL_PROGRESS=50

function qcli() {
    if [[ "$*" == '-l user=admin pw=12345678 saveauthsid=yes' ]]; then
        return 0
    else
        return 1
    fi
}

function qcli_pool() {
    local response
    if [[ "$*" == "-l" ]]; then
        response=$(<./debug/qcli_pool_list.txt)
    elif [[ "$*" == '-i poolID=1 displayfield=Capacity' ]]; then
        response=$(<./debug/qcli_pool_capacity.txt)
    else
        echo "Chamada simulada qcli_pool não pode ser mapeada para argumentos: $*" | slog 3
    fi
    echo "$response"
}

function qcli_volume() {
    local response
    if [[ $1 == '-c' ]]; then
        response=$(<./debug/qcli_volume_create.txt)
    elif [[ $1 == '-i' ]]; then
        response=$(<./debug/qcli_volume_info.txt)
    else
        echo "Chamada simulada qcli_volume não pode ser mapeada para argumentos: $*" | slog 3
    fi
    echo "$response"
}

function qcli_sharedfolder() {
    local response
    if [[ "$1" == '-i' ]]; then #info de shares
        if [[ $((RANDOM % 2)) ]]; then
            echo "Chamada simulada qcli_sharedfolder -i gerou falha randomicamente provocada $*" | slog 3
            return 1
        fi
        return 0
    elif [[ "$1" == '-s' ]]; then #comando para a criação de um share
        echo "Please use qcli_sharedfolder -i, qcli_sharedfolder -u & qcli_sharedfolder -f to check status!" | slog 3
    fi
    echo "$response"
}

function qpkg_cli() {
    local response
    responseSet=(
        "invalid QPKG $2"   #Não usar nos testes da flag (-s)
        "QPKG $2 not found"
        "QPKG $2 is queuing"
        "QPKG $2 download $GLOBAL_PROGRESS %"
        "QPKG HybridBackup is in installation stage 0"
        "QPKG HybridBackup is in installation stage 1"
        "QPKG HybridBackup is in installation stage 2"
        "QPKG $2 is installed"
    )
    if [[ "$1" == '-s' ]]; then #info de shares
        ((CLI_QPKG_INSTALL++))
        response="${responseSet[$CLI_QPKG_INSTALL]}"
    elif [[ "$1" == '-a' ]]; then #comando para a criação de um share
        response=""
    fi
    echo "$response"
}
