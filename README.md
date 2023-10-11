# Final thesis MASQUE experiments

## Description

Scripts and artifacts used for my final Master's Degree thesis in Computer and Electronic Engineering: _Performance assessment of the MASQUE extension for proxying scenarios in the QUIC transport protocol_.
A dedicated testing environment has been developed in order to evaluate the performance of MASQUE and compare it to other protocols under several simulated network conditions.

An experimental testing environment has been implemented and set up for the network emulation, test automation, post-processing and result saving. This environment has been used to evaluate MASQUE and compare it to other protocols under several network conditions. The tools used include Docker, Bash scripting, the Linux networking stack and traffic control techniques. All test cases consist of a client requesting a file of variable size using the HTTP GET method. Network conditions and characteristics are emulated using the Linux traffic control (_tc_) tool. In particular, four different test categories are considered and compared, two with proxies and two end-to-end: MASQUE, TCP+TLS with proxy, QUIC, TCP+TLS without proxy. 
The test categories are as follows:

* MASQUE
  *  Client: Google masque_client communicating to target server through proxy
  *  Proxy: Google masque_server at address 172.18.0.3 and port 6122
  *  Server: Cloudflare quiche_server at address 172.18.0.2 and port 6121
* TCP+TLS with proxy
  *  Client: curl communicating to target server through proxy
  *  Proxy:  Squid proxy at address 172.18.0.3 and port 3128
  *  Server: Twisted HTTPS server at address 172.18.0.2 and port 8081
* QUIC
  *  Client: Google quic_client directly communicating to target server
  *  Server: Cloudflare quiche_server at address 172.18.0.2 and port 6121
* TCP+TLS without proxy
  *  Client: curl directly communicating to target server
  *  Server: Twisted HTTPS server at address 172.18.0.2 and port 8081

In each measurement, a client sends a certain number of requests for a file to a server, either through a proxy or not, with a set delay a fixed bandwidth and, in case, a packet loss. On the other hand, an experiment is a set of measurements with a starting delay that is increased for each measurement, according to a step. The parameters of an experiment are the number of measurements, the number of iterations (requests) per measurement, the starting delay, the step, the file size, the bandwidth and finally the packet loss. An experiment is performed for a certain category, so a complete test includes four experiments, one for each possible category.
To sum up, a full test is made of four experiments, one for each category or scenario (MASQUE, TCP-TLS with proxy, QUIC and TCP-TLS without proxy). In turn, each experiment is made of M measurements, each with a different additional delay, distanced
according to a predefined step. In fact, a single measurement is described by an artificial delay, which results in an additional RTT, a fixed bandwidth, a packet loss, a file size and a summary of the measured time. This summary is calculated based on N iterations, each corresponding to a request that the client sends to the server for a file, either through a proxy or not. In other words, a test contains four experiments, each with M measurements, each with N iterations.

## Testing environment

The emulation setup consists of three Docker containers simulating a client, proxy and server for the tunneled scenario and two Docker containers simulating a client and a server for the end-to-end scenario. In any case, the server container hosts a sample website with a very simple index page and a file of arbitrary size created using the Linux dd command. The site data is stored on the /dev/shm shared memory for more efficiency and speed. A user-defined bridge has been created for the communication between containers, which share the same address space. The traffic control rules are applied to the eth0 interface of each container for the outgoing traffic, depending on the scenario considered. In particular, using _tc-netem_, the delay is symmetrically set on the client and server interface in the tunneled case and on the client interface only in the end-to-end cases, so that the total additional RTT is the same in all scenarios. On the other hand, the bandwidth is set by applying a Token Bucket Filter (tbf) filter on the client and server interface in all cases. As said, the delay changes incrementally for each measurement, while the bandwidth limitation stays the same. The packet loss is applied to each entity, but, like the delay, it is distributed so that the total loss is the same in the two sets of protocols. Each Docker container has net_admin capabilities in order to be able to apply traffic control rules, and server containers also have a dynamically set
shared memory size, based on the size of the file to host.

### Bash scripts

