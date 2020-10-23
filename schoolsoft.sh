#!/bin/bash

# SchoolSoft
# Version 20190829

help() {
cat <<EOT
sensor in Home Assistant
- platform: command_line
  name: SchoolSoft
  json_attributes:
  - updated
  - elev0
  - tider0
  - mat0
  - aktiviteter0
  - elev1
  - tider1
  - mat1
  - aktiviteter1
  - icon
  scan_interval: 14400
  command: "bash /home/homeassistant/.homeassistant/scripts/schoolsoft.sh -u yyyyy -p xxxxx -k stockholm -o json"
  value_template: '{{ value_json.dag0 }}'
EOT
}


#user running
uid=$(id -u -n)

# Convert long args to short
for arg in "$@"; do
  shift
  case "$arg" in
    "--help") set -- "$@" "-h yes" ;;
    "--debug") set -- "$@" "-d true" ;;
    "--kommun") set -- "$@" "-k" ;;
    "--user") set -- "$@" "-u" ;;
    "--password") set -- "$@" "-p" ;;
    "--pass") set -- "$@" "-p" ;;
    "--output") set -- "$@" "-o" ;;
    *)        set -- "$@" "$arg"
  esac
done

# Get options
while getopts h:d:u:p:k:o: option
do
case "${option}"
in
h) action="help";;
d) debug=true;;
u) user=${OPTARG};;
p) password=${OPTARG};;
k) kommun=${OPTARG};;
o) output=${OPTARG};;
esac
done
# --- Funktioner

decode_char() {
    text="$1"
    text="${text//&lt;/<}"
    text="${text//&gt;/>}"
    text="${text//&nbsp;/ }"
    text="${text//&amp;/&}"
    text="${text//&aring;/å}"
    text="${text//&auml;/ä}"
    text="${text//&ouml;/ö}"
    text="${text//&amp;/&}"
    text="${text//&nbsp;/ }"
  echo "$text"
}
# ---
if [ "$action" = "help" ]; then
echo
echo "HELP for script SchoolSoft"
echo "Arguments:"
echo -e "\t -h help "
echo -e "\t -u user \t -p password \t -k kommun \t -o output (json/text)" 
echo
help
else

#IFS=', ' read -r -a studenter_id <<< "$student"

declare -a studenter_id
declare -a elever
declare -a tider
declare -a mat
declare -a aktiviteter
declare -a dag

link_login="https://sms.schoolsoft.se/$kommun/jsp/Login.jsp"
link_students="https://sms.schoolsoft.se/varmdo/jsp/student/right_parent_pwdadmin.jsp"
link_base="https://sms.schoolsoft.se/$kommun/jsp/student/"
pages=("top_student.jsp" "right_student_startpage_preschool.jsp" "right_parent_preschool_schedule_new.jsp" "right_student_lunchmenu.jsp" "right_student_schedule.jsp")

cookie="/tmp/"$uid"_schoolsoft_cookie"


  # efter 18 hämta nästa dag
 if [ $(date +%H) -gt 18 ]; then
   dagens_nummer=$(expr $(date -d@"$(( `date +%s`+60*60*24))" +%u) - 1) # Måndag = 0
   vecko_nummer=$(date -d@"$(( `date +%s`+60*60*24))" +%V)
   add_text_dag="Imorgon "
 else
   dagens_nummer=$(expr $(date +%u) - 1)
   vecko_nummer=$(date +%V)
   add_text_dag=""
 fi
 dag_namn=('Måndag' 'Tisdag' 'Onsdag' 'Torsdag' 'Fredag' 'Lördag' 'Söndag')
 dag_namn=${dag_namn[$dagens_nummer]}
 if [[ $debug = true ]]; then
    echo "Dagens nummer: "$dagens_nummer
    echo "Vecko nummer: "$vecko_nummer
  fi
    
    
#rm $cookie
if [ -f "$cookie" ]; then
    if [[ $debug = true ]]; then
    echo "Cookie: $cookie"
    fi

if [[ $(find "$cookie" -mmin +60 -print) ]]; then
    if [[ $debug = true ]]; then
    echo "Remove cookie"
    fi
  rm $cookie
fi
fi

login=0
while [ $login -le 1 ]; do

# Login page om
if [ $login -eq 1 ] || ! [ -f "$cookie" ]; then
  # HASS måste ha rättigheter till mappen där cookien ligger
    if [[ $debug = true ]]; then
    echo "Login"
    fi
    HTTP_RESPONSE=$(curl --max-time 30 -s $link_login -c $cookie -d "action=login&ssusername=$user&sspassword=$password&usertype=2" --write-out "HTTPSTATUS:%{http_code}" -A "User-Agent: Mozilla/5.0")
    HTTP_BODY=$(echo $HTTP_RESPONSE | sed -e 's/HTTPSTATUS\:.*//g')
	HTTP_STATUS=$(echo $HTTP_RESPONSE | sed -e 's/.*HTTPSTATUS://')
	else
	HTTP_STATUS=0
