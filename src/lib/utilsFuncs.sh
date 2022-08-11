#!/bin/bash

#todo:future: Implementar leitura dos parametros dos discos e não pedir ao usuário
#hdparm -I /dev/sda para pegar atributos do disco

#todo:future: Move all Logging operations to a separate file

declare -a LOG_LEVELS
# https://en.wikipedia.org/wiki/Syslog#Severity_level
LOG_LEVELS=([0]="emerg" [1]="alert" [2]="crit" [3]="err" [4]="warning" [5]="notice" [6]="info" [7]="debug")
declare VOLUME_INEXISTS=10
declare VOLUME_OK=0
declare VOLUME_DIVERGENT=20

#*constantes para tamanhos de discos esperados(calculo meio furado e aproximado)
# shellcheck disable=SC2034
{
	DISK_SIZE_1TB=926720000000 #referencia base para as demais
	DISK_SIZE_2TB=1853440000000
	DISK_SIZE_3TB=2780160000000
}

function get_scriptname(){
	#Returnns the base name from script that started this process
	todo:lib: Move to lib
	basename "$(test -L "$0" && readlink "$0" || echo "$0")"
}

function setDeviceName() {
    local retf="$1"
    local newName="$APP_NAS_HOSTNAME" #was an argument, now uses global
    local curName
    curName=$(getcfg system "Server Name")
    echo "Novo nome=($newName) - Nome antigo=($curName)"
    if [ "$newName" != "$curName" ]; then
        echo "Alterando o nome do dispositivo para ($newName)..."
        setcfg system "Server Name" "$newName" #* em testes, tal chamada aceita praticamente tudo sem gerar erro
        #todo:future: informar no comentário sobre este servidor para exibição, demais dados, como cidade, etc(agora usando apenas valor de newName)
        setcfg system "Server Comment" "$newName"
        retf=$?
        if [ $retf -ne 0 ]; then
            echo "Falha renomeando dispositivo - erro: $retf"
        else
            echo "Nome do dispositivo alterado de ($curName) para ($newName)"
        fi
    else
        slog 6 "Nome atual já corretamente atribuído para: $newName"
        retf=0
    fi
    printf -v "$1" "%d" $retf
}


function read_confirm_input() {
	local retf="$1"
	local prompt="$2"
	local defValue="$3"
	local isPrivate="$4"
	[[ -z "$isPrivate" ]] && isPrivate=0
	if [[ -n $defValue ]]; then #Valor default existe
		local promptAnswer
		if [[ isPrivate -ne 0 ]]; then
			get_prompt_confirmation promptAnswer "$prompt - Confirma o uso do valor(********)?" "SN"
		else
			get_prompt_confirmation promptAnswer "$prompt - Confirma o uso do valor($defValue)?" "SN"
		fi
		if [[ 'Ss' == *"$promptAnswer"* ]]; then
			retf=$defValue
		else
			if [[ isPrivate -ne 0 ]]; then
				read -r -s -p "$prompt" retf
				echo #Volta a linha omitida pelo prompt não ecoado
			else
				read -r -p "$prompt" retf
			fi
		fi
	fi
	printf -v "$1" "%s" "$retf"
}

function read_domain_credential() {
	local retf="$1"
	local retfInner
	if [[ -n $APP_DOMAIN_ADM_ACCOUNT && -n $APP_DOMAIN_ADM_ACCOUNT_PWD ]]; then
		get_prompt_confirmation retfInner "Deseja usar as credenciais salvas para ( $APP_NAS_DOMAIN\\$APP_DOMAIN_ADM_ACCOUNT )?" 'SN'
		[[ 'sS' == *"$retfInner"* ]] && return 0
	fi
	local userInput
	read_confirm_input userInput "Informe conta com permissão de ingresso no domínio $APP_NAS_DOMAIN:" "$APP_DOMAIN_ADM_ACCOUNT" "0"
	local pwdInput
	read_confirm_input pwdInput "Informe a senha para( $APP_NAS_DOMAIN\\$userInput ):" "$APP_DOMAIN_ADM_ACCOUNT_PWD" "1"
	if [[ -n $userInput && -n $pwdInput ]]; then
		APP_DOMAIN_ADM_ACCOUNT="$userInput"
		APP_DOMAIN_ADM_ACCOUNT_PWD="$pwdInput"
		retf=0
	else
		echo "Credenciais inválidas. Tentar novamente?"
		retf=1
	fi
	printf -v "$1" "%d" "$retf"
}

function read_NAS_credential() {
	local retf="$1"
	local retfInner
	if [[ -n $APP_NAS_ADM_ACCOUNT && -n $APP_NAS_ADM_ACCOUNT_PWD ]]; then
		get_prompt_confirmation retfInner "Deseja usar as credenciais salvas para a conta local\ADM do NAS?" "SN"
		[[ 'Ss' == *"$retfInner"* ]] && return 0
	fi

	local userInput
	read_confirm_input userInput "Informe a conta ADM local em $HOSTNAME:" "$APP_NAS_ADM_ACCOUNT" "0"

	local pwdInput
	read_confirm_input pwdInput "Informe a senha da conta ($HOSTNAME\\$userInput):" "$APP_NAS_ADM_ACCOUNT_PWD" "1"

	if [[ -n $userInput && -n $pwdInput ]]; then
		APP_NAS_ADM_ACCOUNT="$userInput"
		APP_NAS_ADM_ACCOUNT_PWD="$pwdInput"
		echo "read NAS Credential saida com user = $APP_NAS_ADM_ACCOUNT senha = $APP_NAS_ADM_ACCOUNT_PWD"
		retf=0
	else
		echo "Credenciais inválidas. Tentar novamente?"
		retf=1
	fi
	printf -v "$1" "%d" "$retf"
}

function read_device_id() {
	local retf="$1"
	local -i deviceId=0
	if [ -n "$APP_DEVICE_ORDER_ID" ]; then
		get_prompt_confirmation retfInner "Deseja usar o valor padrão para o índice do dispositivo(${APP_DEVICE_ORDER_ID})?" 'SN'
		[[ 'sS' != *"$retfInner"* ]] && APP_DEVICE_ORDER_ID=0
		[[ $APP_DEVICE_ORDER_ID != 0 ]] && retf=0 || retf=1
	fi
	while [[ "$APP_DEVICE_ORDER_ID" -lt "1" ]]; do
		echo -n "Digite índice do dispositvo no contexto da unidade: "
		read -r deviceId
		if [ -n "$deviceId" ]; then
			if [[ "$deviceId" -ge "1" ]]; then
				APP_DEVICE_ORDER_ID=$deviceId
				retf=0
			else
				echo "Índice( $deviceId ) é inválido."
			fi
		else
			slog 2 "Coleta de dados cancelada pelo usuário"
			retf=1 #reporta erro
		fi
	done
	printf -v "$1" "%d" "$retf"
}

