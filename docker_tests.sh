#!/bin/bash
#Docker must be running before running this
#command -v -c <delay_cli> -s <delay_ser> -p <delay_pro> -f <file_save_path> -b <bandwidth> <type> <num_measurements> <num_iterations_cli> <step> <size>

help_msg="Positional arguments: \n\tTest type: masque, quic, tcp-tls_pro, tcp-tls_no-pro\n\tNumber of client measurements: the client delay changes for each measurement\n\tNumber of client iterations: number of time measurements within each client measurement for time\n\tStep: variation of delay for each experiment and measurement\n\tFile size: size of the file to download in bytes\n\nOptional arguments with parameter: \n\t-c client delay\n\t-s server delay\n\t-p proxy delay\n\t-b maximum bandwidth of client and server in Mbps\n\t-f absolute path for results file\n\nOptional arguments without parameter:\n\t-h help\n\t-v verbose output\n\nNote: Docker must be running before this script is executed."

file_save_path="/home/res"
verbose=false

while getopts ':hvc:s:p:b:f:l:' flag;
do
    case "${flag}" in
        h)
            echo -e $help_msg
            exit;;
        v)
            verbose=true;;
        c)
            delay_cli=${OPTARG};;
        s)
            delay_ser=${OPTARG};;
        p)
            delay_pro=${OPTARG};;
        b)
            max_bandwidth=${OPTARG};;
        f)
            file_save_path=${OPTARG};;
        l)
            packet_loss=${OPTARG};;
        *)
            echo "[$0]: Invalid flag! Exiting."
            exit;;
    esac
done
shift $(($OPTIND - 1))

case $1 in
    "masque")
        server_type="quic_server"
        proxy_type="masque_proxy"
        client_type="masque_client"
        server_addr=172.18.0.2:6121
        proxy_addr=172.18.0.3:6122;;
    "quic")
        server_type="quic_server"
        client_type="quic_client"
        server_addr=172.18.0.2:6121;;
    "tcp-tls_pro")
        server_type="http_server"
        proxy_type="http_proxy"
        client_type="http_client"
        server_addr=172.18.0.2:8081
        proxy_addr=172.18.0.3:3128;;
    "tcp-tls_no-pro")
        server_type="http_server"
        client_type="http_client"
        server_addr=172.18.0.2:8081;;
    *)
        echo "Possible choices: masque, quic, tcp-tls_pro, tcp-tls_no-pro"
        exit
esac

