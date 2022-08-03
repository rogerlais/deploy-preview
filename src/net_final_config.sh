#!/bin/bash

function final_network_setup() {
    local retf="$1"
    local adapter="$2"
    local ipv4="$3"
    local netmask="$4"
    local def_gateway="$5"
    local dns1="$6"
    local dns2="$7"
    local dummy

    echo "Esta etapa irá configurar a interface ${adapter} para os seguintes valores:"

    #echo "IP=10.183.${ipv4}.${hostNumber} netmask=255.255.255.0 gateway=10.183.${ipv4}.70 dns_type=manual dns1=${dns1} dns2=${dns2}"
    echo "IP=${ipv4} netmask=${netmask} gateway=${def_gateway} dns_type=manual dns1=${dns1} dns2=${dns2}"


    echo "Após isso, o acesso ao dispositivo será perdido e o mesmo será desligado"
    local promptAnswer
    get_prompt_confirmation promptAnswer "Confirma finalização do processo?" "SN"
    if [[ 'Ss' == *"$promptAnswer"* ]]; then
        echo "Finalizando as configurações da rede e desligando o NAS."
        echo "Após isso a comunicação será perdida e o dispositivo sera reiniciado."
        read -p "Pressione enter para finalizar..." -r dummy
        echo "$dummy" >/dev/null
        qcli_network -m interfaceID="${adapter}" IPType=STATIC \
            IP="${ipv4}" netmask="$netmask" gateway="$def_gateway" \
            dns_type=manual dns1="${dns1}" dns2="${dns2}" | slog 6
        retf=$?
    else
        retf=1
    fi
    printf -v "$1" "%d" $retf
}

if [[ -z "${APP_LIB_DIR}" ]]; then
    APP_LIB_DIR="$PWD"
fi

echo "externa oriunda de ${APP_LIB_DIR}"

# shellcheck source=/dev/null
source "${APP_LIB_DIR}/utilsFuncs.sh"


function main_net_final_config() {
    local ret="$1"
    local adaptername="$2"
    local ipv4="$3"
    local netmask="$4"
    local def_gateway="$5"
    local dns1="$6"
    local dns2="$7"
    echo -e "Uso: \"variável_retorno(obrigatória)\" \"nome_adaptador\" \"IPV4\" \"mascara\" \"gateway\" \"dns1\" \"dns2\""
    if [[ -z $dns2 ]]; then
        echo "Todos os argumentos são necessários. Repita a chamada conforme uso mostrado acima."
    fi
    final_network_setup ret "$adaptername" "$ipv4" "$netmask" "$def_gateway" "$dns1" "$dns2"
    #final_network_setup success "203" "10.12.0.134" "10.12.0.228"
    echo "Retorno final = $ret"
    printf -v "$1" "%d" "$ret"
}


if [[ $APP_IS_DEV_ENV -ne 0 ]]; then
    #*Flags globais ajustadas após carga dos padrões em utilsFuncs.sh
    switch_simulated_qcli #!as chamadas serão todas simuladas com as respostas montadas internamente
    # shellcheck source=/dev/null
    source "${APP_LIB_DIR}/qcli_simulated.sh"  #call to switch_simulated_qcli above with bug??
    echo "Alternando para o modo de API(QCLI) simulada" | slog 5
else
    if [[ "$EUID" -ne 0 && "$APP_IS_DEV_ENV" -eq 0 ]]; then
        echo "Necessário usar credenciais de administrador do NAS"
        echo 'Encerrando operação.'
        exit
    fi
fi

declare success="$1"
main_net_final_config success "$2" "$3" "$4" "$5" "$6" "$7"
if [ "$success" -eq 0 ]; then
    echo "Rede ajustada"
    printf -v "$1" "%d" 0
else
    echo "Falha ajustando a rede: ${success}"
    printf -v "$1" "%d" 1
fi
