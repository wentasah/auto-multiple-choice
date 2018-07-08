#! /bin/sh

FOUND=0

for glade in `find .. -name '*.glade'`
do

    # checks that all objects has an id tag (needed with old versions of Glade)
    grep -Hn "object class" $glade | grep -v 'id=' && FOUND=1
    # checks that all ids are different
    COUNTS=`grep "object class" $glade | grep "id=" | sed 's/.*id="\([^"]*\)".*/\1/' | sort | uniq -c | grep -v '^\s*1 '`
    if [ "$COUNTS" ]
    then
        echo "$glade:IDs: $COUNTS"
        FOUND=1
    fi
done

exit $FOUND
