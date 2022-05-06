#!/bin/bash

function test_get_files_list_b3() {
	declare -a G_RET_A=() #declare -ga necessario para bash3 lidar com arrays
	echo "TESTE: Entrada de ${FUNCNAME[0]}" | slog 7
	echo "Exibindo todos os arquivos sh da pasta corrente:"
	get_files_list_b3 G_RET_A "$PWD" "sh"
	echo "Resultado da busca por *.sh.."
	for ((i = 0; i < "${#G_RET_A[@]}"; ++i)); do
		printf "%s\n" "${G_RET_A[$i]%$'\n'}"
	done
	unset G_RET_A
	echo "TESTE: Saida de ${FUNCNAME[0]}" | slog 7
}

#*################################################  PONTO DE ENTRADA ###################################################

#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#* import das rotinas auxiliares
# shellcheck source=/dev/null
#*Dados globais
if [[ "( \"sofredor\" , \"IFPB-UBUN2004V1\" )" =~ $(hostname) ]]; then
	cd "/media/sf_WD/operations/qnap-config/src" || exit
	source "${PWD}/utilsFuncs.sh"
	#*Flags globais ajustadas após carga dos padrões em utilsFuncs.sh
	__IS_DEBUG=1          #!Informa que temos depuração agora
	__IS_DEV_ENV=1        #!Usar dados simulados a partir de arquivos
	switch_simulated_qcli #!as chamadas serão todas simuladas com as respostas montadas internamente
else
	source "${PWD}/utilsFuncs.sh"
	#*Flags globais ajustadas após carga dos padrões em utilsFuncs.sh
	__IS_DEBUG=0
	__IS_DEV_ENV=0
fi
LC_NUMERIC="en_US.UTF-8"
#*Final dos dados globais

#* Parte comum a todos os testes = autenticação
declare ret=0
if get_root_login ret "admin" "12345678"; then
	echo "Privilégios necessários fornecidos!" | slog 6
else
	echo "Autenticação falhou!!!" | slog 3
	echo "$ret" | slog 3
fi

#!DEPURAÇÃO A POSTERIORI FORÇADA
__IS_DEBUG=1 #!Informa que temos depuração agora
#__IS_DEV_ENV=1 #!Usar dados simulados a partir de arquivos

#* Criação do Pool primário(único)
create_pool
ret=$?
if ! [[ $ret ]]; then
	echo "Erro criando pool primário $ret" | slog 3
	exit $ret
fi

#* Tamanho do Pool primário existente
declare poolSize
get_pool_size poolSize
echo "Encontrado um pool com $poolSize"

#* Criação dos volumes
create_volumes "${PWD}/volumes.json"
