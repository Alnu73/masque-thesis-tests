#!/bin/bash

#command -i <num_iterations> -c <client_delay> -s <server_delay> -p <proxy_delay> -o <object_size> <type> <server_address> <proxy_address>
WORKDIR="/home"
help_msg="Positional arguments: \n\tTest type: http_server, masque_proxy, quic_server, http_proxy, masque_proxy, masque_client, http_client. \n\tServer address: the client address (IP:PORT)\n\tProxy address: the proxy address (IP:PORT)\n\nFlag arguments: \n\t-h help\n\t-v verbose output\n\t-q quiet time measurement\n\t-p proxy delay in ms\n\t-s server delay in ms\n\t-c client delay in ms\n\t-b max bandwidth in Mbps\n\t-i number of requests\n\t-o size of object to download in bytes.\n\t-l packet loss"
verbose=false
quiet=false
iterations=1

while getopts 'hvqp:s:c:b:i:o:l:' flag;
do
    case "${flag}" in
        h)
            echo -e $help_msg
            exit;;
        v)
            verbose=true;;
        q)
            quiet=true;;
        p)
            proxy_delay=${OPTARG};;
        s)
            server_delay=${OPTARG};;
        c)
            client_delay=${OPTARG};;
        b)
            max_bandwidth=${OPTARG};;
        i)
            iterations=${OPTARG};;
        o)
            obj_size=${OPTARG};;
        l)
            packet_loss=${OPTARG};;
        *)
            echo "[$0]: Invalid flag! Exiting."
            exit;;
    esac
done
shift $(($OPTIND - 1))

function log () {
    if [ "$verbose" = true ]; then
        echo "$@"
    fi
}

function set_delay () {
    if [ "$2" -gt 0 ]; then
        if tc qdisc show dev eth0 | grep "delay" > /dev/null; then
            if [ "$3" -gt 0 ]; then
                tc qdisc change dev eth0 parent 1:1 handle 10: netem delay ${2}ms
            else
                tc qdisc change dev eth0 root netem delay ${2}ms
            fi
        else
            if [ "$3" -gt 0 ]; then
                tc qdisc add dev eth0 parent 1:1 handle 10: netem delay ${2}ms
            else
                tc qdisc add dev eth0 root netem delay ${2}ms
            fi
        fi
        log "$1 delay set: $(tc qdisc show dev eth0)"
    fi
}

function set_bandwidth () {
    if [ "$2" -gt 0 ]; then
        tc qdisc add dev eth0 root handle 1: tbf rate ${max_bandwidth}mbit burst 100kb limit 100kb
        log "$1 max bandwidth set: $(tc qdisc show dev eth0)"
    fi
}

function set_loss () {
    if tc qdisc show dev eth0 | grep "loss" > /dev/null; then
        if [ "$3" -gt 0 ]; then
            tc qdisc change dev eth0 parent 1:1 handle 10: netem delay 10ms loss ${2}%
        else
            tc qdisc change dev eth0 root netem delay 10ms loss ${2}%
        fi
    else
        if [ "$3" -gt 0 ]; then
            tc qdisc add dev eth0 parent 1:1 handle 10: netem delay 10ms loss ${2}%
        else
            tc qdisc add dev eth0 root netem delay 10ms loss ${2}%
        fi
    fi
    log "$1 loss set: $(tc qdisc show dev eth0)"
}


function test_client () {
    if [ -z "$3" ]; then
        log "$1: no proxy to run"
        client_args="-s $2 -o $obj_size $1"
    else
        client_args="-s $2 -p $3 -o $obj_size $1"
    fi
    file_prefix="$1_res"
    file_name="${file_prefix}.csv"
    if [ -n "$obj_size" ]; then
        obj_size_mb=$(numfmt --to si --format "%6.0f" $obj_size)
        obj_size_mb=${obj_size_mb// }
    fi
    mkdir -p $WORKDIR/res
    if [ ! -f /dev/shm/$file_name ]; then
        echo "FileSize, MaxBandwidth, Loss, ClientDelay, MeanTime, StdDev, Median, MinTime, MaxTime, FirstQuartile, ThirdQuartile, FifthPercentile, NiFifthPercentile" >> $WORKDIR/res/$file_name
    fi
    if [ "$quiet" = true ] ; then
        measured_time=$($WORKDIR/cmd_timestat.sh -qcer -d "connected" -m "csv" -n $iterations $WORKDIR/execute.sh $client_args 2>&1)
    else
        measured_time=$($WORKDIR/cmd_timestat.sh -cer -n $iterations $WORKDIR/execute.sh $client_args $1)
    fi
    echo "$obj_size_mb, ${max_bandwidth}Mbps, ${packet_loss}, $client_delay, $(echo $measured_time)" &>> $WORKDIR/res/$file_name
    log "--Experiment results (${client_delay}ms, $obj_size_mb file, $max_bandwidth Mbps, ${packet_loss}% loss)--"
    log "$(cat $WORKDIR/res/$file_name)"
}

if [[ "$1" =~ ^(http_server|quic_server)$ ]]; then
    log "Server setup mode: setting up $1"
    set_bandwidth $1 $max_bandwidth
    #set_delay $1 $server_delay $max_bandwidth
    set_loss $1 $packet_loss $max_bandwidth
    $WORKDIR/execute.sh -s $2 -o $obj_size $1
elif [[ "$1" =~ ^(masque_proxy|http_proxy)$ ]]; then
    log "Proxy setup mode: setting up $1"
    #set_delay $1 $proxy_delay $max_bandwidth
    set_loss $1 $packet_loss $max_bandwidth
    $WORKDIR/execute.sh -p $3 -o $obj_size $1
elif [[ "$1" =~ ^(http_client|quic_client|masque_client)$ ]]; then
    log "Client test mode: setting up $1"
    set_bandwidth $1 $max_bandwidth
    #set_delay $1 $client_delay $max_bandwidth
    set_loss $1 $packet_loss $max_bandwidth
    test_client $1 $2 $3
else
    echo "You entered $1: Not a possible choice! Exiting."
    exit
fi
