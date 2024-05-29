#!/bin/bash

LOGS=/Users/wrightmichae/Downloads/nsx_support_archive_20240526_142427/nsx_manager_1e071042-72dc-a451-5cd7-b3b0b8a36a5f_20240526_142432/var/log

#grabs all the log entries that match the various operations listed, such as Add, Create, etc)
change_logs=$(grep -hE "Operation=\"('Add|Create|Delete|Generate|Patch|Remove|Restore|Resync|Update')\w*\"" $LOGS/nsx-audit.log* > change_logs.txt)

#sort change_logs (this helps later to ensure that split entries that are muxed and added to final output are in correct order

sort -k 2,2 change_logs.txt -o change_logs.txt

# grabs all the entries with a splitId. These entries must be searched out and recombined. The below grabs the splitId only, not the entire log line.

while IFS= read -r line ; do 
	grep -hoE "splitId=\"\w*\""
done < change_logs.txt > splitid.txt

# for each splitID identified in splitid.txt, pull all the corresponding lines out marked with it in nsx-audit.logs, and write it to fullsplitid.txt. 

while IFS= read -r line; do
	grep -hE $line $LOGS/nsx-audit.log*
done < splitid.txt > fullsplitid.txt 

#test code to see if i can mux the split entries together without messing with the stuff above
#note - this works - data is output to catsplitid.txt 
# commenting everything out below to work on the test case noted in the next section

#while IFS= read -r line; do
#	splittest=""
#        while IPS= read -r newline; do
#		if [[ "$newline" == *"$line"* ]]; then
#			splittest=$splittest$newline
#                fi
#        done < fullsplitid.txt
#        printf "$splittest\n\n\n"

# testing editing out some header data on split files to make them appear correctly
# note - this works

while IFS= read -r line; do
        splittest=""
        while IPS= read -r newline; do
                if [[ "$newline" == *"$line"* ]]; then
			if [[ "$newline" == *"splitIndex=\"1 of"* ]]; then
                        	splittest=$newline
			else
				editnewline=$(echo $newline | cut -d "]" -f2-)
				splittest=$splittest$editnewline
			fi
                fi
        done < fullsplitid.txt
#        printf "$splittest\n\n\n"
	echo "$splittest"
	printf "\n\n\n"
done < splitid.txt > catsplitid.txt

# Now replace each line in change logs that have a splitid with the newly joined splitid entry

while IFS= read -r line; do
        newlogentry=""
	if [[ "$line" == *"splitId"* ]]; then
		splitid=$(echo "$line" | grep -hoE "splitId=\"\w*\"")
		while IPS= read -r catsplitentry; do
			if [[ "$catsplitentry" == *"$splitid"* ]]; then
				newlogentry=$catsplitentry
			fi
		done < catsplitid.txt
	else
		newlogentry=$line
	fi

#        printf "$newlogentry\n\n\n"
	echo "$newlogentry"
	printf "\n\n\n"
done < change_logs.txt  > new_change_logs.txt