res_file_name="${client_type}_res.csv"
current_delay_ser=$delay_ser
current_delay_pro=$delay_pro
current_delay_cli=$delay_cli
obj_size=$5
obj_size_mb=$(numfmt --to si --format "%6.0f" $obj_size)
obj_size_mb=${obj_size_mb// }
obj_name=${obj_size_mb}.txt
shm_size=$(($obj_size + 64000000))
shm_size_mb=$(numfmt --to si --format "%6.0f" $shm_size)
shm_size_mb=${shm_size_mb// }

function ctrl_c() {
        echo "** Trapped CTRL-C"
        echo "Stopping all containers"
        docker stop "$(docker ps -a -q)"
        docker rm "$(docker ps --filter status=exited -q)"
}

function log () {
    if [ "$verbose" = true ]; then
        echo -e "$@"
    fi
}

function build_args () {
    if [ -n "$obj_size" ]; then gen_opts="-o $obj_size"; fi
    if [ -n "$current_delay_cli" ]; then tc_opts_cli="-c $current_delay_cli"; fi
    if [ -n "$current_delay_ser" ]; then tc_opts_ser="-s $current_delay_ser"; fi
    if [ -n "$current_delay_pro" ]; then tc_opts_pro="-p $current_delay_pro"; fi
    if [ -n "$max_bandwidth" ]; then
        tc_opts_cli="$tc_opts_cli -b $max_bandwidth"
        tc_opts_ser="$tc_opts_ser -b $max_bandwidth"
    fi
    if [ -n "$packet_loss" ]; then
        tc_opts_cli="$tc_opts_cli -l $packet_loss"
        tc_opts_ser="$tc_opts_ser -l $packet_loss"
        tc_opts_pro="$tc_opts_pro -l $packet_loss"
    fi
    if [ "$verbose" == true ]; then gen_opts="-v $gen_opts"; fi
    client_opts="$gen_opts $tc_opts_cli -i $3"
    server_opts="$gen_opts $tc_opts_ser"
    proxy_opts="$gen_opts $tc_opts_pro"
}

function wait_for_file () {
    if [ -n "$obj_size" ]; then
        log "$client_type waiting for file to be available on server"
        docker exec cspser cat /dev/shm/sites-data/www.example.org/$obj_name > /dev/null
        while [ $? -ne 0 ]; do docker exec cspser cat /dev/shm/sites-data/www.example.org/$obj_name > /dev/null; log "Waiting..."; sleep 1; done
    fi
}

function process_csv () {
    awk -i inplace -v content=$1 'BEGIN{FS=OFS=","} FNR==1{str="Category"} FNR>1{str=content} {print str FS $0}' "$file_save_path/measurements/$res_file_name"
    awk -i inplace -v content="$current_delay_ser,$current_delay_pro,$total_delay" 'BEGIN{FS=OFS=","} FNR==1{str="ServerDelay,ProxyDelay,TotalDelay"} FNR>1{str=content} $5 = $5 FS str' "$file_save_path/measurements/$res_file_name"
    awk -i inplace -v content="$1,$obj_size_mb,$max_bandwidth, $packet_loss,$current_delay_cli,$current_delay_ser,$current_delay_pro,$total_delay" 'BEGIN{FS=OFS=","} FNR==1{str="Category,FileSize,MaxBandwidth,Loss,ClientDelay,ServerDelay,ProxyDelay,TotalDelay"} FNR>1{str=content} {print str FS $0}' "$file_save_path/iterations/iterations.csv"
    awk -i inplace 'BEGIN{FS=OFS=","} FNR==1{str="CPUTime"} FNR>1{str=$10+$11} {print $0 FS str}' "$file_save_path/iterations/iterations.csv"
    #sed -i '/connected/I d' $file_save_path/errors/errors.log       #shouldn't be needed anymore
    mv "$file_save_path/iterations/iterations.csv" "$file_save_path/iterations/iterations_${2}.csv"
    if [ -f  "$file_save_path/errors/errors.log" ]; then
        mv "$file_save_path/errors/errors.log" "$file_save_path/errors/errors_${2}.log"
    fi
    mv "$file_save_path/measurements/$res_file_name" "$file_save_path/measurements/${client_type}_measurement_${2}.csv"
}

trap ctrl_c INT

log "Running experiment: $1 ($client_type--$proxy_type-->$server_type)"
log "Server starting delay is ${current_delay_ser}ms, proxy starting delay is ${current_delay_pro}ms and client starting delay is ${current_delay_cli}ms.\nStep is $4 and number of measurements per experiment is $2. Bandwidth is limited to ${max_bandwidth}Mbps. Packet loss at ${packet_loss}"
for i in $(seq $2); do
    log "Running $i/$2 measurement"
    build_args "$@"
    log "Server delay is ${current_delay_ser}ms, proxy delay is ${current_delay_pro}ms and client delay is ${current_delay_cli}ms."
    #Run server
    docker run -d --name cspser --cpuset-cpus="1" --network br12 --shm-size=$shm_size_mb --cap-add=NET_ADMIN csp_tests $server_opts $server_type $server_addr $proxy_addr > /dev/null
    #Run proxy
    if [ -n "$proxy_addr" ]; then
        docker run -d --name csppro --cpuset-cpus="2" --network br12 --cap-add=NET_ADMIN csp_tests $proxy_opts $proxy_type $server_addr $proxy_addr > /dev/null
    else
        log "Case without proxy."
    fi
    wait_for_file
    #Run client
    if [ "$verbose" = true ]; then
        docker run --name cspcli --cpuset-cpus="3" --network br12 --cap-add=NET_ADMIN csp_tests -qv $client_opts $client_type $server_addr $proxy_addr
    else
        docker run --name cspcli --cpuset-cpus="3" --network br12 --cap-add=NET_ADMIN csp_tests -q $client_opts $client_type $server_addr $proxy_addr > /dev/null
    fi
    docker cp cspcli:/home/res/$res_file_name $file_save_path/measurements > /dev/null
    docker cp cspcli:/home/res/iterations.csv $file_save_path/iterations > /dev/null
    docker cp cspcli:/home/res/errors.log $file_save_path/errors > /dev/null
    log "Copied results file from cspcli container"
    docker rm --force cspcli > /dev/null
    docker rm --force cspser > /dev/null
    docker rm --force csppro > /dev/null 2>&1
    log "Containers removed"
    if [[ "$1" =~ ^(masque|tcp-tls_pro)$ ]]; then
        total_delay=$(($current_delay_cli + $current_delay_ser))
    else
        total_delay=$current_delay_cli
    fi
    process_csv $1 $i $v_loss
    if [ -n "$delay_cli" ]; then current_delay_cli=$(($current_delay_cli + $4)); fi
    if [ -n "$delay_ser" ]; then current_delay_ser=$(($current_delay_ser + $4)); fi
    if [ -n "$delay_pro" ]; then current_delay_pro=$(($current_delay_pro + $4)); fi
done
log "Merging measurements csv files..."
cd $file_save_path/measurements || exit
awk '(NR == 1) || (FNR > 1)' ${client_type}*.csv > "$file_save_path/experiments/${1}_experiment.csv"
cd $file_save_path/experiments || exit
awk -F ',' 'NR == 1; NR > 1 {print $0 | "sort -t \",\" -n -k 6"}' "${1}_experiment.csv" > "output.tmp" && mv "output.tmp" "${1}_experiment.csv"
log "Experiment done. Results are available at $file_save_path/experiments/${1}_experiment.csv"
