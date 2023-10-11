#!/bin/bash

WORKDIR="/home/res"

file_suffix=$(date +%F_%H:%M)
help_msg="Positional arguments: \n\tNumber of measurements\n\tNumber of iterations\n\tDelay in ms\n\tStep\n\tFile size in bytes\n\tMaximum bandwidth in Mbps\n\tPacket loss in percentage\n\nOptional arguments:\n\t-h help\n\t-v verbose output\n\t-f working directory for results\n\nNote: Docker must be running before this script is executed."
verbose=false
declare -a test_types=("masque" "tcp-tls_pro" "quic" "tcp-tls_no-pro")

while getopts ':hvpf:' flag;
do
    case "${flag}" in
        h)
            echo -e "$help_msg"
            exit;;
        v)
            verbose=true;;
        f)
            WORKDIR=${OPTARG};;
        *)
            echo "[$0]: Invalid flag! Exiting."
            exit;;
    esac
done
shift $(($OPTIND - 1))

delay=$3
step=$4
loss=$7
folder_name="test_$file_suffix"
folder_path="$WORKDIR/tests/$folder_name"

function log () {
    if [ "$verbose" = true ]; then
        echo -e "$@"
    fi
}

function build_args () {
    if [[ "$type" =~ ^(masque|tcp-tls_pro)$ ]]; then
        d_loss=$(awk -v loss=$loss 'BEGIN{d_loss=(loss/4); print d_loss;}')
        test_opts="-l $d_loss -b $6 -c $delay -s $delay"
        test_args="$1 $2 $4 $5"
    else
        d_loss=$(awk -v loss=$loss 'BEGIN{d_loss=(loss/2); print d_loss;}')
        test_opts="-l $d_loss -b $6 -c $(( 2*delay ))"
        test_args="$1 $2 $(( 2*step )) $5"
    fi
    if [ "$verbose" == true ]; then test_opts="-v $test_opts"; fi
    test_opts="$test_opts -f $folder_path/$type"
}

log "Creating main directory"
mkdir -p "$folder_path/results/plots"
mkdir -p "$folder_path/results/plots/ecdf"

for type in "${test_types[@]}"
do
    log "Creating directories and sub-directories for $type experiment"
    mkdir -p "$folder_path/$type/iterations" "$folder_path/$type/measurements" "$folder_path/$type/experiments" "$folder_path/$type/errors"
    build_args "$@"
    log "#########   $type   #########"
    $WORKDIR/docker_tests.sh $test_opts $type $test_args
done
log "All experiments done. Beginning merging..."
awk '(NR == 1) || (FNR > 1)' $folder_path/*/experiments/*.csv > "$folder_path/results/result_summary.csv"
awk '(NR == 1) || (FNR > 1)' $folder_path/*/iterations/*.csv > "$folder_path/results/result_expanded.csv"
cat $folder_path/*/errors/*.log > "$folder_path/results/errors.log"
log "Success! Results are available in $folder_path/results/result.csv"
