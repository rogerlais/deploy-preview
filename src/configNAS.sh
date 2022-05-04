#!/bin/bash

#! - O shell oficial é o sh. Alteramos para bash para facilitar nossa vida
#!((X=2**62)); echo $X --> 4611686018427387904 como maior valor inteiro,  4,6 PB acho que deve dar pro gasto

#Script Criado para Configuracao do NAS QNAP nele consiste várias etapas
#inicialmente criando os volumes
#Após a criação dos volumes, o NAS é adicionado tornando-se membro do domínio
#Já pertencendo ao domínio é hora de darmos permissões aos volumes
#E por Último é alterado o nome, as configurações de data e hora e as configurações de rede
#Os comandos "qcli" fazem parte da base específica do NAS QNAP.
#Sendo esse qcli -l uma autorização que é preciso ser feita para prosseguirmos

#
# Revision 20220225 - Roger
# Inicio das modificações com a importação de possíveis partes excluídas e respectivas justificativas de tais exlusões
#

#todo - avaliar se o syslog deve ser ativado - linha abaixo
#setcfg "Global" "Enable" -f "/etc/config/syslog_server.conf" TRUE

#todo Inserir a rota padrão para a subrede da SESOP via eth0
#route add default gw 10.12.37.1 eth0

#*constantes para tamanhos de discos esperados(calculo meio furado e aproximado)
# shellcheck disable=SC2034
{
	DISK_SIZE_1TB=926720000000 #referencia base para as demais
	DISK_SIZE_2TB=1853440000000
	DISK_SIZE_3TB=2780160000000
}


#* Prepara ambiente de execução
LC_NUMERIC="en_US.UTF-8"
#* import das rotinas auxiliares
# shellcheck source=/dev/null
source "${PWD}/utilsFuncs.sh"

#Registro de logs
#! Nível de verbosidade ajustado abaixo
__VERBOSE=7  #Registra TUDO, normal = 5
__LOG_FILE="$PWD/logNAS.txt"
slog 7 "Nível de verbose: $__VERBOSE"
echo "Arquivo de log ajustado para: $__LOG_FILE" | slog 7 

echo "Script configurando Qnap NAS"
#Esse While serve para um tratamento de erro, ao verificar que o comando não teve sucesso ele solicita o usuário e senha novamente
ret=1 #Gera erro para entrada do loop(until para bash daria na mesma)
while [ $ret != 0 ]; do
	echo -n "Digite o User do NAS: "
	read -r usernas
	echo -n "Digite a Senha do NAS: "
	read -ers pwnas
	get_root_login ret "$usernas" "$pwnas"
done
slog 5 "Autenticacao feita com sucesso"

#* Leitura da zona de destino
ret=1 #Gera erro para entrada do loop(until para bash daria na mesma)
while [ $ret != 0 ]; do
	echo -n "Digite a Zona Eleitoral: "; read -r zoneID
	get_is_validZoneId ret "$zoneID"
	if ! [ $ret -eq 0 ] ; then
		echo "Identificador Zona $zoneID é inválido."
	fi
done


#*Nome do dispositivo
zoneIDStr=$(printf "%03d" "$zoneID")
nasName="ZPB${zoneIDStr}NAS01"
setDeviceName "$nasName" | slog 6
echo "Nome do dispositivo: ZPB${zoneIDStr}NAS01" | slog 6

#*Configurações acessórias
echo "Desativando Horário de Verão" | slog 6
setcfg system 'enable daylight saving time' FALSE


#*Controle do armazenamento
echo "Verificando pool de armanzenamento" | slog 6
create_pool
if ! [[ $? ]] ; then
	echo "Falha na criação do pool de armazenamento primário. Processo será encerrado!" | slog 2
	exit 1  #!Saída catastrofica
fi
#Verifica a quantidade total de armazenamento do pool primário
poolSize=''
get_pool_size poolSize "1"
echo "O tamanho nativo informado foi: $poolSize"
poolSize=$( convertShortLongByteSize "$poolSize" )
echo "O pool de armazenamento possui $poolSize Bytes de capacidade"

