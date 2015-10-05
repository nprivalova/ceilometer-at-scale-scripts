#!/bin/bash

TOP_DIR={TOP_DIR:-"/tmp/rally_tempest_deploy/helpers/ceilometer/"}

CEILOMETER_STATS_DIR="/tmp/ceilometer_stats"

packages_install() {
    distro=`ssh $1 "cat /etc/*release | grep -Eo \"Ubuntu|CentOS\"" | head -n 1`
if [ ! -z "$distro" ]; then
    if [[ "$distro" == "CentOS" ]]; then ssh $1 "yum install $2 -y";
    elif [[ "$distro" == "Ubuntu" ]]; then ssh $1 "apt-get install $2 -y";
    else error "Distributor on controllers is unknown";
    fi
else error "Distributor on controllers not determined";
fi
}

available_ceilometer() {
if [ ! -z "`fuel node | grep mongo`" ]; then

    # Create massive with controllers
    controller_numbers=`fuel nodes | grep "controller" | awk '{print $1}'`
    controllers=(); for i in ${controller_numbers[*]}; do controllers+=("node-$i"); done

    node_numbers=`fuel nodes | grep ready | awk '{print $1}'`
    nodes=(); for i in ${node_numbers[*]}; do nodes+=("node-$i"); done

    mongo_numbers=`fuel nodes | grep mongo | awk '{print $1}'`
    mongos=(); for i in ${mongo_numbers[*]}; do mongos+=("node-$i"); done

    return 1;
    else message "Mongo role not found in controllers. Logging not run."; return 0;
fi
}

# TODO(ityaptin) try to make it via pcs
prepare_rabbitmq(){
    curl https://raw.githubusercontent.com/rabbitmq/rabbitmq-management/rabbitmq_v3_5_4/bin/rabbitmqadmin >> /usr/local/bin/rabbitmqadmin
    chmod +x /usr/local/bin/rabbitmqadmin
    rabbitmq-plugins enable rabbitmq_management
    service rabbitmq-server restart
}


file_size_limitation() {
    ssh $1 <<EOF
    if [ -d $CEILOMETER_STATS_DIR ]; then rm -rf $CEILOMETER_STATS_DIR/*; else mkdir $CEILOMETER_STATS_DIR; fi
    cd $CEILOMETER_STATS_DIR
    screen -dmS filelimitation /bin/bash -c "while true ;
    do
        for logfile in `ls`; do
            actualsize=$(du --block-size=G $logfile | cut -f 1)
            if [ $actualsize -ge 2 ];
                scrs=`screen -ls | egrep "statlogceilo" | awk {'print $1'}`
                for i in $scrs; do screen -X -S $i quit; done
                screen -X -S filelimitation quit
            fi

        done
    done
    "
EOF
}

deploy_ps_stats_scripts() {
    #packages_install $1 "vim screen"
    file_size_limitation $1
    scp ${TOP_DIR}/ceilometer_ps_stats.sh "root@${1}:${CEILOMETER_STATS_DIR}/"

}

run_ps_stats_scripts(){
    ps_cmd="${CEILOMETER_STATS_DIR}/ceilometer_ps_stats.sh ${CEILOMETER_STATS_DIR}/$1-ps-stats.log 5"
    ssh root@${1} "screen -dmS statlogceilo /bin/bash -c ${ps_cmd}"
}

deploy_mongo_scripts(){
    #packages_install $1 "vim screen"
    file_size_limitation $1

    scp ${TOP_DIR}/mongo_stats.py root@${1}:${CEILOMETER_STATS_DIR}/
    scp ${TOP_DIR}/rabbitmq_stats.sh root@${1}:${CEILOMETER_STATS_DIR}/
}

run_mongo_stats_scripts(){
    mongourl=`ssh ${controllers[0]} "cat /etc/ceilometer/ceilometer.conf | grep "^[^#].*mongo" | sed 's/connection=//; s:ceilometer:admin:g'"`
    ssh root${1} "screen -dmS statlogceilo python ${CEILOMETER_STATS_DIR}/mongo_stats.py --url $mongourl --result $CEILOMETER_STATS_DIR/$1-mongo-stats.log"
}

deploy_rabbit_scripts(){
    #packages_install $1 "vim screen"
    file_size_limitation $1

    scp ${TOP_DIR}/rabbitmq_stats.sh root@${1}:${CEILOMETER_STATS_DIR}/
}


run_rabbit_stats_scripts(){
    rabbit_stats_cmd="$CEILOMETER_STATS_DIR/rabbitmq_stats.sh ${CEILOMETER_STATS_DIR}/$1-rabbitmq_stats.log 5"
    ssh root@${1} "screen -dmS statlogceilo /bin/bash -c ${rabbit_stats_cmd}"
}

deploy_ceilometer_logs() {

    if available_ceilometer; then return; fi


    for node in ${nodes[*]}
    do
        if [ ! -z ${node} ]; then
            deploy_ps_stats_scripts ${node}
        fi
    done

    deploy_mongo_scripts ${controllers[0]}
    deploy_rabbit_scripts ${controllers[0]}

}

start_ceilometer_logs(){
    if available_ceilometer; then return; fi
    for node in ${nodes[*]}
    do
        if [ ! -z ${node} ]; then
            run_ps_stats_scripts ${node}
        fi
    done
    for mongo in ${mongos[*]}
    do
        run_mongo_stats_scripts ${mongo}
    done
    for controller in ${controllers[*]}
    do
        run_rabbit_stats_scripts ${controller}
    done

}


stop_ceilometer_screens() {
    scrs=`ssh root@$1 "screen -ls | egrep \"statlogceilo|filelimitation\"" | awk {'print $1'}`
    for i in $scrs; do ssh root@$1 "screen -X -S $i quit"; done
}

delete_ceilometer_files() {
    ssh root@$1 "rm -rf $CEILOMETER_STATS_DIR"
}

stop_ceilometer_logs() {

    if available_ceilometer; then return; fi


    if [ -d $CEILOMETER_STATS_DIR/ ]; then rm -rf $CEILOMETER_STATS_DIR/; fi
    mkdir $CEILOMETER_STATS_DIR/

    for node in ${nodes[*]}
    do
        if [ ! -z ${node} ]; then

            echo "STOP ${node}"
            stop_ceilometer_screens ${node}
            scp "root@${node}:$CEILOMETER_STATS_DIR/*stats.log" $CEILOMETER_STATS_DIR/
            delete_ceilometer_files ${node}
        fi
    done
}

collect_ceilometer_logs(){
    CEILOMETER_RESULT_DIR=${1:-"/var/www/test_results"}
    /usr/local/bin/python2.7 ${TOP_DIR}/generate_report.py --output "$CEILOMETER_RESULT_DIR/ceilometer_stats.html" --logdir "$CEILOMETER_STATS_DIR" --templates-dir "${TOP_DIR}/template"
}

