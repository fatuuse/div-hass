#!/bin/sh

# SL-hållplatser
#            

link=http://mini.sl.se/sv/realtime/Departures?fromSiteId=

STATION=(4059 4364)
# Rosenmalm 4364
# Värmdö Marknad 4059
# Slussen 9192

hass_link="http://127.0.0.1:8123/api/states/sensor.sl_"
pass=

tLen=${#STATION[@]}
IFS=;

for (( i=0; i<${tLen}; i++ ));
do
	# store the whole response with the status at the and
	HTTP_RESPONSE=$(curl -X GET --silent --write-out "HTTPSTATUS:%{http_code}" -H 'User-Agent: Mozilla/5.0' $link${STATION[$i]})
	
	# extract the body
	HTTP_BODY=$(echo $HTTP_RESPONSE | sed -e 's/HTTPSTATUS\:.*//g')

	# extract the status
	HTTP_STATUS=$(echo $HTTP_RESPONSE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
	#output="$(curl -s -H 'User--Agent: Mozilla/5.0' $link${STATION[$i]} | tr -d '\n\t' | tr -s ' ' | grep -oP '(?<=<h3 class="block no-padding wurflkeep">).*?(?=</ul>)')"
	
	output="$(echo $HTTP_BODY | tr -d '\n\t' | tr -s ' ' | grep -oP '(?<=<h3 class="block no-padding wurflkeep">).*?(?=</ul>)')"
	
	# Station
	station_name=$(echo $output | grep -oP '(?<=alt="" /> ).*?(?= </h3>)' | tr -d ',')
	busses=$(echo $output | grep -oP '(?<=><b).*?(?=</li>)' | sed -e 's/<[^>]*>/;/g' | sed -e 's/;;;/;/g' -e 's/>/;/g' -e 's/ ;/;/g' -e 's/; /;/g' | cut -c 2- | sed -e 's/;/ /g')

	
	echo $HTTP_STATUS
	echo ${STATION[$i]}  $station_name
	#echo $output
	#echo $busses
	

#if [[ !  -z  $next_buss  ]]; then
if [ $HTTP_STATUS -eq 200  ]; then
	echo
	# Första bussen
	#next_buss=$(echo $busses | head -1)
	IFS=" " 
	next_buss=($(echo $busses | head -1 | sed -e 's/Nu/0 min/g'))
	
	if [ ${#next_buss[0]} -gt 4 ]; then
	next_buss[0]=$[($(date "+%s" --date "14:00")-$(date "+%s"))/60]
	next_buss[2]=${next_buss[3]}
	next_buss[1]=${next_buss[2]}
	fi
	
	
	# resten av bussarna
	#busses=$(echo $busses | tail -n +2 | sed -e ':a' -e 'N' -e '$!ba' -e 's/ \n/\\n/g')
	busses=$(echo $busses | sed -e ':a' -e 'N' -e '$!ba' -e 's/ \n/\\n/g')
	
	#echo "${next_buss[0]} min ${next_buss[2]} ${next_buss[3]}"
	echo $busses
	
generate_post_data()
{
  cat <<EOF
{"state":"${next_buss[0]}",
"attributes": {
 "unit_of_measurement": "${next_buss[1]}",
 "friendly_name": "${next_buss[2]} ${next_buss[3]}",
 "station": "$station_name",
 "kommande": "$busses"}
}
EOF
}

#echo $(generate_post_data)
# skicka data
echo 
	curl -X POST --silent -H "x-ha-access: $pass" -H "Content-Type: application/json; charset=UTF-8" -d "$(generate_post_data)" $hass_link${STATION[$i]}
else
generate_post_data()
{
  cat <<EOF
{"state":"err",
"attributes": {}
}
EOF
}
 curl -X POST --silent -H "x-ha-access: $pass" -H "Content-Type: application/json; charset=UTF-8" -d "$(generate_post_data)" $hass_link${STATION[$i]}
fi

echo 
echo --------------

done
