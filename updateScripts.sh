#!/bin/bash

dest="admin@10.12.37.28:/root/"

#mkdir "${dest}debug" 3> /dev/null

echo "atualizando scripts no NAS..."
sshpass -p "12345678" rsync -av "$PWD/src/configNAS.sh" "${dest}"
sshpass -p "12345678" rsync -av "$PWD/src/utilsFuncs.sh" "${dest}"
sshpass -p "12345678" rsync -av "$PWD/src/POCs.sh" "${dest}"
sshpass -p "12345678" rsync -av "$PWD/src/qcli_simulated.sh" "${dest}"          #fora da versão final
sshpass -p "12345678" rsync -av "$PWD/src/debug/" "${dest}debug/"   #fora da versão final
#sshpass -p "12345678" rsync -av "$PWD/src/debug/volinfo.txt" "${dest}debug/" #fora da versão final
sshpass -p "12345678" rsync -av "$PWD/src/volumes.json" "${dest}"
sshpass -p "12345678" rsync -av "$PWD/src/login_manual.sh" "${dest}"        #Fora da versão final
sshpass -p "12345678" rsync -av "$PWD/src/parts/shorts.sh" "${dest}/parts/" #Fora da versão final
