#!/usr/bin/env bash

stat_names=( cpu_util mem_util virtual_memory )

hostname=$(hostname)
log_file=$1
if [ -z "$log_file" ]; then
  log_file="/tmp/ceilometer_stats/${hostname}-ceilometer-ps-stats.log"
fi
sleep_time=$2
if [ -z "$sleep_time" ]; then
  sleep_time=5
fi

function write_stats() {
  names=($(ls /usr/bin/ | grep $1))
  for name in ${names[*]}; do
    pids=($(ps -eo pid,cmd | grep "$name " | awk '{print $1}'))
    for pid in ${pids[*]}; do
      ts=$(date +%s)
      stats_line=$(ps --pid ${pid} -o %cpu,%mem,vsize | awk 'NR==2')
      echo ${stats_line}
      IFS=' ' read -ra stats <<< "$stats_line"
      if [ -n "$stats" ]; then
         stats[2]="$((${stats[2]} / 1024))"

         for i in {0..2}; do
           echo -e "GAUGE\t${hostname}\tprocess_${name}/${stat_names[($i)]}\t${ts}\t${stats[($i)]}" >> ${log_file}
         done
      fi
    done
  done
}

echo "" > ${log_file}
while true; do
  sleep $sleep_time
  write_stats ceilometer
  write_stats mongo
done
