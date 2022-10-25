#!/bin/bash
# This code is partialy taken from https://github.com/alfiosalanitri/server-guardian and changed.
# This is a simple bash script that monitor the server high cpu and ram usage and check the systemctl services status.
# If the ram or cpu usage is greather then limit or a service is failed, send a message to telegram user
#
# Require telegram bot and telegram user
#
# written by Samhamsam and are licensed under MIT license.
set -e

PATH=/sbin:/bin:/usr/sbin:/usr/bin

current_path="/etc/server-guardian" # Change this if you made a link.
cd $current_path # If this was called from link we have to change directory.


##########################
# Default options
##########################
watch_cpu=false
watch_ram=false
watch_services=false
watch_hard_disk=false
watch_smart=false

server_name=$(hostname | sed 's/-//g')

log_folder="./logs" # If you change this please change also in logrotate.conf
log_file="${log_folder}/server_guardian.log"
last_report_file="${log_folder}/last_report.txt"

telegram_bot_token=""
telegram_user_chat_id=""
telegram_title="Server - $server_name:"

# CPU WARNING LEVEL
# -high: to receive an alert if the load average of last minute is greater than cpu core number. 
# -medium: watch the value of the latest 5 minutes. (default)
# -low: watch the value of the latest 15 minuts.
cpu_warning_level=medium 
folders_to_watch_disk_space="/ /backupDevice" # Example: folders_to_watch_disk_space="/ /backup /test"
ram_perc_limit=60
disk_space_perc_limit=85
smart_devices="sda sdb"

##########################
# Functions
##########################
display_help() {
cat << EOF

Copyright (C) 2022 by Samhamsam
Usage: $(basename $0) -ws -wc -wr -wh
Options
-wc / --watch-cpu        To enable check for high cpu usage
-wr / --watch-ram        To enable check for high ram usage
-wh / --watch-hard-disk  To enable check for hard disk free space
-ws / --watch-smart	 To enable watch for smart devices
-h, --help               Show this help Message

-------------
EOF
exit 0
}
# send the message to telegram with curl

log_message() {
  current_date="$(date +'%m/%d/%Y - %H:%M')"
  echo "${current_date} - $1" >> "${log_file}"
  logrotate -v -s "${log_folder}/logrotate.status" ./logrotate.conf
}

send_message() {
  telegram_message="\`$1\`"
  
  # store top results to file
  if [ "yes" == $2 ]; then
    top -n1 -b > "${last_report_file}"
    telegram_message="${telegram_message}"
  fi

  log_message "${telegram_message}"

  esc_telegram_message=$(echo "$telegram_message" | sed "s/\./\\\./g" | sed "s/\-/\\\-/g" | sed "s/\*/\\\*/g" | sed "s/\[/\\\[/g" | sed "s/\`/\\\`/g")
  esc_telegram_title=$(echo "$telegram_title" | sed "s/\./\\\./g" | sed "s/\-/\\\-/g" | sed "s/\*/\\\*/g" | sed "s/\[/\\\[/g" | sed "s/\`/\\\`/g")

  curl -s -X POST "https://api.telegram.org/bot$telegram_bot_token/sendMessage" -F chat_id=$telegram_user_chat_id -F text="$esc_telegram_title $esc_telegram_message" -F parse_mode="MarkdownV2"
}


##########################
# Get options from cli
##########################
while [[ $# -gt 0 ]]; do
  case $1 in
    -wc | --watch-cpu)
      watch_cpu=true
      shift
      ;;
    -wr | --watch-ram)
      watch_ram=true
      shift
      ;;
    -ws | --watch-services)
      watch_smart=true
      shift
      ;;
    -wh | --watch-hard-disk)
      watch_hard_disk=true
      shift
      ;;
    -wm | --watch-mdadm)
      watch_mdadm=true
      shift
      ;;
    -h | --help)
      display_help
      exit 0
      shift
      ;;
    
    *)
      display_help
      shift
      ;;
  esac
done


##########################
# Check options and config
##########################
# Check telegram bot key and chat id
if test -z $telegram_bot_token || test -z $telegram_user_chat_id; then
  printf "Please set \$telegram_bot_token and \$telegram_user_chat_id.\n"
  exit 1
fi

##########################
# Start monitor
##########################
# --------------------------------------------------------------------------------
# Get the load average value and if is greather than 100% send an alert and exit
if test $watch_cpu = true; then
  echo "Start check CPU"
  server_core=$(lscpu | grep '^CPU(s)' | awk '{print int($2)}')
  load_avg=$(uptime | grep -ohe 'load average[s:][: ].*')
  avg_position='$4' #avg 5min
  case $cpu_warning_level in 
    low)
      avg_position='$5' #avg 15min
      ;;
    high)
      avg_position='$3' #avg 1min
      ;;
  esac
  load_avg_for_minutes=$(uptime | grep -ohe 'load average[s:][: ].*' | awk '{ print '$avg_position'}' | sed -e 's/,/./' | sed -e 's/,//' | awk '{print int($1)}')
  load_avg_percentage=$(($load_avg_for_minutes * 100 / $server_core))
  if [ $load_avg_percentage -ge 100 ]; then
    message="High CPU usage: $load_avg_percentage% - $load_avg (1min, 5min, 15min)"
    send_message "$message" "yes"
  fi
fi

# --------------------------------------------------------------------------------
# Get the ram usage value and if is greather then limit, send the message and exit
if test $watch_ram = true; then
  echo "Start check RAM"
  # Lang: English
  ram_usage=$(free | awk '/Mem/{printf("RAM Usage: %.0f\n"), $3/$2*100}' | awk '{print $3}')
  # Lang: German
  #ram_usage=$(free | awk '/Speicher/{printf("benutzt: %.0f\n"), $3/$2*100}' | awk '{print $2}')
  if test "$ram_usage" -gt $ram_perc_limit; then
    message="High RAM usage: $ram_usage%"
    send_message "$message" "yes"
  fi
fi

# --------------------------------------------------------------------------------
# Check the systemctl services and if one or more are failed, send an alert and exit
if test $watch_services = true; then
  echo "Start check SERVICES"
  services=$(sudo systemctl --failed | awk '{if (NR!=1) {print}}' | head -2)
  if [[ $services != *"0 loaded"* ]]; then
    message="Systemctl failed services: $services"
    send_message "$message" "no"
  fi
fi

# --------------------------------------------------------------------------------
# Check the free disk space
if test $watch_hard_disk = true; then
  echo "Start check DISK"
  for folder in $folders_to_watch_disk_space; do
    disk_perc_used=$(df "$folder" --output=pcent | tr -cd 0-9)
    if [ "$disk_perc_used" -gt $disk_space_perc_limit ]; then
      message="Hard disk $folder full (space used $disk_perc_used%)"
      send_message "$message" "no"
    fi
  done
fi

# check smart disk state
if test $watch_smart = true; then
  for device in $smart_devices; do
    echo "Start checking mdadm device: ${device}"
    fullpath="/dev/${device}"
    if ! test -e ${fullpath}; then 
      message="Smart device $device does not exist anymore!"
      send_message "$message" "no"
    fi
    smart=$(
      sudo smartctl -H $fullpath 2>/dev/null |
      grep '^SMART overall' |
      awk '{ print $6 }'
    )

    if test "${smart}" = ""; then
      message="Smart device $device does not exist anymore!"
      send_message "$message" "no"
    fi
    
    if test ${smart} != "PASSED"; then
      message="Smart device $device is faulty!"
      send_message "$message" "no"
    fi
  done
fi


date > ${log_folder}/last_run

printf "\nFinished watching.\n"
exit 0
