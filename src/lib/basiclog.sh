#!/bin/bash

declare -a LOG_LEVELS
# https://en.wikipedia.org/wiki/Syslog#Severity_level
LOG_LEVELS=([0]="emerg" [1]="alert" [2]="crit" [3]="err" [4]="warning" [5]="notice" [6]="info" [7]="debug")
declare VOLUME_INEXISTS=10
declare VOLUME_OK=0
declare VOLUME_DIVERGENT=20
export VOLUME_INEXISTS , VOLUME_OK , VOLUME_DIVERGENT

#todo:urgent: Put initialization process, aka log path and rotation. Export pertinent data after this

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