function read_local_id() {
	local retf="$1"
	local -i localId=0
	if [ -n "$APP_LOCAL_ID" ]; then
		echo "Valor da unidade ( $APP_LOCAL_ID ) pré-carregado do ambiente" | slog 6
		if [ "$(get_localId_class "$APP_LOCAL_ID")" -gt "0" ]; then #* ret > 0 -> ou zona(1) ou NVI(2)
			retf=0
		else
			if [ $retf -lt 0 ]; then
				echo "Valor carregado inválido( $APP_LOCAL_ID )."
				retf=1
			fi
		fi
	else
		while [[ "$(get_localId_class "$APP_LOCAL_ID")" -lt "1" ]]; do
			echo -n "Digite identificador da unidade Eleitoral: "
			read -r localId
			if [ -n "$localId" ]; then
				if [[ "$(get_localId_class "$localId")" -gt "0" ]]; then
					APP_LOCAL_ID=$localId
					retf=0
				else
					echo "Identificador( $localId ) é inválido."
				fi
			else
				slog 2 "Coleta de dados cancelada pelo usuário"
				retf=1 #reporta erro
			fi
		done
	fi
	printf -v "$1" "%d" "$retf"
}

function switch_simulated_qcli() {
	# shellcheck source=/dev/null
	source "${APP_LIB_DIR}/qcli_simulated.sh"
}

function get_prompt_confirmation() {
	local ret_prompt_confirmation="$1"
	local screenPrompt="$2"
	local availbleOptions="$3"
	echo -n "${screenPrompt}[$availbleOptions]:" >&2 #não inserir na saída do método
	ret_prompt_confirmation=$(get_key_press "$availbleOptions")
	echo "$ret_prompt_confirmation"
	printf -v "$1" "%s" "$ret_prompt_confirmation"
}

function get_key_press() {
	local validCharSet="$1"
	local defaultResult="$2"
	local caseSensitive="$3"
	local ret_get_key_press=''
	while [[ -z $ret_get_key_press ]]; do
		read -rsn1 ret_get_key_press
		if [[ ! $caseSensitive ]]; then
			#validCharSet=${validCharSet^^}  #*BASH > 4
			validCharSet=$(tr '[:lower:]' '[:upper:]' <<<"${validCharSet}") #* BASH < 4
			#ret_get_key_press=${ret_get_key_press^^}
			ret_get_key_press=$(tr '[:lower:]' '[:upper:]' <<<"${ret_get_key_press}")
		fi
		if ! [[ "$validCharSet" == *"$ret_get_key_press"* ]]; then #Valor fora do conjunto -> tentar de novo caso inexista default
			ret_get_key_press=''
		fi
		if [[ -z $ret_get_key_press && -n $defaultResult ]]; then
			ret_get_key_press=${defaultResult}
		fi
	done
	echo "$ret_get_key_press"
}

function create_secondary_share() {
	local ret_create_secondary_share=$1
	local sharename=$2
	local volAlias=$3
	local -i ret_create_secondary_share=0
	local -i volID
	get_volume_id_by_alias volID "$volAlias"
	if [[ volID -le 0 ]]; then
		echo "Alias com o nome ($volAlias) não encontrado. para a criação do compartilhamento( $sharename )" | slog 7
		ret_create_secondary_share=1 #Volume não encontrado
	else
		qcli_sharedfolder -i sharename="$sharename" &>/dev/null #Gera erro para sharename invalido -> cria-se
		if [[ $? ]]; then
			echo "Novo comparilhamento secundário em criação $sharename no volume $volID" | slog 6
			qcli_sharedfolder -s sharename="$sharename" volumeID="$volID" &>/dev/null #convert volumeID base 0 to 1
			ret_create_secondary_share=$?
			#todo: validar se chamada acima precisa aguardar processo finalizar
			#*saida comando acima abaixo reproduzida abaixo, omitida no console:
			#Please use qcli_sharedfolder -i, qcli_sharedfolder -u & qcli_sharedfolder -f to check status!
			#!remover na versão final as 3 linhas abaixo
			echo "SAIDA qcli_sharedfolder -i sharename=$sharename"
			qcli_sharedfolder -i sharename="$sharename"
			echo "SAIDA qcli_sharedfolder -u sharename=$sharename"
			qcli_sharedfolder -u sharename="$sharename"
			echo "SAIDA qcli_sharedfolder -f sharename=$sharename"
			qcli_sharedfolder -f sharename="$sharename"
		else
			echo "Sharename ( $sharename ) já existe." | slog 5 #Não gera erro
		fi
	fi
	printf -v "$1" "%d" "$ret_create_secondary_share"
}

function test_json() {
	#todo:lib: levar para lib o teste de json( 0 - sucesso, 1 - falha, 4 - inválido)
	#Ref.: https://stackoverflow.com/questions/46954692/check-if-string-is-a-valid-json-with-jq
	local jsonfile="$1"
	if ! [ -r "$jsonfile" ]; then
		echo "Caminho para os dados dos cvolumes ($jsonfile) não pode ser lido!" | slog 3
		return 1
	fi
	echo "$(<"$jsonfile")" | jq -e . >/dev/null 2>&1 || echo "${PIPESTATUS[1]}"
}

function create_volumes() {
	#recebe o caminho para o json com os dados dos volumes
	local -i retf="$1"
	local jsonfile="$2"
	local createLimit="$3"
	local -i ret_create_volumes volCount volIdx shareIdx volType
	local alias shares size primaryShareName

	ret_create_volumes=$(test_json "${jsonfile}")
	if [[ ret_create_volumes -ne 0 ]]; then
		echo "Parser do JSON com os dados dos volumes não poder ser lido( $ret_create_volumes )" | slog 3
		return "$ret_create_volumes"
	fi

	[ -z "$createLimit" ] && createLimit=1024
	[ "$createLimit" == "0" ] && createLimit=1024
	echo "Volumes limitados a ( $createLimit )" | slog 7
	volCount=$(jq "length" "$jsonfile")
	if [[ volCount -gt createLimit ]]; then
		volCount=$createLimit
	fi
	echo "Serão criados ( $volCount ) volumes" | slog 7
	for ((volIdx = 0; volIdx < volCount; volIdx++)); do
		alias=$(jq -r ".[$volIdx].alias" "$jsonfile")
		volType=$(jq -r ".[$volIdx].lv_type" "$jsonfile")
		shares=$(jq ".[$volIdx].shares" "$jsonfile")
		size=$(jq -r ".[$volIdx].size" "$jsonfile")
		primaryShareName=$(echo "$shares" | jq -r ".[0].name")
		echo "Volume Index<$((volIdx + 1))> - Volume alias<$alias> - Volume size<$size> - Volume type<$volType> Principal sharename<$primaryShareName>" | slog 7
		echo "Shares: $shares" | slog 7
		echo "Criando volume <$((volIdx + 1))>" | slog 7
		echo "Criando volume $((volIdx + 1))/${volCount}"
		create_vol "$alias" "$primaryShareName" "$size" "$volType"
		if [[ $? ]]; then
			shareCount=$(echo "$shares" | jq "length")
			if [[ shareCount -gt 1 ]]; then
				echo "Adicionando compartilhamentos secundários..." | slog 6
				for ((shareIdx = 1; shareIdx < shareCount; shareIdx++)); do #Salta o indice 0 por ter sido feito junto com volume acima
					secShareName=$(echo "$shares" | jq -r ".[$shareIdx].name")
					echo "Novo compartilhamento secundário: $secShareName"
					create_secondary_share ret_create_volumes "$secShareName" "$alias" #convert volumeID base 0 to 1
				done
			fi
		else
			echo "Erro criando volume $alias" | slog 2
		fi
	done
}

