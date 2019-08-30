#!/bin/bash

# SchoolSoft
# Version 20190828

#user running
uid=$(id -u -n)

# Convert long args to short
for arg in "$@"; do
  shift
  case "$arg" in
    "--help") set -- "$@" "-h yes" ;;
    "--student") set -- "$@" "-s" ;;
    "--kommun") set -- "$@" "-k" ;;
    "--user") set -- "$@" "-u" ;;
    "--password") set -- "$@" "-p" ;;
    "--pass") set -- "$@" "-p" ;;
    "--output") set -- "$@" "-o" ;;
    *)        set -- "$@" "$arg"
  esac
done

# Get options
while getopts h:s:u:p:k:o: option
do
case "${option}"
in
h) action="help";;
s) student=${OPTARG};;
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
  echo "$text"
}
# ---
if [ "$action" == "help" ]; then
echo
echo "HELP for script SchoolSoft"
echo "Arguments:"
echo -e "\t -h help \t -s student (, delimiter)"
echo -e "\t -u user \t -p password \t -k kommun \t -o output (json/text)" 
else

IFS=', ' read -r -a studenter_id <<< "$student"

declare -a elever
declare -a tider
declare -a mat
declare -a aktiviteter
declare -a dag

link_login="https://sms.schoolsoft.se/$kommun/jsp/Login.jsp"
link_base="https://sms.schoolsoft.se/$kommun/jsp/student/"
pages=("top_student.jsp" "right_student_startpage_preschool.jsp" "right_parent_preschool_schedule_new.jsp" "right_student_lunchmenu.jsp" "right_student_schedule.jsp")

cookie="/tmp/"$uid"_schoolsoft_cookie"

# Måndag = 0
dagens_nummer=$(expr $(date +%u) - 1)

if [ -f "$cookie" ]; then
if [[ $(find "$cookie" -mmin +120 -print) ]]; then
  rm $cookie
fi
fi

login=0
while [ $login -le 1 ]; do

# Login page om
if [ $login -eq 1 ] || ! [ -f "$cookie" ]; then
  # HASS måste ha rättigheter till mappen där cookien ligger
    #echo "Login"
    HTTP_RESPONSE=$(curl -s $link_login -c $cookie -d "action=login&ssusername=$user&sspassword=$password&usertype=2" --write-out "HTTPSTATUS:%{http_code}" -A "User-Agent: Mozilla/5.0")
    HTTP_BODY=$(echo $HTTP_RESPONSE | sed -e 's/HTTPSTATUS\:.*//g')
	HTTP_STATUS=$(echo $HTTP_RESPONSE | sed -e 's/.*HTTPSTATUS://')
	else
	HTTP_STATUS=0
fi
if [ $HTTP_STATUS -eq 302  ] && [ $login -eq 0  ]; then
    #echo "Login Error   - Login: $login"
    #echo "Status: $HTTP_STATUS"
    login=1
  sleep 3
else
    login=$(expr $login + 2)
    #echo "Logged in"
fi

done

