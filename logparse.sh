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

# editing out some header data on split files to make them appear correctly, and then
# joining all split pieces into a single entry

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
# using echo and printf seperately as printf alone formats the output of things like certificate data
# in a way that makes it harder to format the data later. 
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

# using echo and printf seperately as printf alone formats the output of things like certificate data
# in a way that makes it harder to format the data later. 
	echo "$newlogentry"
	printf "\n\n\n"
done < change_logs.txt  > new_change_logs.txt

# Now that logs are sorted and ready, create output that is easier to read:

while IFS= read -r line; do
	if [[ "$line" != "" ]]; then
		logdate=$(echo "$line" | grep -hoE "\d{4}\-\d{1,2}\-\d{1,2}.*? ")
		username=$(echo "$line" | grep -hoE "UserName=\"\w*\""  | cut -d "\"" -f2)
		modulename=$(echo "$line" | grep -hoE "ModuleName=\"\w*\"" | cut -d "\"" -f2)
		operation=$(echo "$line" | grep -hoE "Operation=\"\w*\"" | cut -d "\"" -f2)
		operation_status=$(echo "$line" | grep -hoE "Operation status=\"\w*\""  | cut -d "\"" -f2)
		old_value=$(echo "$line" | grep -hoE "Old value=.*New value" |  sed 's/Old value=//' | sed  's/, New value//')
		new_value=$(echo "$line" | grep -hoE "New value=.*" | sed 's/New value=//')

		if [[ "$operation" != *"Delete"* ]] && [[ "$old_value" != "" ]] && [[ "$new_value" != "" ]]; then
			echo "$old_value" > old_value_tmp.txt
			new_value=$(echo $new_value | sed 's/\[.*" {/\[{/' | sed 's/}[[:space:]]{/},{/')
			echo "$new_value" > new_value_tmp.txt
			getdiff=$(diff -y --suppress-common-lines <(jq --sort-keys . old_value_tmp.txt) <(jq --sort-keys . new_value_tmp.txt))
		fi


		printf "Date: $logdate \n"
		printf "UserName: $username \n"
		printf "ModuleName: $modulename \n"
		printf "Operation: $operation \n"
		printf "Operation Status: $operation_status \n"
		printf "Old Value: $old_value \n"
		printf "New Value: $new_value \n\n"
		printf "Diff: \n$getdiff"
		printf "\n\n\n"

		getdiff=""



	fi


done < new_change_logs.txt > Pretty_logs.txt