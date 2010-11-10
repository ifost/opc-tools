#!/usr/bin/sh

# This script reports what collections are working, by listing each
# datafile and 

cd /var/opt/OV/share/databases/snmpCollect
COLLECTIONS=$(ls *.*[0-9] | cut -d. -f1 | sort | uniq)

for collection in $COLLECTIONS
do
  echo -n "$collection "
  echo $( ( for file in ${collection}*[0-9]
            do
              snmpColDump $file | awk '{print $4}' | sort | uniq
            done
           ) | sort | uniq
        )
done


  