for student in "${studenter_id[@]}"; do
for page in "${pages[@]}"; do


    # Hämta sida med info
    if [ "$page" == "${pages[0]}" ]; then
      page="$page?student=$student"
    fi
    #echo "Get info from page: $page"
    HTTP_RESPONSE=$(curl -X POST --silent -b $cookie --write-out "HTTPSTATUS:%{http_code}" -A "User-Agent: Mozilla/5.0" "$link_base$page" | iconv -f iso8859-1 -t utf-8)
	HTTP_BODY=$(echo $HTTP_RESPONSE | sed -e 's/HTTPSTATUS\:.*//g')
	HTTP_STATUS=$(echo $HTTP_RESPONSE | sed -e 's/.*HTTPSTATUS://')
	
	#echo "Status: $HTTP_STATUS"


	
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
    result=$(echo "$result" | sed -e 's/<\/span>/;/g' | sed -e 's/<[^>]*>//g' )
    result=$(echo "$result" | tr -d '\n\r' | tr -d ' ' )
    
    #echo "$result" >> html_output.txt
    IFS=$';' read -r -d '' -a array_student <<< "$result"
    elever+=("${array_student[4]}")
    
    ;;
    "${pages[2]}" )
    result=$(echo "$HTTP_BODY" | grep -P -o '<div id="cont_schedule_content" class="h2_inner" >\K.*?(?=</div><!-- ends content -->)')
    result=$(echo "$result" | sed -e 's/<tr>/|/g' | sed -e 's/<\/table>/|/g' | sed -e 's/<td[^>]*>/;/g' | sed -e 's/<br[^>]*>/+/g' | sed -e 's/<[^>]*>//g' )
    result=$(echo "$result" | tr '|' '\n' | tr -d ' ' | sed -e 's/+/ /g' )
    #echo "$result" >> html_output.txt
    IFS=$'\n' read -r -d '' -a result_lines <<< "$result"
    
    for i in {3..7}; do
      IFS=';' read -r -d '' -a line <<< "${result_lines[$i]}"
      if [ $(date +%V) -eq ${line[1]} ]; then
        #echo "$i"
        #echo "${line[@]}"
        break
      fi
    done
    IFS=' ' read -r -d '' -a array_tider <<< "${line[$(expr $dagens_nummer + 2)]}"
    #echo ${array_tider[1]}
    tider+=(${array_tider[1]})
    ;;
    "${pages[3]}" )
      # Mat sida
      #echo "Food page"
    result=$(echo "$HTTP_BODY" | grep -P -o '<div class="h2_container" id="lunchmenu_con">\K.*?(?=<!-- ends content -->)')
    result=$(echo "$result" | sed -e 's/<table[^>]*>/|/g' | sed -e 's/<\/table>/;/g' | sed -e 's/<td[^>]*>/;/g' | sed -e 's/<script>[^>]*<\/script>//g' | sed -e 's/<[^>]*>//g' )
    result=$(echo "$result" | tr -d '\n\r'  )
    result=$(echo "$result" | tr '|' '\n' )
    #echo "$result" >html_output.txt
    IFS=$'\n' read -r -d '' -a result_lines <<< "$result"
    
    IFS=';' read -r -d '' -a array_mat <<< "${result_lines[$(expr $dagens_nummer + 1)]}"
    mat+=("${array_mat[2]} ${array_mat[4]}")
    
    # Hämta dag
    IFS=';' read -r -d '' -a dag_array<<< $(echo "$result" | grep 'Idag')
    dag+=("$(echo "${dag_array[6]} ${dag_array[7]}" | sed -e 's/&nbsp//g' )")

    ;;
    "${pages[4]}" )
      # Schema
      #echo "Time page"
    result=$(echo "$HTTP_BODY" | grep -P -o '<div class="content_wrapper" id="content">\K.*?(?=<\/table><\/div><\/div>)')
    result=$(echo "$result" | sed -e 's/<tr[^>]*>/|/g'  )
    result=$(echo "$result" | tr -d '\n\r'  )
    result=$(echo "$result" | tr '|' '\n' | sed '/^ *$/d' )
    #echo "$result" >>html_output.txt
    #IFS=$'\n' read -r -d '' -a result_lines <<< "$result"
    
    #IFS=';' read -r -d '' -a array_mat <<< "${result_lines[$(expr $dagens_nummer + 1)]}"
    #aktiviteter+=("${array_mat[2]} ${array_mat[4]}")
    
    ;;
    esac # end case page
    
    fi # end status
    done # for loop pages
    done # for studenter
    
result=""
if [ "$output" == "json" ]; then
result="\"updated\": \"$(date +'%Y-%m-%d %T.0%z')\","

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
result="updated: $(date +'%Y-%m-%d %T.0%z')\n"
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


