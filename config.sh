#!/bin/bash

#Clean up 20220802

#*################################################  PONTO DE ENTRADA ###################################################

#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
declare dummy
declare success

envDir="${PWD}" #Root from project
#Test DEV(machine) state signature
if [ -d "/media/sf_WD/operations/qnap-config/src" ]; then
    APP_LIB_DIR="/media/sf_WD/operations/qnap-config/src/lib/"
    APP_DBG_DIR="/media/sf_WD/operations/qnap-config/src/debug/"
else
    APP_LIB_DIR="$PWD/"
    APP_DBG_DIR="${PWD}/debug/"
fi
export APP_DBG_DIR
export APP_LIB_DIR

#Load all dependencies
# shellcheck source=/dev/null
source "${APP_LIB_DIR}cmdargs.sh"
# shellcheck source=/dev/null
source "${APP_LIB_DIR}utilsFuncs.sh"

#*Shows execution environment
if env | grep -E "^APP_|^GLOBAL_|^TEST_" >/dev/null; then # "^APP_*" >/dev/null; then
    echo "Ambiente original listado abaixo:"
    debug_show_vars
else
    echo "Nenhuma configuração de ambiente(env=|prod|dev) presente na linha de comando ou ambiente original"
fi
echo "Carregando ambiente de execução..."
#* Load environment from .env/.secret files or addictionaly others informed by APP_ENV variable value
process_env "$envDir" #Search for .env and .secret files(or addionaly others) at $envDir
echo -e "\n\n"

#Load additional arguments from command line and overwrite values loaded from .env file(s) above
read_cl_args "$@"

#Show all relevant global & app parameters
if ((GLOBAL_DEBUG_LEVEL + GLOBAL_DEV_LEVEL)); then
    debug_show_vars
fi

