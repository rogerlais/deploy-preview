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
	local -i ret volCount volIdx shareIdx
	local alias shares size primaryShareName

	ret=$(test_json "${jsonfile}")
	if [[ ret -ne 0 ]]; then
		echo "Parser do JSON com os dados dos volumes não poder ser lido( $ret )" | slog 3
		return "$ret"
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
					qcli_sharedfolder -s sharename="$secShareName" volumeID="$((volIdx + 1))" #convert volumeID base 0 to 1
				done
			fi
		else
			echo "Erro criando volume $alias" | slog 2
		fi
	done
	# while read -r item; do
	# 	((cnt++))
	# 	alias=$(jq -r '.alias' <<<"$item")
	# 	sharename=$(jq -r '.sharename' <<<"$item") #!Pode haver diversos compartilhamentos para cada volume
	# 	size=$(jq -r '.size' <<<"$item")
	# 	echo "Volume Index<$cnt>"
	# 	echo "Alias: $alias"
	# 	echo "Sharename: $sharename"
	# 	echo "Size: $size"
	# 	echo "Criando volume <$cnt>"
	# 	create_vol "$alias" "sharename" "$size"
	# done <<<"$(echo "$jsonfile" | jq -c -r '.[]')"

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
	RESULT=$(awk "BEGIN {printf \"%d\",${pool_size}*${vol_percent}/100}") #Saida com inteiro livre
	echo "${RESULT}"
}

function truncToInt() {
	#trunca valor flututante para inteiro
	echo "${1%.*}"
}

function get_root_login() {
	#Passar texto plano para esta rotina de autenticação
	local login=$2
	local pwd=$3

	if [[ $__IS_DEBUG ]]; then
		if [[ $login = 'admin' ]] && [[ "$pwd" = '12345678' ]]; then
			printf -v "$1" "%d" "$?"
			return 0
		else
			printf -v "$1" "%s" "Valores diferentes do esperado para a depuração"
			return 1
		fi
	fi
	#Chamada para a autenticação do cliente na CLI
	qcli -l user="$2" pw="$3" saveauthsid=yes
	printf -v "$1" "%d" "$?"
	#* é gerado um sid aqui, talvez possa ser utils depois
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
	local poolID="$2"
	if ! [ "$poolID" ]; then
		poolID=1
	fi
	slog 7 "PoolID informado: $poolID"
	ret=$(qcli_pool -i poolID=${poolID} displayfield=Capacity | sed -n '$p')
	slog 7 "Valor bruto retornado: $ret"
	printf -v "$1" "%s" "$ret" #gambiarra de retorno para primeiro arg
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
	ret=$(qcli_pool -l | sed "2q;d")
	echo "$ret"
}

function create_pool() {
	if [[ $(get_pool_count) ]]; then
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

	local response volCount volTable line result

	if [[ $__IS_DEV_ENV -eq 0 ]]; then
		response=$(qcli_volume -i displayfield=Alias,Capacity)
	else
		response=$(<./input.txt)
	fi

	volCount=$(echo "$response" | sed -n "2p")
	if [[ $volCount -le 0 ]]; then
		echo "Pool não possui nenhum volume ainda"
		result=$VOLUME_INEXISTS
	else
		volTable=$(tail -n +4 <<<"$response") #pula resumo e cabeçalho da saida
		declare -a entries
		while IFS='' read -r line; do
			entries+=("$line")
		done <<<"$volTable"

		for line in "${entries[@]}"; do
			if [[ "$line" == "$alias"* ]]; then #encontrado no começo da cadeia
				slog 7 "Alias encontrado($alias)"
				IFS=' ' read -r -a parts <<<"$line"
				declare mant=0
				declare bexp=''
				convertLongShortByteSize mant bexp "$volSize"
				if [[ "${parts[2]}" == "$bexp" ]]; then
					checkTolerancePercent "$mant" "${parts[1]}" "5" #cinco e meio porcento
					if [ $? ]; then
						result=$VOLUME_OK #Saida do caminho feliz
					else
						result=$VOLUME_DIVERGENT
					fi
				else
					slog 7 "Grandezas divergentes (${parts[2]}) ($bexp)"
					result=$VOLUME_DIVERGENT
				fi
			fi
		done
		slog 5 "Volume ($alias) não validado."
		result=$VOLUME_INEXISTS		
	fi


	echo "!!!!!!!!!!!! saida da validação = $result "
	printf -v "$1" "%d" "$result"
}

function create_vol() {
	local diskID=1 #00000001 eg
	local poolID=1 #Assumido por ser único
	local alias=$1
	local sharename=$2
	local volSize=$3 #180388626432 eg sistema

	local ret
	check_vol ret "$alias" "$sharename" "$volSize"
	if [[ $ret -eq $VOLUME_INEXISTS ]]; then
		slog 5 "Criando o volume, favor aguarde..."
		qcli_volume -c Alias="$alias" diskID="$diskID" SSDCache=no Threshold=80 \
			sharename="$sharename" encrypt=no lv_type=1 poolID="$poolID" raidLevel=1 \
			Capacity="$volSize" Stripe=Disabled | slog 6
	else
		if [[ $ret -eq $VOLUME_DIVERGENT ]]; then
			slog 3 "Volume com características divergentes foi encontrado!!"
			echo "Volume de tamanho divergente do solicitado já existe!!"
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
			printf -v "$1" "%d" "$out" #retorno mantissa
			break
		fi
	done
}


#!Exemplo de saida abaixo
# [~] # qcli_volume -i
# Volume Count
# 7         
# volumeID poolID Capacity FreeSize Type FileSystem Thin SSDCache Threshold Encrypt Status          Alias    Staticvolume SystemCache Allocated 
# 1        1      81 GB    65 GB    Data EXT4       yes  no       80 %      --      Ready           sistema  no           Enabled     21 %      
# 2        1      4 GB     4 GB     Data EXT4       yes  no       80 %      --      Ready           critico  no           Enabled     3 %       
# 3        1      195 GB   195 GB   Data EXT4       yes  no       80 %      --      Ready           outros   no           Enabled     2 %       
# 4        1      48 GB    48 GB    Data EXT4       yes  no       80 %      --      Ready           entrada  no           Enabled     2 %       
# 5        1      0 MB     0 MB     Data --         yes  no       80 %      --      Formatting...   publico  no           --          2 %       
# 6        1      0 MB     0 MB     Data --         yes  no       80 %      --      Formatting...   restrito no           --          --        
# 7        -1     0 MB     0 MB     Data --         no   no       0 %       --      Initializing... backup   yes          --          --        