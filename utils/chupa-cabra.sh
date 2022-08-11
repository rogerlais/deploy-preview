#!/bin/bash

envDir="${PWD}" #Root from project
if [ -d "/media/sf_WD/operations/qnap-config/src" ]; then
    # Executando em desenv -> realign path to lib
    APP_LIB_DIR="/media/sf_WD/operations/qnap-config/src/lib/"
    APP_DBG_DIR="/media/sf_WD/operations/qnap-config/src/debug/"
else
    APP_LIB_DIR="$PWD/../lib/"
    APP_DBG_DIR="${PWD}/../debug/"
fi
export APP_DBG_DIR

# shellcheck source=/dev/null
source "${APP_LIB_DIR}cmdargs.sh"
# shellcheck source=/dev/null
source "${APP_LIB_DIR}utilsFuncs.sh"

process_env "$envDir" #busca e carrega de toda a forma agora
debug_show_vars

read_cl_args "$@"

APP_ENDPOINT=$(resolve_arg_value 'target' '#1' "$APP_ENDPOINT")

APP_NAS_ADM_ACCOUNT=$(resolve_arg_value 'login' '#2' "$APP_NAS_ADM_ACCOUNT")

APP_NAS_ADM_ACCOUNT_PWD=$(resolve_arg_value 'pass' '#3' "$APP_NAS_ADM_ACCOUNT_PWD")

APP_TAG_NAME=$(resolve_arg_value 'tag' "$(date '+%Y-%m-%d')")


#Test if last octet from local VLAN informed
if [ -n "$APP_ENDPOINT" ]; then
    if ! [[ "${APP_ENDPOINT}" == *"."* ]]; then
        APP_ENDPOINT="${APP_PRIVATE_VLAN/'0/24'/"$APP_ENDPOINT"}"
    else
        dots=$(echo "$APP_ENDPOINT" | grep -o '\.' | wc -l)
        if [[ "${dots}" -ne 3 ]]; then
            echo "IP inválido( $APP_ENDPOINT )"
            exit 1
        fi
    fi
else
    echo "Informe final do IP do NAS para coletar os dados de configuração!"
    exit
fi

DEST_BASE_DIR="${PWD}/tmp/$APP_TAG_NAME/"
rm -R "$DEST_BASE_DIR" 2>/dev/null
mkdir -p "$DEST_BASE_DIR"
touch "${DEST_BASE_DIR}dummy.txt"

echo "Baixando arquivos de configuração do host=${APP_ENDPOINT}"
declare dummy
#shellcheck disable=2034
read -p "Enter para confirmar...<cr>" -r dummy

echo -e "Copiando dados do NAS(ip/host=${APP_ENDPOINT})...\n"

declare leaf='mnt/HDA_ROOT/.conf'
mkdir -p "${DEST_BASE_DIR}${leaf}"
sshpass -p "$APP_NAS_ADM_ACCOUNT_PWD" rsync -av "${APP_NAS_ADM_ACCOUNT}@${APP_ENDPOINT}:/${leaf}" "${DEST_BASE_DIR}${leaf}"

declare leaf='mnt/HDA_ROOT/.config/'
mkdir -p "${DEST_BASE_DIR}${leaf}"
sshpass -p "$APP_NAS_ADM_ACCOUNT_PWD" rsync -av "${APP_NAS_ADM_ACCOUNT}@${APP_ENDPOINT}:/${leaf}" "${DEST_BASE_DIR}${leaf}"

declare leaf='mnt/HDA_ROOT/.cups/'
mkdir -p "${DEST_BASE_DIR}${leaf}"
sshpass -p "$APP_NAS_ADM_ACCOUNT_PWD" rsync -av "${APP_NAS_ADM_ACCOUNT}@${APP_ENDPOINT}:/${leaf}" "${DEST_BASE_DIR}${leaf}"

declare leaf='mnt/HDA_ROOT/.domain_computer'
mkdir -p "${DEST_BASE_DIR}${leaf}"
sshpass -p "$APP_NAS_ADM_ACCOUNT_PWD" rsync -av "${APP_NAS_ADM_ACCOUNT}@${APP_ENDPOINT}:/${leaf}" "${DEST_BASE_DIR}${leaf}"

declare leaf='mnt/HDA_ROOT/.inited/'
mkdir -p "${DEST_BASE_DIR}${leaf}"
sshpass -p "$APP_NAS_ADM_ACCOUNT_PWD" rsync -av "${APP_NAS_ADM_ACCOUNT}@${APP_ENDPOINT}:/${leaf}" "${DEST_BASE_DIR}${leaf}"

declare leaf='mnt/HDA_ROOT/.logs/'
mkdir -p "${DEST_BASE_DIR}${leaf}"
sshpass -p "$APP_NAS_ADM_ACCOUNT_PWD" rsync -av "${APP_NAS_ADM_ACCOUNT}@${APP_ENDPOINT}:/${leaf}" "${DEST_BASE_DIR}${leaf}"

leaf='etc/' #eh grande esse
mkdir -p "${DEST_BASE_DIR}${leaf}"
sshpass -p "$APP_NAS_ADM_ACCOUNT_PWD" rsync -av "${APP_NAS_ADM_ACCOUNT}@${APP_ENDPOINT}:/${leaf}" "${DEST_BASE_DIR}${leaf}"

leaf='.samba'
mkdir -p "${DEST_BASE_DIR}${leaf}"
sshpass -p "$APP_NAS_ADM_ACCOUNT_PWD" rsync -av "${APP_NAS_ADM_ACCOUNT}@${APP_ENDPOINT}:/${leaf}" "${DEST_BASE_DIR}${leaf}"

# sshpass -p "$APP_NAS_ADM_ACCOUNT_PWD" rsync -av "$PWD/.env" "${DEST_HOST_NAS}"
# sshpass -p "$APP_NAS_ADM_ACCOUNT_PWD" rsync -av "$PWD/.secret" "${DEST_HOST_NAS}"
# sshpass -p "$APP_NAS_ADM_ACCOUNT_PWD" rsync -av "$PWD/LINUX_DEV.env" "${DEST_HOST_NAS}"
# sshpass -p "$APP_NAS_ADM_ACCOUNT_PWD" rsync -av "$PWD/LINUX.env" "${DEST_HOST_NAS}"

#sshpass -p "$APP_NAS_ADM_ACCOUNT_PWD" rsync -av "$PWD/src/volumes.json" "${DEST_HOST_NAS}"
# sshpass -p "$APP_NAS_ADM_ACCOUNT_PWD" rsync -av "$PWD/src/debug/volinfo.txt" "${DEST_HOST_NAS}debug/" #fora da versão final
# sshpass -p "$APP_NAS_ADM_ACCOUNT_PWD" rsync -av "$PWD/src/login_manual.sh" "${DEST_HOST_NAS}"         #Fora da versão final
# sshpass -p "$APP_NAS_ADM_ACCOUNT_PWD" rsync -av "$PWD/src/parts/shorts.sh" "${DEST_HOST_NAS}parts/"   #Fora da versão final
# sshpass -p "$APP_NAS_ADM_ACCOUNT_PWD" rsync -av "$PWD/src/qcli_simulated.sh" "${DEST_HOST_NAS}"       #fora da versão final
# sshpass -p "$APP_NAS_ADM_ACCOUNT_PWD" rsync -av "$PWD/src/debug/" "${DEST_HOST_NAS}debug/"            #fora da versão final
