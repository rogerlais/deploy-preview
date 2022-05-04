#!/bin/bash


dest="admin@10.12.37.28:/root/"
echo "atualizando scripts no NAS..."
sshpass -p "12345678" scp -r "$PWD/src/configNAS.sh" "$dest"
sshpass -p "12345678" scp -r "$PWD/src/utilsFuncs.sh" "$dest"
sshpass -p "12345678" scp -r "$PWD/src/POCs.sh" "$dest"
sshpass -p "12345678" scp -r "$PWD/src/input.txt" "$dest" #fora da versão final
sshpass -p "12345678" scp -r "$PWD/src/volumes.json" "$dest"
sshpass -p "12345678" scp -r "$PWD/src/login_manual.sh" "$dest"  #Fora da versão final