function checkTolerancePercent() {
	#Avalia se o valor de comparação está dentro do de referência +/- o percentul informado
	local reference=$1
	local compValue=$2
	local pmargin=$3 ## Deve ser valor inteiro entre 1 e 99
	maxV=$((reference + (pmargin * reference / 100)))
	minV=$((reference - (pmargin * reference / 100)))
	if [[ $compValue -gt $maxV ]]; then
		return 1
	elif [[ $compValue -lt $minV ]]; then
		return 1
	else
		return 0
	fi
}

function get_files_list_b3() {
	local path="$2"
	local fileExtension="$3"
	if ! collect=$(find "$path" -maxdepth 1 -printf "%f\n" 2>/dev/null); then #Versões do bash/find comportamentos distintos
		collect=$(find ./ -maxdepth 1 -print 2>/dev/null)
	fi
	if [ $? ]; then
		while IFS='' read -r line; do
			name="${line}" #name="${line#*.}"
			if [[ $name =~ .*\.$fileExtension ]]; then
				item="$(
					cd "$(dirname "$path/$name")" || exit
					pwd
				)/$(basename "$path/$name")" #test: linha original acima era -> cd "$(dirname "$path/$name")"
				G_RET_A+=("$item")
			fi
		done <<<"$collect"
	else
		slog 3 "Erro de coleta de arquivos - retorno inválido"
		G_RET_A=()
	fi
}

function slog() {
	#rotina de registro de logs
	local LEVEL="$1"
	shift
	if [[ ${GLOBAL_VERBOSE_LEVEL} -ge ${LEVEL} ]]; then
		if [ -t 0 ]; then
			echo "[${LOG_LEVELS[$LEVEL]}]" "$@" | tee -a "$GLOBAL_LOG_FILE"
		else
			if [[ $1 ]]; then
				echo "[${LOG_LEVELS[$LEVEL]}] $1" | tee -a "$GLOBAL_LOG_FILE"
			else
				echo "[${LOG_LEVELS[$LEVEL]}] $(cat)" | tee -a "$GLOBAL_LOG_FILE"
			fi
		fi
	fi
}

function get_abs_value() {
	#Calcula o valor absoluto datos o total e o percentual
	#Valores flutuantes com ponto como separador
	pool_size="${1}"
	vol_percent="${2}"
	awk "BEGIN {printf \"%d\",${pool_size}*${vol_percent}/100}" #Saida com inteiro livre
}

function truncToInt() {
	#trunca valor flututante para inteiro
	echo "${1%.*}"
}

function get_root_login() {
	#Passar texto plano para esta rotina de autenticação
	local login=$2
	local pwd=$3
	#Chamada para a autenticação do cliente na CLI
	qcli -l user="$login" pw="$pwd" saveauthsid=yes #* é gerado um sid aqui, talvez possa ser utils depois
	printf -v "$1" "%d" "$?"
}

