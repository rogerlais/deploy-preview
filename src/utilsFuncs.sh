#!/bin/bash

#todo a ser implementado - se der tempo...
#hdparm -I /dev/sda para pegar atributos do disco

# set verbose level to info
__VERBOSE=7                 #Nível de verbosidade mínimo para registro
__LOG_FILE="/tmp/roger.log" #Local para saída dos logs
__IS_DEBUG=0                #Global para identificar se roda como depuração
__IS_DEV_ENV=0              #Global para usar dados simulados

declare -a LOG_LEVELS
# https://en.wikipedia.org/wiki/Syslog#Severity_level
LOG_LEVELS=([0]="emerg" [1]="alert" [2]="crit" [3]="err" [4]="warning" [5]="notice" [6]="info" [7]="debug")
declare VOLUME_INEXISTS=10
declare VOLUME_OK=0
declare VOLUME_DIVERGENT=20

GLOBAL_VERSION=1
# alias      sharename  volume_size
# shellcheck disable=SC2034
VOLUME_DATA=$(
	cat <<-END
		[
		  {
		    "alias": "sistema",
		    "shares": [{ "name": "sistema" }],
		    "size": "90194313216",
		    "version": "${GLOBAL_VERSION}"
		  },
		  {
		    "alias": "critico",
		    "shares": [{ "name": "critico" }],
		    "size": "5368709120",
		    "version": "${GLOBAL_VERSION}"
		  },
		  {
		    "alias": "outros",
		    "shares": [
		      { "name": "suporte" },
		      { "name": "espelho" }
		    ],
		    "size": "214748364800",
		    "version": "${GLOBAL_VERSION}"
		  },
		  {
		    "alias": "entrada",
		    "shares": [{ "name": "entrada" }],
		    "size": "53687091200",
		    "version": "${GLOBAL_VERSION}"
		  },
		  {
		    "alias": "publico",
		    "shares": [{ "name": "publico" }],
		    "size": "53687091200",
		    "version": "${GLOBAL_VERSION}"
		  },
		  {
		    "alias": "restrito",
		    "shares": [{ "name": "restrito" }],
		    "size": "214748364800",
		    "version": "${GLOBAL_VERSION}"
		  },
		  {
		    "alias": "backup",
		    "shares": [{ "name": "backup" }],
		    "size": "1000000000000",
		    "version": "${GLOBAL_VERSION}"
		  }
		]
	END
)

function switch_simulated_qcli() {
	# shellcheck source=/dev/null
	source "${PWD}/qcli_simulated.sh"
}

function create_secondary_share() {
	local ret_create_secondary_share=$1
	local sharename=$2
	local volID=$3
	local -i ret_create_secondary_share=0
	qcli_sharedfolder -i sharename="$sharename" &>/dev/null #Gera erro para sharename invalido
	if [[ $? ]]; then
		echo "Novo comparilhamento secundário em criação $sharename no volume $volID" | slog 6
		qcli_sharedfolder -s sharename="$sharename" volumeID="$volID" &>/dev/null #convert volumeID base 0 to 1
		#*saida comando acima abaixo reproduzida abaixo, omitida no console:
		#Please use qcli_sharedfolder -i, qcli_sharedfolder -u & qcli_sharedfolder -f to check status!
		ret_create_secondary_share=$?
	fi
	printf -v "$1" "%d" "$ret_create_secondary_share"
}

function test_json() {
	#todo levar para lib o teste de json( 0 - sucesso, 1 - falha, 4 - inválido)
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
	local jsonfile="$1"
	local -i ret_create_volumes volCount volIdx shareIdx
	local alias shares size primaryShareName

	ret_create_volumes=$(test_json "${jsonfile}")
	if [[ ret_create_volumes -ne 0 ]]; then
		echo "Parser do JSON com os dados dos volumes não poder ser lido( $ret_create_volumes )" | slog 3
		return "$ret_create_volumes"
	fi

	volCount=$(jq "length" "$jsonfile")
	for ((volIdx = 0; volIdx < volCount; volIdx++)); do
		alias=$(jq -r ".[$volIdx].alias" "$jsonfile")
		shares=$(jq ".[$volIdx].shares" "$jsonfile")
		size=$(jq -r ".[$volIdx].size" "$jsonfile")
		primaryShareName=$(echo "$shares" | jq -r ".[0].name")
		#todo repor logs abaixo
		# echo "Volume Index<$volIdx> - Volume alias<$alias> - Volume size<$size> - Principal sharename<$primaryShareName>" | slog 7
		# echo "Shares: $shares" | slog 7
		# echo "Criando volume <$volIdx>" | slog 7
		create_vol "$alias" "$primaryShareName" "$size"
		if [[ $? ]]; then
			shareCount=$(echo "$shares" | jq "length")
			if [[ shareCount -gt 1 ]]; then
				echo "Adicionando compartilhamentos secundários..." | slog 6
				for ((shareIdx = 1; shareIdx < shareCount; shareIdx++)); do #Salta o indice 0 por ter sido feito junto com volume acima
					secShareName=$(echo "$shares" | jq -r ".[$shareIdx].name")
					echo "Novo compartilhamento secundário: $secShareName"
					create_secondary_share ret_create_volumes "$secShareName" "$((volIdx + 1))" #convert volumeID base 0 to 1
				done
			fi
		else
			echo "Erro criando volume $alias" | slog 2
		fi
	done
	#todo Ao finalizar, repetir a saída de "qcli_volume -i" e esperar que os volumes sejam formatados
	#sample = watch -g -n 5 'date +%H:%M'
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
	if [[ ${__VERBOSE} -ge ${LEVEL} ]]; then
		if [ -t 0 ]; then
			echo "[${LOG_LEVELS[$LEVEL]}]" "$@" | tee -a "$__LOG_FILE"
		else
			if [[ $1 ]]; then
				echo "[${LOG_LEVELS[$LEVEL]}] $1" | tee -a "$__LOG_FILE"
			else
				echo "[${LOG_LEVELS[$LEVEL]}] $(cat)" | tee -a "$__LOG_FILE"
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
	#todo pode precisar de base de conversão mais aprimorada para 1024^n a 1024*(1000^(n-1))
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

function get_is_validZoneId() {
	#Valida a entrada do identificador da zona
	zoneID=$(($2)) #int -> without quotation marks
	case $zoneID in
	[1-9] | [1-7][0-9]) #1 a 79 - por simplicidade neste momento. O real é um pouco diferente
		echo -n " - Zonas normais"
		printf -v "$1" "%d" "0"
		;;      #set $? true=ok=0
	20[1-5]) #NVIs conhecidos
		echo -n " - NVIs"
		printf -v "$1" "%d" "0"
		;;
	*) # para todos os demais valores, erro
		echo "Valor inválido!"
		printf -v "$1" "%d" "1"
		;; #set $? true=false=1
	esac
}