create_volumes "${VOLUME_DATA}"
if [[ $? ]]; then
	echo "Todos os Volumes foram criados com sucesso!"
else
	echo "Falha na criação dos Volumes. Processo será interrompido!" | slog 
fi

exit


#todo para calcular em % o tamando dos volumes, será necessário calcular por dado recuperado pelo comando abaixo:
#* Apenas palpite, mas por o volume mais acessado antes dos demais
#sistema
#qcli_volume -c Alias=Sistema diskID=00000001 SSDCache=no Threshold=80 sharename=Sistema encrypt=no lv_type=1 poolID=1 raidLevel=1 Capacity=179314884608 Stripe=Disabled | tee -a logNAS.txt
#qcli_volume -c Alias=sistema diskID=00000001 SSDCache=no Threshold=80 sharename=sistema encrypt=no lv_type=1 poolID=1 raidLevel=1 Capacity=180388626432 Stripe=Disabled | tee -a logNAS.txt

#qcli_volume -c Alias=Critico diskID=00000001 SSDCache=no Threshold=80 sharename=Critico encrypt=no lv_type=1 poolID=1 raidLevel=1 Capacity=5368709120 Stripe=Disabled | tee -a logNAS.txt
#-qcli_volume -c Alias=critico diskID=00000001 SSDCache=no Threshold=80 sharename=critico encrypt=no lv_type=1 poolID=1 raidLevel=1 Capacity=5368709120 Stripe=Disabled | tee -a logNAS.txt

#*Note que não existe sharedname=outros, apenas um volume
#qcli_volume -c Alias=Outros diskID=00000001 SSDCache=no Threshold=80 sharename=Outros encrypt=no lv_type=1 poolID=1 raidLevel=1 Capacity=213674622976 Stripe=Disabled | tee -a logNAS.txt
#-qcli_volume -c Alias=outros diskID=00000001 SSDCache=no Threshold=80 sharename=suporte encrypt=no lv_type=1 poolID=1 raidLevel=1 Capacity=214748364800 Stripe=Disabled | tee -a logNAS.txt

#qcli_volume -c Alias=Entrada diskID=00000001 SSDCache=no Threshold=80 sharename=Entrada encrypt=no lv_type=1 poolID=1 raidLevel=1 Capacity=53687091200 Stripe=Disabled | tee -a logNAS.txt
#-qcli_volume -c Alias=entrada diskID=00000001 SSDCache=no Threshold=80 sharename=entrada encrypt=no lv_type=1 poolID=1 raidLevel=1 Capacity=53687091200 Stripe=Disabled | tee -a logNAS.txt

#qcli_volume -c Alias=Publico diskID=00000001 SSDCache=no Threshold=80 sharename=Publico encrypt=no lv_type=1 poolID=1 raidLevel=1 Capacity=53687091200 Stripe=Disabled | tee -a logNAS.txt
#-qcli_volume -c Alias=publico diskID=00000001 SSDCache=no Threshold=80 sharename=publico encrypt=no lv_type=1 poolID=1 raidLevel=1 Capacity=53687091200 Stripe=Disabled | tee -a logNAS.txt

#qcli_volume -c Alias=Restrito diskID=00000001 SSDCache=no Threshold=80 sharename=Restrito encrypt=no lv_type=1 poolID=1 raidLevel=1 Capacity=214748364800 Stripe=Disabled | tee -a logNAS.txt
#qcli_volume -c Alias=restrito diskID=00000001 SSDCache=no Threshold=80 sharename=restrito encrypt=no lv_type=1 poolID=1 raidLevel=1 Capacity=214748364800 Stripe=Disabled | tee -a logNAS.txt

#qcli_volume -c Alias=Backup diskID=00000001 SSDCache=no Threshold=80 sharename=Backup encrypt=no lv_type=1 poolID=1 raidLevel=1 Capacity=966367641600 Stripe=Disabled | tee -a logNAS.txt
#-qcli_volume -c Alias=backup diskID=00000001 SSDCache=no Threshold=80 sharename=backup encrypt=no lv_type=1 poolID=1 raidLevel=1 Capacity=1000000000000 Stripe=Disabled | tee -a logNAS.txt