function convertShortLongByteSize() {
	#Dada string "human-readble" de capacidade, converte para o valor inteiro correlato
	#exemplo "123.5 TB" --> 126.464.000.000.000
	#para rodar em bash 3, precisa-se dois vetores(complicou um pouco)
	SFX='YZEPTGMK'                  #Sufixos dos valoresy-yota, z-zeta, p-peta....k-kilo
	SFX_MULT=(24 21 18 15 21 9 6 3) #multiplicadores vinculados
	input=$(echo "$1" | tr -d ' 	') #trim spaces & tabs
	suffix="${input: -1}"           #last char, must be discard if "B"(ytes)
	length=${#input}
	if [[ "$suffix" == "B" ]]; then
		suffix="${input: -2:1}"
		number="${input:0:length-2}" #load values, ignore sufix(2 chars)
	else
		number="${input:0:length-1}" #load values, ignore sufix(1 char)
	fi
	pos=$(awk -v b="$suffix" -v a="$SFX" 'BEGIN{print index(a,b)}')
	num=$(awk "BEGIN {printf \"%f\",1024*${number}*(10 ^ ${SFX_MULT[${pos}]})}") #awk no qnap estoura para decimais -> usar float
	printf "%f\n" "${num}"
}

function get_pool_size() {
	#Devolve o tamanho do pool de armazenamento, dado o seu indice(os valores são 1 based). Caso argumento omitido, retorna o valor para o poolId=1
	local ret_get_pool_size
	local poolID="$2"
	if ! [ "$poolID" ]; then
		poolID=1
	fi
	slog 7 "Lendo tamanho do PoolID( $poolID )"
	ret_get_pool_size=$(qcli_pool -i poolID=${poolID} displayfield=Capacity | sed -n '$p')
	slog 7 "Valor bruto retornado: $ret_get_pool_size"
	printf -v "$1" "%s" "$ret_get_pool_size" #gambiarra de retorno para primeiro arg
}

function get_localId_class() {
	#Valida a entrada do identificador da unidade. Valor negativo -> invalido
	if [[ -z "${1}" ]]; then
		echo "0" #Valor indefinido ou todos
	else
		local localId=$(($1))                      #int -> without quotation marks
		if ((localId >= 1 && localId <= 79)); then #1 a 79 - por simplicidade neste momento. O real é um pouco diferente
			echo "1"
		elif ((localId >= APP_MIN_NVI_ID && localId <= APP_MAX_NVI_ID)); then #NVIs conhecidos
			echo "2"
		else # para todos os demais valores, erro
			echo "-1"
		fi
	fi
}

function get_pool_count() {
	local -i ret_get_pool_count
	ret_get_pool_count=$(qcli_pool -l | sed "2q;d")
	printf -v "$1" "%d" "$ret_get_pool_count"
}

function create_pool() {
	#Cria o pool de armazenamento. Sugestão de aguardar a ressincronização, como mostrado no link abaixo
	#https://forum.qnap.com/viewtopic.php?t=137370
	local retf="$1"
	local -i pc
	get_pool_count pc
	if [[ pc -eq 0 ]]; then
		echo "Pool de armazenamento não encontrado. Um novo será criado"
		echo "Esta operação pode demorar alguns minutos..."
		#Parece boa pática por um thresohold. Pendente forma de especificar o valor para o "instantaneo"
		qcli_pool -c diskID=00000001,00000002 raidLevel=1 Stripe=Disabled | slog 6
		retf=$?
		if [ $retf -eq 0 ] && [ "$APP_POOL_THRESHOLD" -ne 0 ]; then
			qcli_pool -t poolID=1 threshold="$APP_POOL_THRESHOLD"
		else
			echo "Falha criação de pool de armazenamento"
		fi
	else
		echo "Discos já fazem parte de um pool de armazenamento." | slog 6
		retf=0
	fi
	printf -v "$1" "%d" "$retf"
}

function get_volume_id_by_alias() {
	#Assume que o poolID existe
	local diskID=1 #00000001 eg
	local poolID=1 #Assumido por ser único
	local retf="$1"
	local alias=$2
	local response volCount volTable line ret_check_vol

	response=$(qcli_volume -i displayfield=Alias,volumeID)
	volCount=$(echo "$response" | sed -n "2p")
	retf=0 #não encontrado
	if [[ $volCount -gt 0 ]]; then
		volTable=$(tail -n +4 <<<"$response") #pula resumo e cabeçalho da saida
		declare -a entries
		while IFS='' read -r line; do
			entries+=("$line")
		done <<<"$volTable"

		for line in "${entries[@]}"; do
			if [[ "$line" == "$alias "* ]]; then #encontrado no começo da cadeia(nota para o espaço ao final como separador)
				IFS="$(printf '\t ')" read -r -a parts <<<"$line"
				retf="${parts[1]}"
				break
			fi
		done
	fi
	printf -v "$1" "%d" "$retf"
}

function check_vol() {
	#Assume que o poolID existe
	local diskID=1 #00000001 eg
	local poolID=1 #Assumido por ser único
	local alias=$2
	local sharename=$3
	local volSize=$4 #180388626432 eg sistema

	local response volCount volTable line ret_check_vol

	response=$(qcli_volume -i displayfield=Alias,volumeID,Capacity,Status)

	ret_check_vol=$VOLUME_INEXISTS #resultado default
	volCount=$(echo "$response" | sed -n "2p")
	if [[ $volCount -le 0 ]]; then
		echo "Pool não possui nenhum volume ainda"
	else
		volTable=$(tail -n +4 <<<"$response") #pula resumo e cabeçalho da saida
		declare -a entries
		while IFS='' read -r line; do
			entries+=("$line")
		done <<<"$volTable"

		for line in "${entries[@]}"; do
			if [[ "$line" == "$alias "* ]]; then #encontrado no começo da cadeia(nota para o espaço ao final como separador)
				slog 7 "Alias encontrado($alias)"
				IFS="$(printf '\t ')" read -r -a parts <<<"$line"
				declare mant=0
				declare bexp=''
				convertLongShortByteSize mant bexp "$volSize"
				if [[ "${parts[3]}" == "$bexp" ]]; then
					checkTolerancePercent "$mant" "${parts[2]}" "5" #cinco e meio porcento
					if [ $? ]; then
						ret_check_vol=$VOLUME_OK #Saida do caminho feliz
					else
						slog 7 "Erro/Tolerância de volume ultrapassado (${parts[1]}) ($mant)"
						ret_check_vol=$VOLUME_DIVERGENT
					fi
				else
					slog 7 "Grandezas divergentes (${parts[2]}) ($bexp)"
					ret_check_vol=$VOLUME_DIVERGENT
				fi
				break
			fi
		done
	fi
	printf -v "$1" "%d" "$ret_check_vol"
}

function get_is_volume_ready() {
	local targetVolID=$2
	local response volTable line
	local -i ret_is_volume_ready=1 #Default é falha de volume

	response=$(qcli_volume -i volumeID="$targetVolID" displayfield=Alias,volumeID,Capacity,Status)
	volTable=$(tail -n +4 <<<"$response") #pula resumo e cabeçalho da saida
	declare -a entries
	while IFS='' read -r line; do
		entries+=("$line")
	done <<<"$volTable"

	for line in "${entries[@]}"; do
		IFS=' ' read -r -a parts <<<"$line"
		if [[ "${parts[1]}" == "$targetVolID" ]]; then #encontrado no começo da cadeia
			if [[ "${parts[4]}" == "Ready" ]]; then       #*Assinatura que o volume está OK!
				ret_is_volume_ready=0
			fi
			break
		fi
	done
	printf -v "$1" "%d" "$ret_is_volume_ready"
}

function wait_volume_ready() {
	local targetVolID=$2
	local -i ret_wait_volume_ready=1 #Assume falha inicial
	if [[ $TEST_VALUE_ALL_VOLUMES_OK ]]; then
		ret_wait_volume_ready=0 #Encutar o teste
	else
		local -i retries=0
		while [[ $ret_wait_volume_ready -ne 0 ]]; do #Equivale a 10 minutos(magic number here)
			get_is_volume_ready ret_wait_volume_ready "$targetVolID"
			echo -n '#'
			sleep "$APP_MIN_TIME_SLICE"
			((retries++))
			if [[ $retries -gt 120 ]]; then
				echo "Finalização do volume ${targetVolID} está demorando. Sugerimos aguardar um pouco mais."
				local promptAnswer
				get_prompt_confirmation promptAnswer "Deseja aguardar mais algum tempo(S/N)?" 'SN'
				if [[ 'Ss' == *"$promptAnswer"* ]]; then
					retries=0
				fi
			fi
		done
		echo '.'
		if [[ $ret_wait_volume_ready ]]; then
			echo "Volume(#$targetVolID) pronto!" | slog 5
		else
			echo "Volume(#$targetVolID) falhou em preparação !!!" | slog 3
		fi
	fi
	printf -v "$1" "%d" "$ret_wait_volume_ready"
}

function create_vol() {
	local diskID=1 #00000001 eg
	local poolID=1 #Assumido por ser único
	local alias=$1
	local sharename=$2
	local volSize=$3 #180388626432 eg sistema
	local volType=$4 #lv_type={1|2|3} 1:thin 2:thick 3:static

	local -i ret_create_vol=0 #Valor padrão(sucesso)
	check_vol ret_create_vol "$alias" "$sharename" "$volSize"
	if [[ $ret_create_vol -eq $VOLUME_INEXISTS ]]; then
		slog 5 "Criando o volume($alias), favor aguarde..."
		local cmdOut
		cmdOut=$(qcli_volume -c Alias="$alias" diskID="$diskID" SSDCache=no Threshold="$APP_VOLUME_THRESHOLD" \
			sharename="$sharename" encrypt=no lv_type="$volType" poolID="$poolID" raidLevel=1 \
			Capacity="$volSize" Stripe=Disabled)
		ret_create_vol=$?
		if [[ $ret_create_vol ]]; then
			local targetVolID
			targetVolID=$(echo "$cmdOut" | head -1 | awk '{print $NF}' | tr -d .)
			echo "Aguardando o volume( $targetVolID ) ficar pronto..."
			wait_volume_ready ret_create_vol "$targetVolID"
		fi

		if [[ $ret_create_vol ]]; then
			slog 5 "Volume $alias (ID=$targetVolID) criado com sucesso!"
		else
			echo "Erro fatal criando volume($alias = $targetVolID). Abortando processo..."
			return $ret_create_vol #*DEVE se rvalor abaixo de 10
		fi
	else
		if [[ $ret_create_vol -eq $VOLUME_DIVERGENT ]]; then
			slog 3 "Volume com características divergentes foi encontrado!!"
			return $VOLUME_DIVERGENT
		else #VOLUME_OK
			echo "Volume ($alias) com $volSize bytes de tamanho já existe." | slog 6
		fi
	fi
}

function convertLongShortByteSize() {
	#$1 = retorno da mantissa do tamanho
	#$2 = retorno do expoente em 'X'B
	local size="$3"      #Valor inteiro grande a ser convertido para a forma curta
	local precision="$4" #Quantidade de dígitos( 0 a 2 aceitos) - opcional
	local base="$5"      #Base de conversão(1000 ou 1024 aceitos) - opcional
	if ! [[ $precision ]]; then
		precision=2
	fi
	if ! [[ $base ]]; then
		base=1024
		factor=1000
	elif ! [ $base == 1000 ]; then
		factor=1024
	fi
	declare -a grade=('' K M G T P E Z Y)
	declare suffix="${grade[0]}B"
	for ((i = 0; i <= 8; i++)); do
		factor=$((factor * (base ** i)))
		q=$((size / factor))
		if [[ q -le 999 ]]; then
			suffix="${grade[${i} + 1]}B"
			printf -v "$2" "%s" "$suffix" #retorno expoente
			#qts 5.1 sem bc, se vira com awk
			out=$(awk -v size="$size" -v factor="$factor" -v CONVFMT=%.17g "BEGIN{ print (1000*size/factor) }")
			printf -v "$1" "%.0f" "$out" #retorno mantissa
			break
		fi
	done
}

function is_package_installed() {
	local pkgName="$1"
	local pkgStatus qpkg_success
	qpkg_success="[CLI] QPKG $pkgName is installed"
	pkgStatus=$(qpkg_cli -s "$pkgName")
	if [[ "$qpkg_success" == "$pkgStatus" ]]; then
		echo 0
	else
		#echo "Current status = $pkgStatus" >&2
		echo 1
	fi
	unset pkgStatus
}

function install_package() {
	local pkgName="$2"
	local ret_install_package=0 #Assume sucesso
	local -i retries=0
	local pkgStatus=''
	if [[ $(is_package_installed "$pkgName" "$pkgStatus") -ne 0 ]]; then
		pkgStatus=$(qpkg_cli -a "$pkgName") #inicia processo de instalação do pacote
		echo "$pkgStatus" | slog 6
		if ! [[ $APP_IS_DEV_ENV ]]; then
			sleep 10
		else
			sleep 1
		fi
		while [[ "$(is_package_installed "$pkgName" "$pkgStatus")" -ne "0" ]]; do
			local oldStatus="$pkgStatus"
			pkgStatus=$(qpkg_cli -s "$pkgName")
			if [[ "$oldStatus" != "$pkgStatus" ]]; then
				echo "$pkgStatus"
				oldStatus="$pkgStatus"
			fi
			((retries++))
			if [[ $retries -gt 60 ]]; then
				echo "Estouro do tempo de espera para o processo de instalação"
				local promptAnswer
				get_prompt_confirmation promptAnswer "Deseja aguardar mais algum tempo(S/N)?" 'SN'
				if [[ 'Ss' == *"$promptAnswer"* ]]; then
					retries=0 #comecar de novo
				else
					ret_install_package=1 #flag de falha
					echo "Instalação de ($pkgName) abortada pelo usuário.!!!" | slog 3
					break
				fi
			fi
			if ! [[ $APP_IS_DEV_ENV ]]; then
				sleep 5
			else
				sleep 1
			fi
		done
	else
		echo "Pacote $pkgName já está instalado" | slog 5
	fi
	printf -v "$1" "%d" $ret_install_package
}

function get_primary_group() {
	local localID=$2
	local ret_primary_group
	if ((1 <= localID && localID <= 77)); then
		ret_primary_group="setorGzon${localID}"
	elif ((APP_MIN_NVI_ID <= localID && localID <= APP_MAX_NVI_ID)); then
		ret_primary_group="setorGNVI${APP_NVI_MAPPING[((localID - 201))]}"
	fi
	printf -v "$1" "%s" "$ret_primary_group"
}

function authenticate_session() {
	#Esse While serve para um tratamento de erro, ao verificar que o comando não teve sucesso ele solicita o usuário e senha novamente
	local -i ret_authenticate_session=1 #Gera erro para entrada do loop(until para bash daria na mesma)

	while [ $ret_authenticate_session != 0 ]; do
		if [[ -n "${APP_NAS_ADM_ACCOUNT}" && -n "${APP_NAS_ADM_ACCOUNT_PWD}" ]]; then
			#Tenta validar com os valores preexistentes
			get_root_login ret_authenticate_session "${APP_NAS_ADM_ACCOUNT}" "${APP_NAS_ADM_ACCOUNT_PWD}"
			if [[ $ret_authenticate_session == 0 ]]; then
				break
			fi
		fi
		echo -n "Login(ADM) do NAS: "
		read -r APP_NAS_ADM_ACCOUNT
		if [ -n "${APP_NAS_ADM_ACCOUNT}" ]; then
			echo -n "Senha para(\"${APP_NAS_ADM_ACCOUNT}\"): "
			read -ers APP_NAS_ADM_ACCOUNT_PWD
			echo
			if [ -n "${APP_NAS_ADM_ACCOUNT_PWD}" ]; then
				get_root_login ret_authenticate_session "${APP_NAS_ADM_ACCOUNT}" "${APP_NAS_ADM_ACCOUNT_PWD}"
				if [[ $ret_authenticate_session -ne 0 ]]; then
					#Reseta valores anteriores(indiferente da origem)
					APP_NAS_ADM_ACCOUNT=''
					APP_NAS_ADM_ACCOUNT_PWD=''
					echo "Credenciais inválidas!" | slog 6
				fi
			else
				echo "Senha nula, inválida"
			fi
		else
			echo "Login nulo, inválido"
		fi
	done
	slog 5 "Autenticacao feita com sucesso"
	printf -v "$1" "%d" "$ret_authenticate_session"
}

function process_env() {
	#Realiza o processamento da carga dos arquivos .env referenciados pelaenv:APP_ENVS na ordem inversa de aparecimento, localizados no caminho dado por $!
	#Caso $1 seja nulo, o diretório corrente é usado
	local rootpath="$1"
	shift
	local envName="$1"
	if [[ -n "${envName}" ]]; then
		envSuffix=".$(echo "$envName" | tr '[:upper:]' '[:lower:]')"
		if [[ "${envSuffix}" == *'.prod'* ]]; then
			envSuffix=''
		fi
	else
		envSuffix=''
	fi
	if [[ -z "${rootpath}" ]]; then
		rootpath=${PWD}
	fi
	echo "Procurando envfiles em \"$rootpath\"..." | slog 7
	local -a parts
	if [[ -n "${APP_ENVS}" ]]; then
		local noQuotes
		noQuotes="${APP_ENVS//\'/}" #! Como remover caracter (') foi complicado !PQP!
		IFS=":" read -r -a parts <<<"$noQuotes"
	else
		parts=('.env' '.secret') #* entradas padrões para o caso de nenhum ser informada
		echo "Buscando envFiles padrões(.env+.secret)" | slog 7
	fi
	local -i i
	for ((i = ${#parts[@]} - 1; i >= 0; i--)); do
		local envFile
		if [[ "${parts[$i]%%/}" == $"."* ]]; then
			#* começando com . -> nome original
			envFile="${rootpath%%/}/${parts[$i]%%/}"
		else
			#* sem começar com , -> garante extensão esperada
			if [[ "${parts[$i]%%/}" == *'.env' ]]; then
				envFile="${rootpath%%/}/${parts[$i]}"
			else
				envFile="${rootpath%%/}/${parts[$i]}.env"
			fi
		fi
		# if [[ "${parts[$i]%%/}" == "." ]]; then
		# 	envFile="${rootpath%%/}/.env"
		# else
		# 	envFile="${rootpath%%/}/${parts[$i]}.env"
		# fi
		loadEnv "${envFile}${envSuffix}"
	done
}

function loadEnv() {
	echo "Carregando env: $1 ..." | slog 7
	if [ -r "$1" ]; then
		chmod +x "$1"
		set -o allexport
		#shellcheck source=/dev/null
		source "$1"
		set +o allexport
	else
		echo "Arquivo \"$1\" não pode ser lido" | slog 5
	fi
}

function debug_show_vars() {
	#env -0 | sort -z | tr '\0' '\n' | grep -E "^APP_|^GLOBAL_|^TEST_"  #!bash > 4
	env | sort -f | tr '\0' '\n' | grep -E "^APP_|^GLOBAL_|^TEST_"

	#Show .env mapping to units groups
	#echo "Mapeamento: ${#APP_NVI_MAPPING[@]} elementos"
	#echo "Mapeamento: ${APP_NVI_MAPPING[3]} exemplos"
}

function set_extra_settings() {
	echo "Desativando Horário de Verão" | slog 6
	setcfg system 'enable daylight saving time' FALSE
	if [[ $? ]]; then
		echo "Horário de verão ajustado com sucesso!" | slog 6
	else
		echo "Falha ajustando o horário de verão" | slog 3
	fi
	echo "Configurando Data e hora"
	qcli_timezone -s timezone=17 dateformat=1 timeformat=24 timesetting=2 server="${APP_NTP_SERVER}" interval_type=2 timeinterval=7 AMPM_option=PM
}

function get_volume_config_file() {
	#echo "${PWD%%/}/volumes.json"
	echo "${APP_LIB_DIR}/volumes.json"
}

function first_network_setup() {
	#!<01> Em versão não homologada havia alinha abaixo. Não encontrada documentação a respeito da chamada
	local -i ret
	network_boot_rescan
	ret=$?
	if ! [[ $ret ]]; then
		echo "Retorno do rescan de rede: ${ret}"
	fi

	#todo: Validar alterações globais para a inserção sem erros no domínio
	setcfg "Network" "Domain Name Server 1" "${APP_DNS1}"
	setcfg "Network" "Domain Name Server 2" "${APP_DNS2}"
	setcfg "Network" "DNS type" manual
	setcfg "Samba" "DC List" "${APP_DC_PRIMARY_NAME},${APP_DC_SECONDARY_NAME}"
	setcfg "Samba" "User" "${APP_DOMAIN_ADM_ACCOUNT}" #!Usar apenas o nome sem o dominio

	echo "Realizando ajustes de rede..."

	#Aqui inicia seção de alterações, como esperado, sem documentação...
	#Pelos foruns /etc/config/nm.conf são configurações remontadas a cada boot

	#este mesmo valor indiferentemente
	setcfg -f /mnt/HDA_ROOT/.config/nm.conf global "current_default_gateway" interface0
	setcfg -f /etc/config/nm.conf global "current_default_gateway" interface0

	setcfg -f /mnt/HDA_ROOT/.config/nm.conf global "gateway_policy" 2 #original 1
	setcfg -f /etc/config/nm.conf global "gateway_policy" 2           #original 1

	setcfg -f /mnt/HDA_ROOT/.config/nm.conf global "disable_dw_updater" 0 #indiferentemente sempre 0
	setcfg -f /etc/config/nm.conf global "disable_dw_updater" 0

	setcfg -f /mnt/HDA_ROOT/.config/nm.conf global "dns_strict_order" 1 #original 0
	setcfg -f /etc/config/nm.conf global "dns_strict_order" 1           #original 0

	setcfg -f /mnt/HDA_ROOT/.config/nm.conf global "fixed_gateway1" interface0 #Originalmente nulo
	setcfg -f /etc/config/nm.conf global "fixed_gateway1" interface0

	#Alterações pendentes de testes
	setcfg "System" "Workgroup" "${APP_NAS_NETBIOS_DOMAIN}"
	setcfg "System" "Server Name" "${APP_NAS_HOSTNAME}"

	#todo:extras: Outras entradas divergentes para acesso ao dominio coletadas da referencia manual
	rm /etc/resolv.dnsmasq
	echo "nameserver ${APP_DNS1}" >/etc/resolv.dnsmasq
	echo "nameserver ${APP_DNS2}" >>/etc/resolv.dnsmasq

	#* 1 - D:\Sw\WD\Operations\qnap-config\tmp\new.pos-domain\etc\etc\resolv.dnsmasq com as primeiras linnhas como o modelo abaixo:
	# nameserver 10.12.0.134
	# nameserver 10.12.0.228
	# nameserver 10.12.1.18@eth0
	# nameserver 10.12.1.148@eth0
	#* 1.1 - Opcionalmente eliminar as citadas pela configuração via dhcp

	#* 2 - SNMP
	# Em \mnt\HDA_ROOT\.config\snmpd.conf, seguem as linhas, onde as duas primeiras são alvos de alteração
	# sysName ZPB205NAS01 (*alteração aqui*)
	# syscontact louis@celab1.ee.ntou.edu.tw
	# syslocation keelung
	# rwcommunity public
	# rocommunity public

	#!<02> Em versão não homologada havia alinha abaixo. Idem ao caso <01>
	network_boot_rescan

	echo 'Reiniciando serviços de rede...' | slog 6
	if ! [[ $APP_IS_DEV_ENV ]]; then
		/etc/init.d/network.sh restart | slog 6
	else
		echo "Serviços de rede não reinciados pelo modo de depuração ativo!!!!!!!!!!"
	fi
	printf -v "$1" "%d" "0" #Sem captura de erro possível aqui :-(
}

function ProgressBar() {
	((currentState = $1))
	((totalState = $2))
	_progress=$((currentState * 100 / totalState))
	((_done = $(((_progress * 4))) / 10))
	((_left = 40 - _done))
	# Build progressbar string lengths
	_done=$(printf "%${_done}s")
	_left=$(printf "%${_left}s")
	printf "\rProgresso : [${_done// /#}${_left// /-}] ${_progress}%%"
}

function wait_resync() {
	local -i _wait_resync
	SECONDS=0
	if [[ "$APP_SKIP_POOL_RESYNC" -eq "1" ]]; then
		echo "Espera de resincronização do pool ignorada pela configuração do ambiente." | slog 6
		_wait_resync=0
	else
		if [[ APP_IS_DEV_ENV -ne 0 ]]; then
			[ "$TEST_VALUE_RESYNC_OK" == "1" ] && _wait_resync=0 || _wait_resync=1 #Teste se pula a espera(apenas no modo DEV)
			progressFile="$PWD/debug/sync_completed.txt"
		else
			#todo:future: Melhorar captura do caminho do arquivo de progresso
			progressFile=/sys/block/md1/md/sync_completed
		fi

		if [ "$_wait_resync" -eq "0" ]; then
			echo "Espera simulada bypassed(env:TEST_VALUE_RESYNC_OK)" | slog 7
		else
			echo "Aguarde a resincronização do RAID-1."
			echo "Tal processo levará algumas horas. Sugerimos fazer outra coisa por enquanto!"
			if [ -r "$progressFile" ]; then
				./adjust_sync_speed.sh 0 #Aumenta a prioridade da sincronização
				while true; do
					local -a parts
					content=$(tr <"$progressFile" '[:upper:]' '[:lower:]')
					if [[ "$content" == 'none' ]]; then
						_wait_resync=0
						break
					else
						IFS='/' read -r -a parts <<<"$content"
						if [[ "${#parts[@]}" -ne 2 ]]; then
							break
						else
							current="${parts[0]}"
							total="${parts[1]}"
							ProgressBar "$current" "$total"
						fi
					fi
					sleep $((5 * APP_MIN_TIME_SLICE))
				done
				./adjust_sync_speed.sh 1
			else
				echo "Arquivo com informações de progresso não podem ser lidas($progressFile)"
			fi
		fi
	fi
	ProgressBar "100" "100"
	echo
	echo "DURAÇÃO DA SINCRONIZAÇÃO = $((SECONDS / 3600))h $(((SECONDS / 60) % 60))m $((SECONDS % 60))s"
	printf -v "$1" "%d" "$_wait_resync"
}

function test_domain() {
	local retf="$1"
	local _retries="$2"
	local content match
	for ((i = 0; i < _retries; i++)); do
		content=$(tr '[:lower:]' '[:upper:]' <<<"$(qcli_domainsecurity -A)")
		match=$(tr '[:lower:]' '[:upper:]' <<<"$APP_NAS_DOMAIN")
		if [[ $content == *"$match"* ]]; then
			echo "Dispositivo já se encontra no domínio($APP_NAS_DOMAIN)" | slog 7
			retf=0
			break
		else
			echo -e "Resposta de consulta de união ao dominio = \n$content" | slog 7
			retf=1
		fi
		sleep "$APP_MIN_TIME_SLICE"
	done
	printf -v "$1" "%d" "$retf"
}

function join_to_domain() {
	local -i _success="$1"
	local -i ret=1
	local -i retries
	local result

	#Ajuste das permissões do samba
	setcfg Samba 'DC List' "$APP_DC_PRIMARY_NAME,$APP_DC_SECONDARY_NAME"
	setcfg Network 'Domain Name Server 2' "$APP_DNS2"
	setcfg Network 'Domain Name Server' "$APP_DNS1"
	setcfg Network 'Domain Name Server 1' "$APP_DNS1"
	setcfg -f /etc/config/nm.conf global 'domain_name_server_1' "$APP_DNS1"
	setcfg -f /etc/config/nm.conf global 'domain_name_server' "$APP_DNS1"
	setcfg -f /etc/config/nm.conf global 'domain_name_server_2' "$APP_DNS2"

	#! para qcli_domainsecurity o argumento -m
	#!foi usado ao invés do argumento -q como no caso abaixo(remover comentario após elucidação de motivos)
	echo 'Ajustando as configurações do domínio.'
	echo 'Aguarde alguns minutos...'
	test_domain ret 1
	local upperNETBIOS
	upperNETBIOS=$(echo "$APP_NAS_NETBIOS_DOMAIN" | tr '[:lower:]' '[:upper:]')
	until [[ $ret -eq 0 ]]; do
		#! ERA ip="$APP_DNS1" ABAIXO
		# result=$(qcli_domainsecurity -q domain="$APP_NAS_DOMAIN" \
		# 	NetBIOS="$upperNETBIOS" dns_mode=manual ip="$APP_DNS1" ip="$APP_DNS2" \
		# 	domaincontroller="$APP_DC_PRIMARY_NAME" \
		# 	username="$APP_DOMAIN_ADM_ACCOUNT" password="$APP_DOMAIN_ADM_ACCOUNT_PWD")
		result=$(qcli_domainsecurity -m domain="$APP_NAS_DOMAIN" \
			NetBIOS="$upperNETBIOS" AD_server="$APP_DC_PRIMARY_NAME" \
			username="$APP_DOMAIN_ADM_ACCOUNT" password="$APP_DOMAIN_ADM_ACCOUNT_PWD" description="$APP_NAS_HOSTNAME")
		ret=$?
		echo "Retorno da chamada(exit_code=$ret) de união ao domínio = $result" | slog 7
		sleep "$APP_MIN_TIME_SLICE"
		test_domain ret 1
		retries=0
		while [[ $ret -ne 0 ]]; do
			((retries++))
			echo "Tentativa($retries) de ingresso no domínio falhou."
			echo 'Informe as credenciais novamente'
			read -p 'Digite a conta ADM do Dominio:' -r APP_DOMAIN_ADM_ACCOUNT
			read -p "Digite a senha para $APP_NAS_NETBIOS_DOMAIN\\$APP_DOMAIN_ADM_ACCOUNT:" -ers APP_DOMAIN_ADM_ACCOUNT_PWD
			#Nova tentativa com as novas credenciais
			# qcli_domainsecurity -q domain="$APP_NAS_DOMAIN" \
			# 	NetBIOS="$APP_NAS_NETBIOS_DOMAIN" dns_mode=manual \
			# 	ip="$APP_DNS1" domaincontroller="$APP_DC_PRIMARY_NAME" \
			# 	username="$APP_DOMAIN_ADM_ACCOUNT" password="$APP_DOMAIN_ADM_ACCOUNT_PWD"
			result=$(qcli_domainsecurity -m domain="$APP_NAS_DOMAIN" \
				NetBIOS="$upperNETBIOS" AD_server="$APP_DC_PRIMARY_NAME" \
				username="$APP_DOMAIN_ADM_ACCOUNT" password="$APP_DOMAIN_ADM_ACCOUNT_PWD" description="$APP_NAS_HOSTNAME")
			ret=$?
			echo "Chamada repetida a qcli_domainsecurity com retorno: $ret" | slog 7
		done
		test_domain ret 1 #nova rodada
	done

	echo "Entrou no domínio corretamente" | slog 5
	echo 'aguardando sincronização DCs...'
	sleep 15
	printf -v "$1" "%d" "$ret"
}

function config_snmp() {
	local ret="$1"
	setcfg SNMP 'Service Enable' TRUE
	setcfg SNMP 'Listen Port' 161
	setcfg SNMP 'Trap Community'
	setcfg SNMP 'Event Mask 1' 7
	setcfg SNMP 'Trap Host 1' "$APP_SNMP_SERVER1"
	setcfg SNMP 'Event Mask 2' 7
	setcfg SNMP 'Trap Host 2' "$APP_SNMP_SERVER2"
	setcfg SNMP 'Event Mask 3' 7
	setcfg SNMP 'Trap Host 3' #Originalmente esta linha(meio sem sentido)
	setcfg SNMP 'Version' 3
	setcfg SNMP 'Auth Type' 0
	setcfg SNMP 'Auth Protocol' 0
	setcfg SNMP 'Priv Protocol' 0
	setcfg SNMP 'User' "$APP_MONITOR_USER"
	setcfg SNMP 'Auth Key' #todo: valores a serem coletados e ainda desconhecidos
	setcfg SNMP 'Priv Key' #todo: idem acima
	printf -v "$1" "%d" "0"
}

function set_shares_permissions() {
	local -i ret="$1"
	local -i localID="$2"

	#todo:future: Implementar sub-rotina para exibir entrada e tratar os erros das chamadas a qcli_sharedfolder

	upperNETBIOS=$(echo "$APP_NAS_NETBIOS_DOMAIN" | tr '[:lower:]' '[:upper:]')

	#todo:urgent: Setar atributos dos compartilhamentos, inclusive o do sistema para conteudo abaixo
	# qcli_sharedfolder sharename=*** -p WinACLEnabled=1 -e RecycleBinEnable=0
	echo "Ajustando habilitação da WinACL e Lixeira..."
	qcli_sharedfolder sharename=publico -p WinACLEnabled=1 -e RecycleBinEnable=0 | slog 6
	qcli_sharedfolder sharename=restrito -p WinACLEnabled=1 -e RecycleBinEnable=0 | slog 6
	qcli_sharedfolder sharename=critico -p WinACLEnabled=1 -e RecycleBinEnable=0 | slog 6
	qcli_sharedfolder sharename=suporte -p WinACLEnabled=1 -e RecycleBinEnable=0 | slog 6
	qcli_sharedfolder sharename=espelho -p WinACLEnabled=1 -e RecycleBinEnable=0 | slog 6

	echo "Ajustando permissões para o local $localID ..."

	qcli_sharedfolder -B sharename=publico domain_grouprw="$upperNETBIOS\\G_SEINF_ADMINS" | slog 6
	qcli_sharedfolder -B sharename=restrito domain_grouprw="$upperNETBIOS\\G_SEINF_ADMINS" | slog 6
	qcli_sharedfolder -B sharename=critico domain_grouprw="$upperNETBIOS\\G_SEINF_ADMINS" | slog 6
	qcli_sharedfolder -B sharename=suporte domain_grouprw="$upperNETBIOS\\G_SEINF_ADMINS" | slog 6
	qcli_sharedfolder -B sharename=espelho domain_grouprw="$upperNETBIOS\\G_SEINF_ADMINS" | slog 6

	qcli_sharedfolder -B sharename=publico domain_grouprw="$upperNETBIOS\\G_SESOP_ADMINS" | slog 6
	qcli_sharedfolder -B sharename=restrito domain_grouprw="$upperNETBIOS\\G_SESOP_ADMINS" | slog 6
	qcli_sharedfolder -B sharename=critico domain_grouprw="$upperNETBIOS\\G_SESOP_ADMINS" | slog 6
	qcli_sharedfolder -B sharename=suporte domain_grouprw="$upperNETBIOS\\G_SESOP_ADMINS" | slog 6
	qcli_sharedfolder -B sharename=espelho domain_grouprw="$upperNETBIOS\\G_SESOP_ADMINS" | slog 6

	qcli_sharedfolder -B sharename=suporte domain_grouprd="$upperNETBIOS\\G_SIS_ADMINS" | slog 6

	qcli_sharedfolder -B sharename=publico domain_grouprw="$upperNETBIOS\\setorGsesop" | slog 6
	qcli_sharedfolder -B sharename=restrito domain_grouprw="$upperNETBIOS\\setorGsesop" | slog 6
	qcli_sharedfolder -B sharename=critico domain_grouprw="$upperNETBIOS\\setorGsesop" | slog 6
	qcli_sharedfolder -B sharename=suporte domain_grouprw="$upperNETBIOS\\setorGsesop" | slog 6
	qcli_sharedfolder -B sharename=espelho domain_grouprw="$upperNETBIOS\\setorGsesop" | slog 6

	qcli_sharedfolder -B sharename=publico domain_grouprd="$upperNETBIOS\\Domain Users" | slog 6
	qcli_sharedfolder -B sharename=entrada domain_grouprw="$upperNETBIOS\\Domain Users" | slog 6

	local primaryGroup
	get_primary_group primaryGroup "$localID"

	qcli_sharedfolder -B sharename=publico domain_grouprw="$upperNETBIOS\\$primaryGroup" | slog 6
	qcli_sharedfolder -B sharename=restrito domain_grouprw="$upperNETBIOS\\$primaryGroup" | slog 6
	qcli_sharedfolder -B sharename=critico domain_grouprw="$upperNETBIOS\\$primaryGroup" | slog 6
	qcli_sharedfolder -B sharename=suporte domain_grouprd="$upperNETBIOS\\$primaryGroup" | slog 6
	qcli_sharedfolder -B sharename=espelho domain_grouprd="$upperNETBIOS\\$primaryGroup" | slog 6

}
