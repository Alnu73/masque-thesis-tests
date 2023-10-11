#!/bin/bash

WORK_DIR="/home/utils"
TEMPFS_DIR="/dev/shm/sites-data"

help_msg="Client: [-s] server address, [-p] proxy address, [-o] object size\nServer: [-s] server address, [-w] website, [-o] object size\nProxy: [-p] proxy address, [-w] website"
website=www.example.org
website_name="${website%%/*}"

while getopts ':hp:s:w:o:' flag;
do
    case "${flag}" in
        h)
            echo -e $help_msg
            exit;;
        p)
            proxy_addr=${OPTARG}
            proxy_port=${proxy_addr#*:};;
        s)
            server_addr=${OPTARG}
            server_port=${server_addr#*:};;
        w)
            website=${OPTARG}
            website_name="${website%%/*}";;
        o)
            obj_size=${OPTARG}
            obj_size_mb=$(numfmt --to si --format "%6.0f" $obj_size)
            obj_size_mb=${obj_size_mb// }
            obj_name=${obj_size_mb}.txt;;
        *)
            echo "[$0]: Invalid flag! Exiting."
            exit;;
    esac
done
shift $(($OPTIND - 1))

function configure_server () {
    # Creating folder for quic data
    echo "Configuring server ($3) for $1 at address $2"
    mkdir -p $TEMPFS_DIR
    cd $TEMPFS_DIR || return
    if [ ! -d $TEMPFS_DIR/$1 ]; then
        prepare_site_data $1 $2 $3
    else
        echo "Website already saved. Moving on."
    fi
}

#This function is present for completeness but basically never called (we always skip cert verification)
function generate_certificates () {
    if [ ! -d $WORK_DIR/certs/cert_$1/ ]; then
        # Prepare for certificate
        mkdir -p $WORK_DIR/certs
        sed -i '20d' $WORK_DIR/certs/leaf.cnf &&  sed -i "20i\DNS.1 = $1" $WORK_DIR/certs/leaf.cnf
        cd $WORK_DIR/certs || return
        $WORK_DIR/certs/gen_cert.sh
        # Rename certificate folder for more flexibility
        mv $WORK_DIR/certs/out $WORK_DIR/certs/cert_$1
        cd $WORK_DIR/certs/cert_$1 || return
        # Initialize certutil, if needed
        if [ ! -d $HOME/.pki/nssdb ]; then
            mkdir -p $HOME/.pki/nssdb
            certutil -d $HOME/.pki/nssdb -N
        fi
        # Trust certificate
        certutil -d sql:$HOME/.pki/nssdb -A -t "C,," -n quic_ex_cert -i 2048-sha256-root.pem
    else
        echo "Certificates already present. Moving on."
    fi
}

function prepare_site_data () {
    mkdir -p $TEMPFS_DIR/www.example.org
    echo -e "X-Original-Url: https://$2/\nHTTP/1.1 200 OK" > $TEMPFS_DIR/$1/index.html
    #sites-data is a tmpfs, so its content is deleted after reboot
    if [ ! -f $TEMPFS_DIR/$website_name/$obj_name ] && [ ! -z "${obj_size_mb}" ]; then
        #Generates file to download based on the -o argument
        echo "Generating $obj_size_mb file to download ($obj_name)"
        if [ $3 == "quic_server" ]; then
            echo -e "X-Original-Url: https://$2/$obj_name/\nHTTP/1.1 200 OK\n" >> $TEMPFS_DIR/$website_name/$obj_name
        fi
        #dd if=/dev/random of=$TEMPFS_DIR/$website_name/$obj_name  bs=$obj_size_mb  count=1
        dd if=/dev/random bs=$obj_size_mb seek=1 count=0 of=$TEMPFS_DIR/$website_name/$obj_name
    fi
}

case $1 in
    "http_client")
        echo "Starting HTTP client..."
        echo "Running client to server $server_addr"
        if [ -n "${proxy_addr}" ]; then
            echo "Downloading $obj_size_mb file ($obj_name) through proxy $proxy_addr."
            curl -kfsS --connect-timeout 5 -x $proxy_addr -L https://$server_addr/$obj_name > /dev/null
        else
            echo "Downloading $obj_size_mb file ($obj_name) without proxy"
            curl -kfsS --connect-timeout 5 -L https://$server_addr/$obj_name > /dev/null
        fi
        ;;
    "quic_client_curl")
        echo "Starting QUIC client (curl)..."
        $WORK_DIR/scripts/curl/src/curl -kfsS --connect-timeout 5 --http3 https://$server_addr/$obj_name > /dev/null
        ;;
    "quic_client")
        echo "Starting QUIC client..."
        $WORK_DIR/scripts/quic_client --disable_certificate_verification=true https://$server_addr/$obj_name
        ;;
    "masque_client")
        echo "Starting MASQUE client..."
        echo "Running client to server $server_addr through proxy $proxy_addr. Downloading $obj_size bytes"
        $WORK_DIR/scripts/masque_client --allow_unknown_root_cert=true --disable_certificate_verification=true $proxy_addr https://$server_addr/$obj_name
        ;;
    "http_server")
        echo "Starting HTTP server..."
        serverip=${server_addr%%:*}
        configure_server $website_name $serverip $1
        echo "Running server at IP $serverip, port $server_port, hosting $obj_size_mb file"
        twistd -no web -c $WORK_DIR/certs/cert.pem -k $WORK_DIR/certs/ukey.pem --path $TEMPFS_DIR/$website_name/ --https $server_port
        ;;
    "quic_server")
        echo "Starting QUICHE server..."
        serverip=${server_addr%%:*}
        configure_server $website_name $serverip $1
        echo "Running server at IP $serverip, port $server_port to website $website"
        $WORK_DIR/scripts/quiche-server --listen $server_addr --cert $WORK_DIR/certs/cert.crt --key $WORK_DIR/certs/cert.key --root $TEMPFS_DIR/$website --idle-timeout 1000
        ;;
    "http_proxy")
        echo "Starting HTTP proxy..."
        cp $WORK_DIR/squid.conf /etc/squid/squid.conf
        /usr/lib/squid/security_file_certgen -c -s /var/spool/squid/ssl_db -M 4MB
        squid -NCd1
        echo "Running proxy at port $proxy_port to website $website"
        ;;
    "masque_proxy")
        echo "Starting MASQUE proxy..."
        echo "Running proxy at port $proxy_port to website $website"
        $WORK_DIR/scripts/masque_server \
            --port=$proxy_port \
            --allow_unknown_root_cert=true \
            --certificate_file=$WORK_DIR/certs/leaf_cert.pem \
            --key_file=$WORK_DIR/certs/leaf_cert.pkcs8
        ;;
    *)
        echo "Possible options: http_client, quic_client, masque_client, http_server, quic_server, http_proxy, masque_proxy. Try again."

esac