#Criando a pasta de compartilhamento espelho, ela não é criada automáticamente porque ela não possui volume próprio e fica dentro de "outros"
#* Importante: o ID do volume deve ser o de "outros" que foi criado acima. Lista-se volumes com qcli_volume -l
qcli_sharedfolder -s sharename=espelho volumeID=2


echo "Aguarde Formatando Volumes" | tee -a logNAS.txt
sleep 8m

qcli_volume -i | tee -a logNAS.txt

qpkg_cli -a HybridBackup | tee -a logNAS.txt
echo "aguarde instalando Hybrid backup" | tee -a logNAS.txt
sleep 3m

#!<01> Em versão não homologada havia alinha abaixo. Não encontrada documentação a respeito da chamada
#network_boot_rescan

setcfg -f /mnt/HDA_ROOT/.config/nm.conf global 'current_default_gateway' interface0
setcfg -f /mnt/HDA_ROOT/.config/nm.conf global 'gateway_policy' 1
setcfg -f /mnt/HDA_ROOT/.config/nm.conf global 'disable_dw_updater' 0
setcfg -f /mnt/HDA_ROOT/.config/nm.conf global 'dns_strict_order' 0
setcfg -f /mnt/HDA_ROOT/.config/nm.conf global 'fixed_gateway1' interface0
setcfg -f /etc/config/nm.conf global 'current_default_gateway' interface0
setcfg -f /etc/config/nm.conf global 'gateway_policy' 1
setcfg -f /etc/config/nm.conf global 'disable_dw_updater' 0
setcfg -f /etc/config/nm.conf global 'dns_strict_order' 0
setcfg -f /etc/config/nm.conf global 'fixed_gateway1' interface0

#!<02> Em versão não homologada havia alinha abaixo. Idem ao caso <01>
#network_boot_rescan

/etc/init.d/network.sh restart

echo "Configuracao do NAS no DOMINIO" | tee -a logNAS.txt
echo "Colocando NAS no Dominio." | tee -a logNAS.txt

#comando para capturar via entrada do usuario o login e a senha para colocar no dominio

echo Digite o USERNAME Do Dominio:
read -r userdomain
echo digite o PASSWORD Do Dominio:
read -ers pwdomain

#! para qcli_domainsecurity o argumento -m foi usado ao invés do argumento -q como no caso abaixo(remover comentario após elucidação de motivos)
qcli_domainsecurity -q domain=zne-pb001.gov.br NetBIOS=ZNE-PB001 dns_mode=manual ip=10.12.0.134 domaincontroller=zedc01.zne-pb001.gov.br username=$userdomain password=$pwdomain

while [ $? -eq 0 ]; do
	echo Digite o USERNAME Do Dominio:
	read -r userdomain
	echo digite o PASSWORD Do Dominio:
	read -ers pwdomain
	qcli_domainsecurity -q domain=zne-pb001.gov.br NetBIOS=ZNE-PB001 dns_mode=manual ip=10.12.0.134 domaincontroller=zedc01.zne-pb001.gov.br username=$userdomain password=$pwdomain
done

setcfg Samba 'DC List' ZEDC01.zne-pb001.gov.br,ZEDC02.zne-pb001.gov.br
setcfg Network 'Domain Name Server 2' 10.12.0.228
setcfg -f /etc/config/nm.conf global 'domain_name_server_2' 10.12.0.228

echo "Entrou no Domínio corretamente" | tee -a logNAS.txt

#* Local original da criação do sharedfolder espelho dentro do volume outros!!
# A chamada foi deslocada para o ponto imediatamente após a criação do volume correlato

echo "Permissao para grupos do Dominio" | tee -a logNAS.txt

