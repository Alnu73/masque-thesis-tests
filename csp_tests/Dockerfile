FROM ubuntu:latest
COPY utils /home/utils
COPY cmd_timestat.sh execute.sh run_measurements.sh /home/
COPY libs_curl/lib/ /usr/lib/x86_64-linux-gnu/
COPY libs_curl/lib64/ /usr/lib64/
RUN --mount=target=/var/lib/apt/lists,type=cache,sharing=locked \
    --mount=target=/var/cache/apt,type=cache,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
&& apt-get update \
&& apt-get install -y \
   curl \
   datamash \
   iperf3 \
   iproute2 \
   iputils-ping \
   libglib2.0-0 \
   libnss3 \
   libnss3-tools \
   python3 \
   python3-pip \
   tcpdump \
   sudo \
   squid-openssl \
   wget \
&& apt-get clean && apt-get autoclean && apt-get autoremove && rm -rf /var/lib/apt/lists/*

RUN pip3 install \
    pyOpenSSL \
    service-identity \
    Twisted

RUN ["chmod", "+x", "/home/run_measurements.sh"]
ENTRYPOINT ["/home/run_measurements.sh"]