#* Show/test filtered configuration about special locations
if [[ $APP_IS_DEBUG ]]; then
    if [[ $((APP_MAX_NVI_ID - APP_MIN_NVI_ID + 1)) -ne ${#APP_NVI_MAPPING[@]} ]]; then
        echo "Mapeamento dos grupos para os NVIs divergem em cardinalidade"
        exit
    fi
fi

#* Test if simulation mode will be activated
if [[ $APP_IS_DEV_ENV ]]; then
    #* Development environment implies switches for simulated call at utilsFuncs.sh
    switch_simulated_qcli #!as chamadas serão todas simuladas com as respostas montadas internamente
    echo "Alternando para o modo de API(QCLI) simulada" | slog 5
else
    if [[ "$EUID" -ne 0 && "$APP_IS_DEV_ENV" -eq 0 ]]; then
        echo "Necessário usar credenciais de administrador do NAS"
        echo 'Encerrando operação.'
        exit
    fi
fi

#* Reads location attributes to asset information
read_local_id success
if [[ $success -ne 0 ]]; then
    echo "Identificador da unidade( ${APP_LOCAL_ID} ) inválido. Encerrando operação." | slog 2
    exit
else
    slog 6 "Selecionada a unidade: $APP_LOCAL_ID"
fi

#* Reads ordinal index of device to asset information(defaul 1)
read_device_id success
if [[ $success -ne 0 ]]; then
    echo "Índice do dispositivo( ${APP_DEVICE_ORDER_ID} ) inválido. Encerrando operação." | slog 2
    exit
else
    slog 6 "Selecionado índice do dispositivo: $APP_DEVICE_ORDER_ID"
fi

#* Reads domain credentials
read_domain_credential success
if [[ $success -ne 0 ]]; then
    echo "Credenciais do domínio não foram fornecidas adequadamente." | slog 2
    exit
else
    slog 6 "Credencial do domínio a ser utilizada($APP_DOMAIN_ADM_ACCOUNT)"
fi

#* Reads NAS administrative credentials
read_NAS_credential success
if [[ $success -ne 0 ]]; then
    echo "Credenciais do ADM local não foram fornecidas adequadamente." | slog 2
    exit
else
    slog 6 "Credencial do ADM local ser utilizada($APP_NAS_ADM_ACCOUNT)"
fi

#* Starts an administrative session
authenticate_session success
if [[ $success -ne 0 ]]; then
    echo "Autenticação falhou. Encerrando operação." | slog 2
    exit
else
    slog 6 "Acesso à API do NAS concedido para ($APP_NAS_ADM_ACCOUNT)"
fi

#* Rename asset 
declare localIDStr
localIDStr="$(printf "%03d" "$APP_LOCAL_ID")"
deviceOrderID="$(printf "%02d" "$APP_DEVICE_ORDER_ID")" #todo:future: parameter with digits to pad with zeros
declare APP_NAS_HOSTNAME="ZPB${localIDStr}NAS${deviceOrderID}"
export APP_NAS_HOSTNAME
setDeviceName success | slog 6
if [[ $success -ne 0 ]]; then
    echo "Falha renomeando dispositivo para: ${APP_NAS_HOSTNAME}" | slog 3
    exit "$success"
else
    echo "Nome do dispositivo ajustado para: ${APP_NAS_HOSTNAME}" | slog 6
fi

#* Additional parameters for operation
set_extra_settings success
if [[ $success -ne 0 ]]; then
    echo "Falha ajustando parâmetros adicionais!!!" | slog 3
    exit
else
    echo "Todos os parâmetros adicionais foram ajustados!" | slog 6
fi

#* Accessory network configuration
first_network_setup success
if [[ $success -ne 0 ]]; then
    echo "Falha ajustando os parâmetros iniciais da rede!!!" | slog 3
    exit
else
    echo "Setup inicial da rede realizado com sucesso!" | slog 6
fi

#* Domain configuration
join_to_domain success
if [[ $success -ne 0 ]]; then
    echo "Falha durante o ingresso no domínio!!!" | slog 3
    echo "Verifique contas anteriores e conectividade de rede e tente novamente." | slog 3
    exit
else
    echo "Ingresso no domínio realizado com sucesso!" | slog 6
fi

#* Storage pool creation/validation based on volumes.json file content
create_pool success
if [[ $success -ne 0 ]]; then
    echo "Falha criando pool de armanzenamento primário!!!" | slog 3
    exit
else
    echo "Pool de armazenamento primário criado com sucesso!" | slog 6
fi

#* Wait for NAS synchronization to continue with the process
wait_resync success
if [[ $success -ne 0 ]]; then
    echo "Falha sincronizando os discos!!!" | slog 3
    echo "Verificque a integridade dos mesmo e tente novamente"
    read -r -p "Pressione <ENTER> para finalizar" dummy
    echo "$dummy" >/dev/null
    exit
else
    echo "Pool de armazenamento primário sincronizado com sucesso!" | slog 6
fi

#* Renew administrative session because previous step take a long time to complete
authenticate_session success
if [[ $success -ne 0 ]]; then
    echo "Autenticação pós criação do pool de armazenamento falhou. Encerrando operação." | slog 2
    exit
else
    slog 6 "Acesso à API do NAS renovado(preventivamente) para ($APP_NAS_ADM_ACCOUNT) pós processo de sincronização de pool"
fi

#* Create first share only(primary share will be the system volume)
create_volumes success "$(get_volume_config_file)" 1 #0/null -> runout all volumes to be created without limit(follow volumes.json content)
if [[ $success -ne 0 ]]; then
    echo "Falha criando os volumes no pool de armazenamento primário!!!" | slog 3
    exit
else
    echo "Volumes criados/validados com sucesso!" | slog 6
fi

#* Essencial packages installation( Hybrid Backup at least ) - Requires internet access !!!
echo "Aguarde instalando Hybrid backup..."
install_package success "HybridBackup"
if [[ $success -ne 0 ]]; then
    echo "Falha instalando \"HybridBackup\" Verifique a conectividade com a internet!!!" | slog 3
    exit
else
    echo "Pacote HybridBackup instalado com sucesso!" | slog 6
fi

#* Create remains volumes, vinculated primary share and others secondary shares to the same volume
create_volumes success "$(get_volume_config_file)" 0 #0/null -> 0 here,  implies all volumes.json content will be processed, dont only [n] volumes (see above)
if [[ $success -ne 0 ]]; then
    echo "Falha criando os volumes no pool de armazenamento primário!!!" | slog 3
    exit
else
    echo "Volumes criados/validados com sucesso!" | slog 6
fi

#* Adjusting permissions for shares
set_shares_permissions success "$APP_LOCAL_ID"
if [[ $success -ne 0 ]]; then
    echo "Falha ajustando as permissões!!!" | slog 3
    exit
else
    echo "Permissões ajustadas com sucesso!" | slog 6
fi

#* Configuring SNMP(partially tested)
config_snmp success
if [[ $success -ne 0 ]]; then
    echo "Falha registrando-se no serviço de monitormamento!!!" | slog 3
    exit
else
    echo "Configurações de monitoramento efetivadas com sucesso!" | slog 6
fi

#todo:future:???: enable syslog???
#setcfg "Global" "Enable" -f "/etc/config/syslog_server.conf" TRUE

declare -i lastOctect
lastOctect=$((APP_IP_BASE + APP_DEVICE_ORDER_ID - 1)) #BASE ZERO
# shellcheck source=/dev/null
source "${APP_LIB_DIR}/net_final_config.sh" success "${APP_PRIMARY_NET_INTERFACE}" \
    "10.183.${APP_LOCAL_ID}.${lastOctect}" "255.255.255.0" "10.183.${APP_LOCAL_ID}.${APP_ROUTER_LAST_OCTECT}" "$APP_DNS1" "$APP_DNS2"

if [[ $success -ne 0 ]]; then
    echo "Erro durante etapa final da rede($success)" | slog 3
else
    echo "Ajuste final da rede efetivado com sucesso!" | slog 6
    echo "Processo de desligamento iniciado..." | slog 6
    if ! ((APP_IS_DEBUG)); then
        echo -e "\n\n\nA preparação do NAS ${APP_NAS_HOSTNAME} finalizada!!!"
        echo -e "\n\n\nObrigado!\n\n\n"
        poweroff -f -d 10
    fi
fi