fi
if [ $HTTP_STATUS -eq 302  ] && [ $login -eq 0  ]; then
  if [[ $debug = true ]]; then
    echo "Login Error - Login: $login"
    echo "Status: $HTTP_STATUS"
    echo "Status: $HTTP_BODY"
  fi
    rm $cookie
    login=1
    sleep 3
else
    login=$(expr $login + 2)
    if [[ $debug = true ]]; then
    echo "Login"
    fi
fi

done

# Hämta studenter
    HTTP_RESPONSE=$(curl -X POST --max-time 30 --silent -b $cookie --write-out "HTTPSTATUS:%{http_code}" -A "User-Agent: Mozilla/5.0" "$link_students")
    HTTP_BODY=$(echo $HTTP_RESPONSE | sed -e 's/HTTPSTATUS\:.*//g' | iconv -f iso8859-1 -t utf-8)
	HTTP_STATUS=$(echo $HTTP_RESPONSE | sed -e 's/.*HTTPSTATUS://')
	#echo "$HTTP_RESPONSE" > html_output.txt
    result=$(echo "$HTTP_BODY" | grep -P -o 'RSS-flöde\K.*?(?=iCalendar-flöde)')
    result=$(echo "$result" | sed -e 's/<a [^>]*key=/;/g' | sed -e 's/&key2=[^>]*>/;/g' | sed -e 's/<\/a>/;/g' )
    result=$(echo "$result" | sed -e 's/<[^>]*>//g' )
    result=$(echo "$result" | sed -e 's/Aktivt//g' | sed -e 's/;;/;/g' | sed -e 's/;&nbsp;/;/g' )
    result=$(decode_char "$result" )
    
    
    #echo "$result" > html_output.txt
    IFS=$';' read -r -d '' -a array_students <<< "$result"
    if [[ $debug = true ]]; then
      echo "count: $(( (${#array_students[@]} -2) /2 ))"
	  echo "elever: ${array_students[@]}"
	fi
	for (( c=1; c<$(( (${#array_students[@]} -2))); c+=2)); do
	if [[ $debug == true ]]; then
	  echo "$c: ${array_students[$c]}"
	fi
	studenter_id+=("${array_students[$c]}")
	done
	
	if [[ $debug == true ]]; then
	  echo "students: ${studenter_id[@]}"
	fi
	
# Loop studenter
for student in "${studenter_id[@]}"; do
if [[ $debug == true ]]; then
  echo "student: $student"
  fi

for page in "${pages[@]}"; do

    # Hämta sida med info
    if [ "$page" == "${pages[0]}" ]; then
      page="$page?student=$student"
    fi
    if [[ $debug == true ]]; then
      echo "-"
      echo "page: $page"
    fi
    
    HTTP_RESPONSE=$(curl -X POST --max-time 30 --silent -b $cookie --write-out "HTTPSTATUS:%{http_code}" -A "User-Agent: Mozilla/5.0" "$link_base$page" | iconv -f iso8859-1 -t utf-8)
	HTTP_BODY=$(echo $HTTP_RESPONSE | sed -e 's/HTTPSTATUS\:.*//g')
	HTTP_STATUS=$(echo $HTTP_RESPONSE | sed -e 's/.*HTTPSTATUS://')
	
	if [[ $debug == true ]]; then
	  echo "status: $HTTP_STATUS"
	fi

	
	if [ $HTTP_STATUS -eq 200  ]; then
    case "$page" in
    "${pages[0]}" )
      # Change student pages
      echo "Change student pages to student: $student"

    ;;
    "${pages[1]}" )
      # Start page
      #echo "Start page"
    result=$(echo "$HTTP_BODY"  | grep -P -o '<form name="userForm" action="top_student.jsp" method="post">\K.*?(?=</form>)')
    result=$(decode_char "$result" )
    
    result=$(echo "$result" | sed -e 's/<\/span>/;/g' | sed -e 's/<\/li>/;/g' | sed -e 's/<[^>]*>//g' )
    result=$(echo "$result" | tr -d '\n\r' | tr -d ' ' | sed -e 's/,/, /g' )
    #echo "$result" >> html_output.txt
    
    IFS=$';' read -r -d '' -a array_student <<< "$result"
    if [[ $debug == true ]]; then
     # echo ${array_student[@]}
	  echo "elev: ${array_student[3]}"
	fi
    elever+=("${array_student[3]}")
    
    ;;
    "${pages[2]}" )
    result=$(echo "$HTTP_BODY" | grep -P -o '<div id="cont_schedule_content" class="h2_inner" >\K.*?(?=</div><!-- ends content -->)')
    result=$(decode_char "$result" )
    result=$(echo "$result" | sed -e 's/<tr>/|/g' | sed -e 's/<\/table>/|/g' | sed -e 's/<td[^>]*>/;/g' | sed -e 's/<br[^>]*>/+/g' | sed -e 's/<[^>]*>//g' )
    result=$(echo "$result" | tr '|' '\n' | tr -d ' ' | sed -e 's/+/ /g' )
    #echo "$result" >> html_output.txt
    IFS=$'\n' read -r -d '' -a result_lines <<< "$result"
    
    for i in {2..6}; do
      IFS=';' read -r -d '' -a line <<< "${result_lines[$i]}"
      if [[ $debug == true ]]; then
        echo ${line[@]}
        echo "veckonr: " $vecko_nummer
      fi
      if [ $vecko_nummer -eq ${line[1]} ]; then
        #echo "$i"
        #echo "${line[@]}"
        IFS=' ' read -r -d '' -a array_tider <<< "${line[$(expr $dagens_nummer + 2)]}"

        if [[ $debug == true ]]; then
	      echo "tider: ${array_tider[1]}"
	    fi
        tider+=(${array_tider[1]})
        break
      elif [[ $i -eq ${#result_lines[@]} || $i -eq 6 ]]; then
        if [[ $debug == true ]]; then
          echo "dagen finns inte i listan"
        fi
        tider+=("")
      fi
    done
    ;;
    "${pages[3]}" )
      # Mat sida
      #echo "Food page"
    result=$(echo "$HTTP_BODY" | grep -P -o '<div class="h2_container" id="lunchmenu_con">\K.*?(?=<!-- ends content -->)')
    result=$(decode_char "$result" )
    
    result=$(echo "$result" | sed -e 's/<table[^>]*>/|/g' | sed -e 's/<\/table>/;/g' | sed -e 's/<td[^>]*>/;/g' | sed -e 's/<script>[^>]*<\/script>//g' )
    #echo "$result" >html_output.txt
    result=$(echo "$result" | sed -e 's/<[^>]*>//g' )
    result=$(echo "$result" | tr -d '\n\r'  )
    result=$(echo "$result" | tr '|' '\n' )
    
    IFS=$'\n' read -r -d '' -a result_lines <<< "$result"
    
    IFS=';' read -r -d '' -a array_mat <<< "${result_lines[$(expr $dagens_nummer + 1)]}"
    mat+=("${array_mat[2]} ${array_mat[4]}")
    
    # Hämta dag
    #IFS=';' read -r -d '' -a dag_array<<< $(echo "$result" | grep 'Idag')
    IFS=';' read -r -d '' -a dag_array <<< "${result_lines[$(expr $dagens_nummer)]}"
    if [[ $debug == true ]]; then
	  echo "dag: ${dag_array[5]}"
	fi
    dag+=("$(echo "${dag_array[5]}" | sed -e 's/Idag //g' | sed -e 's/Imorgon //g' )")

    ;;
    "${pages[4]}" )
      # Schema
      #echo "Time page"
    result=$(echo "$HTTP_BODY" | grep -P -o '<div class="content_wrapper" id="content">\K.*?(?=<\/table><\/div><\/div>)')
    result=$(decode_char "$result" )
    result=$(echo "$result" | sed -e 's/<tr[^>]*>/|/g'  )
    result=$(echo "$result" | tr -d '\n\r'  )
    result=$(echo "$result" | tr '|' '\n' | sed '/^ *$/d' )
    #echo "$result" >>html_output.txt
    #IFS=$'\n' read -r -d '' -a result_lines <<< "$result"
    
    #IFS=';' read -r -d '' -a array_mat <<< "${result_lines[$(expr $dagens_nummer + 1)]}"
    if [[ $debug == true ]]; then
	  echo "aktiviteter: ${array_mat[0]}"
	fi
    #aktiviteter+=("${array_mat[2]} ${array_mat[4]}")
    
    ;;
    esac # end case page
    
    fi # end status
    done # for loop pages
    if [[ $debug == true ]]; then
	  echo
	  echo "----"
	  echo
	fi
    done # for studenter
    
result=""
if [ "$output" == "json" ]; then
result="\"updated\": \"$(date +'%Y-%m-%d %T.0%z')\","
  result="$result \"dag\": \"$add_text_dag$dag_namn\","
  result="$result \"elever\": \"${array_students[@]}\","
for (( i=0; i<${#studenter_id[@]}; i++ )); do
  result="$result \"elev$i\": \"${elever[$i]}\","
  result="$result \"dag$i\": \"${dag[$i]}\","
  result="$result \"tider$i\": \"${tider[$i]}\","
  result="$result \"mat$i\": \"${mat[$i]}\","
  result="$result \"aktiviteter$i\": \"${aktiviteter[$i]}\","
done
result="{$result \"icon\": \"mdi:school\"}"

echo $result

else
result=">updated: $(date +'%Y-%m-%d %T.0%z')\n"
  result="$result dag: $add_text_dag$dag_namn\n"
  result="$result elever: ${array_students[@]}\n"
for (( i=0; i<${#studenter_id[@]}; i++ )); do
  result="$result elev$i: ${elever[$i]}\n"
  result="$result dag$i: ${dag[$i]}\n"
  result="$result tider$i: ${tider[$i]}\n"
  result="$result mat$i: ${mat[$i]}\n"
  result="$result aktiviteter$i: ${aktiviteter[$i]}\n"
done
printf "$result"

fi # end output
fi # end action