function setDeviceName() {
	local newName="$1"
	curName=$(getcfg System 'Server Name')
	echo "Novo nome = $newName - Nome antigo = $curName"
	if [ "$newName" != "$curName" ]; then
		echo "Alterando o nome do dispositivo para $newName ..."
		setcfg System 'Server Name' "$newName" #* em testes, tal chamada aceita praticamente tudo sem gerar erro
		rc=$?
		if [[ $rc ]]; then
			echo "Nome do dispositivo alterado de $curName para $newName"
		else
			echo "Falha renomeando dispositivo - erro: $rc"
			return $rc
		fi
	else
		slog 6 "Nome atual já corretamente atribuído para: $newName"
	fi
}

function get_pool_count() {
	local -i ret_get_pool_count
	ret_get_pool_count=$(qcli_pool -l | sed "2q;d")
	printf -v "$1" "%d" "$ret_get_pool_count"
}

function create_pool() {
	declare pc
	get_pool_count pc
	if [[ pc -eq 0 ]]; then
		echo "Pool de armazenamento não encontrado. Um novo será criado"
		echo "Esta operação pode demorar alguns minutos..."
		qcli_pool -c diskID=00000001,00000002 raidLevel=1 Stripe=Disabled | slog 6
	else
		echo "Discos já fazem parte de um pool de armazenamento." | slog 6
		return 0
	fi
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

function is_volume_ready() {
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
			if [[ "${parts[4]}" == "Ready" ]]; then
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
	local -i retries=0
	while [[ $ret_wait_volume_ready -ne 0 && $retries -lt 120 ]]; do #Equivale a 10 minutos(magic number here)
		is_volume_ready ret_wait_volume_ready "$targetVolID"
		if [[ $__IS_DEV_ENV ]]; then
			echo '#'
		else
			echo -n '#'
		fi		
		sleep 5
		((retries++))
	done
	echo '.'
	if [[ $ret_wait_volume_ready ]]; then
		echo "Volume(#$targetVolID) pronto!" | slog 5
	else
		echo "Volume(#$targetVolID) falhou em preparação !!!" | slog 3
	fi
	printf -v "$1" "%d" "$ret_wait_volume_ready"
}

function create_vol() {
	local diskID=1 #00000001 eg
	local poolID=1 #Assumido por ser único
	local alias=$1
	local sharename=$2
	local volSize=$3 #180388626432 eg sistema

	local -i ret_create_vol=0 #Valor padrão(sucesso)
	check_vol ret_create_vol "$alias" "$sharename" "$volSize"
	if [[ $ret_create_vol -eq $VOLUME_INEXISTS ]]; then
		slog 5 "Criando o volume($alias), favor aguarde..."
		local cmdOut
		cmdOut=$(qcli_volume -c Alias="$alias" diskID="$diskID" SSDCache=no Threshold=80 \
			sharename="$sharename" encrypt=no lv_type=1 poolID="$poolID" raidLevel=1 \
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
			return $ret_create_vol  #*DEVE se rvalor abaixo de 10
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

function is_package_installed(){
	local pkgName="$1"
	local pkgStatus="$2"
	local qpkg_success
	qpkg_success="QPKG $pkgName is installed"
	if [[ "$qpkg_success" == "$pkgStatus"  ]]; then
		return 0
	else
		return 1
	fi
	#qpkg_response=$(qpkg_cli -s "$pkgName")
}

function install_package(){
	local pkgName="$1"
	local pkgStatus=''
	
	while [[ $(is_package_installed "$pkgName" "$pkgStatus") ]]; do
		local oldStatus="$pkgStatus"
		pkgStatus=$(qpkg_cli -s "$pkgName")


	done

	pkgStatus=$(qpkg_cli -s "$pkgName")

}