qcli_sharedfolder -B sharename=publico domain_grouprw='ZNE-PB001\G_SEINF_ADMINS' | tee -a logNAS.txt
qcli_sharedfolder -B sharename=restrito domain_grouprw='ZNE-PB001\G_SEINF_ADMINS' | tee -a logNAS.txt
qcli_sharedfolder -B sharename=critico domain_grouprw='ZNE-PB001\G_SEINF_ADMINS' | tee -a logNAS.txt
qcli_sharedfolder -B sharename=suporte domain_grouprw='ZNE-PB001\G_SEINF_ADMINS' | tee -a logNAS.txt
qcli_sharedfolder -B sharename=espelho domain_grouprw='ZNE-PB001\G_SEINF_ADMINS' | tee -a logNAS.txt

qcli_sharedfolder -B sharename=publico domain_grouprw='ZNE-PB001\G_SESOP_ADMINS' | tee -a logNAS.txt
qcli_sharedfolder -B sharename=restrito domain_grouprw='ZNE-PB001\G_SESOP_ADMINS' | tee -a logNAS.txt
qcli_sharedfolder -B sharename=critico domain_grouprw='ZNE-PB001\G_SESOP_ADMINS' | tee -a logNAS.txt
qcli_sharedfolder -B sharename=suporte domain_grouprw='ZNE-PB001\G_SESOP_ADMINS' | tee -a logNAS.txt
qcli_sharedfolder -B sharename=espelho domain_grouprw='ZNE-PB001\G_SESOP_ADMINS' | tee -a logNAS.txt

qcli_sharedfolder -B sharename=suporte domain_grouprd='ZNE-PB001\G_SIS_ADMINS' | tee -a logNAS.txt

qcli_sharedfolder -B sharename=publico domain_grouprw='ZNE-PB001\setorGsesop' | tee -a logNAS.txt
qcli_sharedfolder -B sharename=restrito domain_grouprw='ZNE-PB001\setorGsesop' | tee -a logNAS.txt
qcli_sharedfolder -B sharename=critico domain_grouprw='ZNE-PB001\setorGsesop' | tee -a logNAS.txt
qcli_sharedfolder -B sharename=suporte domain_grouprw='ZNE-PB001\setorGsesop' | tee -a logNAS.txt
qcli_sharedfolder -B sharename=espelho domain_grouprw='ZNE-PB001\setorGsesop' | tee -a logNAS.txt

qcli_sharedfolder -B sharename=publico domain_grouprd='ZNE-PB001\Domain Users' | tee -a logNAS.txt
qcli_sharedfolder -B sharename=entrada domain_grouprw='ZNE-PB001\Domain Users' | tee -a logNAS.txt

qcli_sharedfolder -B sharename=publico domain_grouprw="ZNE-PB001\setorGzon${zona}" | tee -a logNAS.txt
qcli_sharedfolder -B sharename=restrito domain_grouprw="ZNE-PB001\setorGzon${zona}" | tee -a logNAS.txt
qcli_sharedfolder -B sharename=critico domain_grouprw="ZNE-PB001\setorGzon${zona}" | tee -a logNAS.txt
qcli_sharedfolder -B sharename=suporte domain_grouprd="ZNE-PB001\setorGzon${zona}" | tee -a logNAS.txt
qcli_sharedfolder -B sharename=espelho domain_grouprd="ZNE-PB001\setorGzon${zona}" | tee -a logNAS.txt

#desabilitando pastas iniciais

#deletando as pastas public,web e homes que sao criadas automáticamente
#qcli_sharedfolder -D sharename=Public,Web,homes delete_data=yes

qcli_sharedfolder -e sharename=Public hidden=1 RecycleBinEnable=0
qcli_sharedfolder -e sharename=Web hidden=1 RecycleBinEnable=0
qcli_sharedfolder -e sharename=homes hidden=1 RecycleBinEnable=0
qcli_users -o enable=0 vol_ID=1

