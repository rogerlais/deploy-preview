#!/bin/bash


#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
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
# shellcheck source=/dev/null
source "${APP_LIB_DIR}prompts.sh"


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

#Fix/Bind command line arguments
APP_USER=$( resolve_arg_value 'user' '#1' ) 
APP_PWD=$( resolve_arg_value 'pass' '#2' )

if [[ -z "${APP_USER}" ]]; then
    APP_USER=$( read_string 'Informe o nome do usuário: ' "$APP_USER" 'test_not_empty' )
fi

if [[ -z "${APP_PWD}" ]]; then
    APP_PWD=$( read_password "Informe a senha para (${APP_USER}): " "$APP_PWD" 'test_not_empty' )
fi


#Show all relevant global & app parameters
if ((GLOBAL_DEBUG_LEVEL + GLOBAL_DEV_LEVEL)); then
    debug_show_vars
fi

#Call to authentication API 
qcli -l user="${APP_USER}" pw="${APP_PWD}" saveauthsid=yes
success=$?
if [[ $success ]]; then
    echo "Falha durante autenticação da sessão( ${success} )"
    exit $success
fi

#Caso a conta não seja root, usar comando abaixo pode ser necessário
#sudo -i ou sudo -S

