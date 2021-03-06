#!/bin/bash

#Contador de etapas para simulação de instalação de apps
export SUBSHL_BOSTA_STEP
SUBSHL_BOSTA_STEP=$(mktemp)
export SUBSHL_BOSTA_PROGRESS
SUBSHL_BOSTA_PROGRESS=$(mktemp)


function get_install_progress(){
    if ! [ -s "$SUBSHL_BOSTA_PROGRESS" ]; then
        echo "0" >"$SUBSHL_BOSTA_PROGRESS"
    fi
    cat "$SUBSHL_BOSTA_PROGRESS"
}

function set_install_progress() {
    echo "$1" >"$SUBSHL_BOSTA_PROGRESS"
}


function get_install_step() {
    if ! [ -s "$SUBSHL_BOSTA_STEP" ]; then
        echo "0" >"$SUBSHL_BOSTA_STEP"
    fi
    cat "$SUBSHL_BOSTA_STEP"
}

function set_install_step() {
    echo "$1" >"$SUBSHL_BOSTA_STEP"
}

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
    local response_qpkg_cli progress
    progress=$(get_install_progress)
    local -a responseSet=(
        "invalid QPKG $2"                              #(0) - #* Não usar nos testes da flag (-s)
        "QPKG $2 not found"                            #(1)
        "QPKG $2 is queuing"                           #(2)
        "QPKG $2 download $progress %"          #(3)
        "QPKG HybridBackup is in installation stage 0" #(4)
        "QPKG HybridBackup is in installation stage 1" #(5)
        "QPKG HybridBackup is in installation stage 2" #(6)
        "QPKG $2 is installed"                         #(7)
    )

    local step
    step=$(get_install_step)
    if [[ "$1" == '-s' ]]; then #info de shares
        case $step in
        0)
            ((step++))
            #####step=3 #! TESTE DE AVALAIÇÂO
            ;;
        1) #nada alterado
            ;;
        2)
            ((step++))
            ;;
        3)
            progress=$((progress + 10))
            set_install_progress "$progress"
            if [[ progress -gt 100 ]]; then
                step=4                
            fi
            ;;
        esac
        response_qpkg_cli="${responseSet[$step]}"
    elif [[ "$1" == '-a' ]]; then #*Instalação
        step=2
        response_qpkg_cli="${responseSet[$step]}"
    fi
    set_install_step "$step"    
    echo "$response_qpkg_cli"
}
