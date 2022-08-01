#!/bin/bash

ENDPOINT="$1"
if [ -n "$ENDPOINT" ]; then
    SSH_USER="admin"
    SSH_PASSWORD="admin"
else
    echo "Informe IP do NAS a atualizar"
    exit
fi

echo "Atualizando endpoint host=${ENDPOINT}"
declare dummy
#shellcheck disable=2034
read -p "Enter para confirmar" -r dummy

DEST_HOST_NAS="${SSH_USER}@${ENDPOINT}:/tmp/sesop/"

echo "atualizando scripts no NAS..."
sshpass -p "$SSH_PASSWORD" rsync -av "$PWD/src/" "${DEST_HOST_NAS}"
sshpass -p "$SSH_PASSWORD" rsync -av "$PWD/.env" "${DEST_HOST_NAS}"
sshpass -p "$SSH_PASSWORD" rsync -av "$PWD/.secret" "${DEST_HOST_NAS}"
sshpass -p "$SSH_PASSWORD" rsync -av "$PWD/LINUX_DEV.env" "${DEST_HOST_NAS}"
sshpass -p "$SSH_PASSWORD" rsync -av "$PWD/LINUX.env" "${DEST_HOST_NAS}"
