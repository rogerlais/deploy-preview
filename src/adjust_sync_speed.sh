#!/bin/sh

#Atualizada por Roger m 20220523

[ "$#" != 1 ] && exit 1

set_low_speed=$1  #1 -> baixa velocidade, outro valor alta velocidade
MD_LIST_FILE=/tmp/.mdlist
low_speed_path=/sys/block/md9/md/sync_speed_min
high_speed_path=/sys/block/md9/md/sync_speed_max

/usr/bin/find /sys/block -name md >$MD_LIST_FILE 2>>/dev/null
numOfmd=$( /bin/cat $MD_LIST_FILE 2>>/dev/null | /bin/awk 'END {print NR}' )

for ((i = numOfmd; i > 0; i--)); do  
    mdPath=$( /bin/cat $MD_LIST_FILE | /usr/bin/tail -n $i | /usr/bin/head -n 1 )
    #Ignora discos nativos
    if [ "$mdPath" = "/sys/block/md9/md" ] || 
       [ "$mdPath" = "/sys/block/md13/md" ] ||
       [ "$mdPath" = "/sys/block/md256/md" ]; then
        continue
    fi

    if [ "$set_low_speed" = "1" ]; then
        sync_completed=$( /bin/cat "$mdPath/sync_completed" 2>>/dev/null)
        if [ $? ]; then
            if [ "$sync_completed" != "none" ]; then
                /bin/cat $low_speed_path 2>>/dev/null | /bin/awk '{print $1}' >"$mdPath/sync_speed_max"
                echo "Velocidade de sinconização elevada ao máximo."
            fi
        fi
    else
        /bin/cat $high_speed_path 2>>/dev/null | /bin/awk '{print $1}' >"$mdPath/sync_speed_max"
        echo "Velocidade de sinconização restabelecida ao valor padrão."
    fi
done

rm -f $MD_LIST_FILE