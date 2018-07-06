#! /bin/sh

ERR=0

for po in ../I18N/lang/*.po
do

    dir=`grep -A 1 "msgid \"MC-Projects\"" $po | tail -n 1 | sed 's/^msgstr \"//;s/\"$//'`

    if echo "$dir" | grep -Pq '[^A-Za-z0-9_-]'
    then
        echo "[FAIL] $po: $dir"
        ERR=$(($ERR + 1))
    else
        echo "[ OK ] $po: $dir"
    fi

done

exit $ERR
