#!/bin/bash
TIMEFORMAT=$'%R\t%U\t%S'   #%0lR for slow executing commands
SAVEPATH="/home/res"
help_msg="Positional arguments: \n\tCommand: Complete command to analyse the duration of.\n\nFlag arguments: \n\t-h help\n\t-q quiet mode, suppress the inner command output.\n\t-c compact mode, show the results as comma-separated numbers.\n\t-e log errors to errors.log file\n\t-r retry command in case of error\n\t-n number of iterations.\n\t-m [csv/txt] save measurements in the specified format.\n\t-s result file save base path\n\t-d string to be deleted from the error log, useful in case of commands that print everything to the stderr"
comma_output=false
suppress_output=false
log_errors=false
retry=false
n_iterations=1

outfile="$(mktemp /tmp/output.XXXXXXXXXX)" || { echo "Failed to create temp file"; exit 1; }
errfile="$(mktemp /tmp/err.XXXXXXXXXX)" || { echo "Failed to create temp file"; exit 1; }

while getopts 'hqecrm:n:s:d:' flag;
do
    case "${flag}" in
        h)
            echo -e "$help_msg"
            exit;;
        q)
            suppress_output=true;;
        e)
            log_errors=true;;
        c)
            comma_output=true;;
        r)
            retry=true;;
        m)
            save_measurements=${OPTARG};;
        n)
            n_iterations=${OPTARG};;
        s)
            SAVEPATH=${OPTARG};;
        d)
            del_string=${OPTARG};;
        *)
            echo "[$0]: Invalid flag! Exiting."
            exit;;
    esac
done
shift $(($OPTIND - 1))

command=( "$@" )
new_it=$n_iterations

function save_measurements () {
    if [[ "$save_measurements" == "txt" ]]; then
        echo "RealTime,UserTime,SysTime" > "$SAVEPATH/iterations.txt"
        cat "$outfile" >> "$SAVEPATH/iterations.txt"
    elif [[ "$save_measurements" == "csv" ]]; then
        echo "RealTime,UserTime,SysTime" > "$SAVEPATH/iterations.csv"
        cat "$outfile" >> "$SAVEPATH/iterations.csv"
    fi
}

function redirect_output() {
    if [[ "$suppress_output" = false ]]; then
        "$@" 2>"$errfile"
    else
        "$@" > /dev/null 2>"$errfile"
    fi
}

function detect_and_log_errors() {
    if [[ -n $del_string ]];then sed -i "/$del_string/I d" $errfile; fi
    if [[ -s $errfile ]] && [[ $retry == true ]]; then
        new_it=$((new_it+1))
        sed -i '$ d' "$outfile"
    fi
    if [[ $log_errors == true && -s $errfile ]]; then echo $(cat "$errfile") >> "$SAVEPATH/errors.log"; fi
}

i=0
while [ $i -lt $new_it ]; do
    { time redirect_output "${command[@]}" ; } 2>> "$outfile"
    detect_and_log_errors
    sleep 5
    i=$((i+1))
done

if [[ "$(locale decimal_point)" == "," ]]; then
    sed -i 's/\,/./g' "$outfile"
fi
sed -i 's/\t/,/g' "$outfile"
save_measurements
sed -i 's/,.*//' "$outfile"
out=$(datamash -t "," -R 3 mean 1 sstdev 1 median 1 min 1 max 1 q1 1 q3 1 perc:5 1 perc:95 1 < "$outfile")
echo "$out" > "$outfile"
if [[ "$comma_output" = false ]]; then
    results="Mean\tStdDev\tMedian\tMin\tMax\tFirstQuartile\tThirdQuartile\t5Percentile\t95Percentile\n$(cat "$outfile")"
else
    results=$(cat "$outfile")
fi

echo -e "$results"

rm "$outfile"
rm "$errfile"
