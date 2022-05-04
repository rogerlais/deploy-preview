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
	__IS_DEBUG=1 #!Informa que temos depuração agora
	__IS_DEV_ENV=1  #!Usar dados simulados a partir de arquivos
else
	source "${PWD}/utilsFuncs.sh"
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

create_volumes "${PWD}/volumes.json"

exit

#valores em human-readble to integer
echo "\"convertShortLongByteSize \"123.5	 TB\"\""
val=$(convertShortLongByteSize "123.5	 TB") #spaces & tabs at sample
echo "Valor bruto flututante: $val bytes"
echo "Valor bruto inteiro: $(truncToInt "$val") bytes"

totalPoolSize=$(get_pool_size "1")
echo "Resultado de get_pool_size \"1\": $totalPoolSize"
echo "Resultado de get_pool_size em bytes \"1\": $( (convertShortLongByteSize "${totalPoolSize}"))"

exit 0

#Valores inteiros absolutos a partir do percentual do tamanho total
dspValue=$(get_abs_value "2342342" "12.5")
echo "Resultado de get_abs_value \"2342342\" \"12.5\" : $dspValue"

dspValue=$(get_pool_size "1")
echo "Resultado de get_pool_size \"1\": $dspValue"


#todo inciar montagem menu seleção abaixo
# declare -a G_RET_A=()
# get_files_list_b3 G_RET_A "$PWD" "json"
# echo -e "Retorno \n ${G_RET_A[@]}"
# for ((i=0;i<"${#G_RET_A[@]}";++i)); do
#     printf "%s\n" "${G_RET_A[$i]%$'\n'}"
# done
# unset G_RET_A