echo "Desabilitando Lixeira de rede" | tee -a logNAS.txt
#desabilitar Lixeira de rede
qcli_sharedfolder -e sharename=sistema RecycleBinEnable=0
qcli_sharedfolder -e sharename=suporte RecycleBinEnable=0
qcli_sharedfolder -e sharename=critico RecycleBinEnable=0
qcli_sharedfolder -e sharename=entrada RecycleBinEnable=0
qcli_sharedfolder -e sharename=publico RecycleBinEnable=0
qcli_sharedfolder -e sharename=restrito RecycleBinEnable=0
qcli_sharedfolder -e sharename=backup RecycleBinEnable=0

#Habilitar Windows ACL
echo "Habilitando Windows ACL" | tee -a logNAS.txt
qcli_sharedfolder -p WinACLEnabled=1 | tee -a logNAS.txt

#exemplo de como escrever entre chaves para o sifrao nao ignorar o resto do texto
#O comando setcfg serve entre outras funções para alterar o nome do NAS

#configurando data e hora
echo "Configurando Data e hora" | tee -a logNAS.txt
qcli_timezone -s timezone=17 dateformat=1 timeformat=24 timesetting=2 server=ntp.tre-pb.gov.br interval_type=2 timeinterval=7 AMPM_option=PM | tee -a logNAS.txt

#Configurando SNMP
echo "Configurando SNMP"
setcfg SNMP 'Service Enable' TRUE
setcfg SNMP 'Listen Port' 161
setcfg SNMP 'Trap Community'
setcfg SNMP 'Event Mask 1' 7
setcfg SNMP 'Trap Host 1' 10.12.2.37 #CNAME=zabbix(hordak)
setcfg SNMP 'Event Mask 2' 7
setcfg SNMP 'Trap Host 2' 10.12.2.60 #CNAME=monitor,centreon(pluto)
setcfg SNMP 'Event Mask 3' 7
setcfg SNMP 'Trap Host 3'
setcfg SNMP 'Version' 3
setcfg SNMP 'Auth Type' 0
setcfg SNMP 'Auth Protocol' 0
setcfg SNMP 'Priv Protocol' 0
setcfg SNMP 'User' snmpnas
setcfg SNMP 'Auth Key'
setcfg SNMP 'Priv Key'

#Criando Agregação de Compartilhamento

echo "Criando Agregacao compartilhamento"
qcli_sharedfolder -c Name=Compartilhamento
#esse comando serve para a opção os usuários devem fazer login antes de acessar a pasta portal
setcfg -f /etc/config/smb.conf Compartilhamento 'invalid users' guest
qcli_sharedfolder -A portalfolder=Compartilhamento Name=critico HostName="ZPB0${zona}NAS01" RemoteSharedFolder=critico
qcli_sharedfolder -A portalfolder=Compartilhamento Name=entrada HostName="ZPB0${zona}NAS01" RemoteSharedFolder=entrada
qcli_sharedfolder -A portalfolder=Compartilhamento Name=espelho HostName="ZPB0${zona}NAS01" RemoteSharedFolder=espelho
qcli_sharedfolder -A portalfolder=Compartilhamento Name=outros HostName="ZPB0${zona}NAS01" RemoteSharedFolder=suporte
qcli_sharedfolder -A portalfolder=Compartilhamento Name=publico HostName="ZPB0${zona}NAS01" RemoteSharedFolder=publico
qcli_sharedfolder -A portalfolder=Compartilhamento Name=restrito HostName="ZPB0${zona}NAS01" RemoteSharedFolder=restrito
qcli_sharedfolder -A portalfolder=Compartilhamento Name=backup HostName="ZPB0${zona}NAS01" RemoteSharedFolder=backup

setcfg system 'enable daylight saving time' FALSE

x="0"
while [ $x -eq 0 ]; do
	echo "Deseja Continuar para o Fim da Configuracao s/n? "
	read -r y
	[ "$y" == "s" ] && x="1"
done

echo "Configuracoes de Network" | tee -a logNAS.txt
qcli_network -m interfaceID=eth0 IPType=STATIC IP="10.183.${zona}.210" netmask=255.255.255.0 gateway="10.183.${zona}.70" dns_type=manual dns1=10.12.0.134 dns2=10.12.0.228 | tee -a logNAS.txt
