#!/bin/bash

LOGS=/Users/wrightmichae/Downloads/nsx_support_archive_20240531_210547/nsx_manager_1e071042-72dc-a451-5cd7-b3b0b8a36a5f_20240531_210548/var/log

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
		while IFS= read -r catsplitentry; do
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

		# "big" changes appear to shove multiple entries into one log file. Inserting a comma between each entry so 
		# jq can break them down and display in json format. 
		pretty_old=$(echo "$old_value" | sed 's/}{/},{/g' )
		pretty_old=$(echo "$pretty_old" | jq )

		# all examples of new data have additional fields that the old data never does. Performing
		# a lot of brute force work to make the new data fit constraints for jq 
		

		# 1. stripping starting and ending brackets
		pretty_new=$(echo "$new_value" | sed 's/^\[//' | sed 's/.$//')

		# 2. moving $pretty_new into an array with elements split by space
		read -ra pretty_new_array <<< "$pretty_new"

		# 3. calculating array length for later use
		array_len=${#pretty_new_array[@]}
		
		# 4. adding logic to prevent items such as firewall rules with spaces resulting in being split by the prior
		# read action, such as when a user places spaces in a firewall rule name
		modified_pretty_array=()
		for i in "${pretty_new_array[@]}"; do
			if [[ "$match" == "" ]]; then
				modified_pretty_array+="$i"
				if [[ "$i" == "{"* ]]; then
					if [[ "$i" != *"}" ]]; then
						match="$i"
					fi
				fi
			else
				match="$match$i"
			fi	
		done
		modified_pretty_array+="$match"
		

		#now place all array members back into one variable, inserting leading and closing brackets
		#checking each member of array for lack of curly braces, and adding them if missing
	
		pretty_new_final="["
		for i in "${!modified_pretty_array[@]}"; do
			if [[ "${modified_pretty_array[$i]}" != "{"*"}" ]]; then
				modified_pretty_array[$i]="{${modified_pretty_array[$i]}:${modified_pretty_array[$i]}}"
			fi
		done
	
		# pretty_new_final="["
		# for (( i=0; i < $array_len; i++)); do
		# 	if [[ "${pretty_new_array[$i]}" != "{"*"}" ]]; then
		# 		pretty_new_array[$i]="{${pretty_new_array[$i]}:${pretty_new_array[$i]}}"
		# 	fi
		# done

		#debug test for firewall rules
		for i in "${!modified_pretty_array[@]}"; do
			printf "Array member "$i" : "${modified_pretty_array[$i]}
		done
		printf "\n"

		pretty_new_final=$pretty_new_final${modified_pretty_array[@]}
		pretty_new_final="$pretty_new_final]"
		pretty_new_final=$(echo "$pretty_new_final" | sed 's/} {/},{/g')
		pretty_new_final=$(echo "$pretty_new_final" | jq -R '. as $line | try (fromjson) catch $line' )

	
		# now print all the data

		printf "Date: $logdate \n"
		printf "UserName: $username \n"
		printf "ModuleName: $modulename \n"
		printf "Operation: $operation \n"
		printf "Operation Status: $operation_status \n\n"
		printf "Old Value: $old_value \n\n"
		printf "New Value: $new_value \n\n"
		printf "Pretty Old: $pretty_old \n\n"
		printf "Pretty New: $pretty_new_final \n\n"
	#	printf "Diff: ${diff_data[@]} \n"


		printf "\n\n\n"

	#	diff_data=""


	fi


done < new_change_logs.txt > Pretty_logs.txt

# finally, removing all temp files created
rm -rf change_logs.txt
rm -rf splitid.txt
rm -rf fullsplitid.txt
rm -rf catsplitid.txt
rm -rf new_change_logs.txt