The scripts are divided into internal scripts and orchestration scripts.
The Docker emulation setup is regulated by three internal Bash scripts, one serving as the entrypoint of the containers, while two being utility scripts. The scripts are as follows, in a bottom-up order:
* **execute.sh**: configures and runs an entity, that can be a client, a server, or a proxy, in the QUIC, MASQUE or TCP+TLS (tunneled and end-to-end) scenarios, for a total of seven possible entities. The configuration includes generating and loading certificates for the server, creating an index.html file as well as a text file of a specified size to be downloaded and writing the needed headers on such files.
* **cmd_timestat.sh**: calls a specified command a certain number of times and measures its execution time using the Linux time command. Furthermore, it saves intermediate results, logs eventual errors and calculates and saves some useful statistics with the collected times, including mean time, median, minimum, maximum and quartiles. In case of a failed request, it repeats it without saving the time elapsed.
* **run_measurements.sh**: Docker entrypoint. It first applies traffic control rules (delay, bandwidth and packet loss), if any, on the specified entity and, if it is a server or a proxy, it simply runs it using the execute.sh script. If it is a client, it executes the cmd_timestat.sh on the execute.sh script and saves the statistics in a csv file. To sum up, this script basically runs a measurement consisting of a specific number of requests for a certain scenario with certain traffic conditions.

Orchestration scripts are present on the host machine and they serve the purpose of setting up and managing the tests using Docker. The scripts are as follows:
* **docker_tests.sh**: performs a specified number of measurements of a certain category by running Docker containers: a client, a server and a proxy (based on the measurement category, it can be present or not), each with a certain delay, a bandwidth limit and a packet loss. The delay can be applied to any entity and it is updated according to a specified step for each measurement, in which the containers are stopped, removed and run again. At the end of each measurement, the results csv files and error logs are copied from the container to the host machine and further modified to include other useful information. When the measurements are concluded, the files are merged.
* **main_tests.sh**: as the name suggests, the main script to launch in order to run a full test. It creates a specific folder for the test, along with the four subfolders for each category, which in turn contain the necessary subfolders for intermediate iterations, measurements, experiments and errors. It then runs four experiments, one for each scenario (MASQUE, TCP+TLS tunneled, QUIC and TCP+TLS end-to-end) and then merges the results in two main csv files, one with the summary.

**Note**: Each script has a help flag that can be used to understand how it works.

## How to use

The **csp_tests** folder contains all the necessary files for the Docker testing environment. For this reason, it is necessary to navigate to the directory and build the docker image.

`docker build -t csp_tests .`

It is also necessary to create a custom network bridge in Docker, with the following command:

`docker network create -d bridge br12`

After doing this, in order to run a full test, it is simply necessary to navigate back to the main directory, run Docker and run the **main_tests.sh** script, for example:

`./main_tests <num_measurements> <num_requests> <starting_delay> <delay_step> <download_size> <bandwidth_limit> <packet_loss>`

Delay and delay step are in milliseconds, maximum bandwidth is in Mbps, packet loss is in percentage, file size is in bytes.

For example:

`./main_tests 21 100 0 5 1000000 10 2`

The previous command runs a test made of 4 experiments (one for each category), 21 measurements, each one performing 100 requests, either through a proxy or not, to a target server for a 1MB file with 10Mbps of bandwidth, 2% of packet loss and with an
additional artificial delay varying from 0ms to 200ms.

After a test is done, it is possible to see the results in the **tests/<test_dateandtime>** folder. This folder contains a subfolder for each category and the intermediate results for each iteration, measurement and experiment. The final results are present in the **tests/<test_dateandtime>/results** subfolder.

## Dependencies

- [Docker](https://www.docker.com/) for containerization.

The Docker containers use the following tools:
- Google tools from [Chromium source](https://www.chromium.org/quic/playing-with-quic/).
- Cloudflare tools from [Cloudflare quiche](https://github.com/cloudflare/quiche)
- [Squid proxy](http://www.squid-cache.org/)
- [Twisted HTTPS server](https://twisted.org/documents/15.0.0/web/howto/using-twistedweb.html)
- [curl](https://curl.se/)
