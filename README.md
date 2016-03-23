# OpenSSL with Flocker

### Generating Flocker Certificates OpenSSL

This script will help generate the following certificates for Flocker

* Cluster CA (cluster.crt/.key)
* Control Cert (control-<CONTROL_HOST>.crt/.key)
* Node Cert (node-<AGENT_NODE>.crt/.key)
* API User (<USERNAME>.crt/.key)

For more information on [Flocker Authentication](https://docs.clusterhq.com/en/latest/flocker-standalone/configuring-authentication.html) see:

https://docs.clusterhq.com/en/latest/flocker-standalone/configuring-authentication.html

### How to use this repository

First, [Install Flocker on your system](https://docs.clusterhq.com/en/latest/)

Second, create needed directories.

>Note: this is only an example, you can great a different `ssl` directory to fit your needs.

```
$ mkdir $HOME/ssl
$ cd $HOME/ssl
$ mkdir csr newcerts
$ touch index.txt
$ echo 1000 > serial
```

> Note: You will also need to update the CA_default section of openssl.cnf to point at your ssl directory.

Pull and update openssl.cnf
```
$ cd $HOME/ssl
$ git clone https://github.com/wallnerryan/flockeropenssl
$ vi flockeropenssl/openssl.cnf

# edit `dir =` under `[ CA_default ]` 
```

> Note:  You can edit `dir = ` under `[ CA_default ]` to either `$HOME/ssl` from the above example or a custom location you are using for your root ssl directory.

#### Generate Flocker Certificates

You can view help message by
```
$ ./flockeropenssl/generate_flocker_certs.sh -h

# Need one of these options set
-i= | --control_ip= (Control Service IP)
-d= | --control_dns= (Control Service DNS)

# Optional
-c= | --cluster_name= (Name of your cluster  should be unique Default=mycluster)
-f= | --openssl_file= (Location of openssl.cnf. Default: ./openssl.cnf)

# Required
-n= | --nodes= (Comma seperated list of node DNS names or unique names)

# Other
-h | --help (This help message)
```

Example

```
./flockeropenssl/generate_flocker_certs.sh -d="ec2-52-91-11-106.compute-1.amazonaws.com" -n="ec2-52-91-11-106.compute-1.amazonaws.com,node2,node3" -f=/etc/flocker/ssl/flockeropenssl/openssl.cnf
```

Example Output
```
0:ec2-52-91-11-106.compute-1.amazonaws.com
1:node2
2:node3
Generating RSA private key, 4096 bit long modulus
.....................................................................++
....................................++
e is 65537 (0x10001)
Generating RSA private key, 4096 bit long modulus
..............................................................................++
.
.
. (cut out long output)
```

Your SSL directory should be populated with the new certificates
```
$ ls
api_user.crt  cluster.key                                           csr                                       index.txt           index.txt.old  node3
api_user.key  control-ec2-52-91-11-106.compute-1.amazonaws.com.crt  ec2-52-91-11-106.compute-1.amazonaws.com  index.txt.attr      newcerts       serial
cluster.crt   control-ec2-52-91-11-106.compute-1.amazonaws.com.key  flockeropenssl                            index.txt.attr.old  node2          serial.old
```

How to use the certificates?
```
# Copy control, cluster and API certs
$ cp *.crt *.key /etc/flocker/
$ cd /etc/flocker/

# Rename them appropriately 
$ mv api_user.crt plugin.crt
$ mv api_user.key plugin.key
$ mv control-ec2-52-91-11-106.compute-1.amazonaws.com.crt control-service.crt
$ mv control-ec2-52-91-11-106.compute-1.amazonaws.com.key control-service.key

# On the dataset node, copy the appropriate node certs (you may need to scp these to appropriate locations)
$ cp ssl/node2/node-da0779a7-51b9-4d62-a4a7-e9ca55f73988.crt node.crt
$ cp ssl/node2/node-da0779a7-51b9-4d62-a4a7-e9ca55f73988.key node.key
```

Then start the Flocker services. Learn more [here.](https://docs.clusterhq.com/en/latest/)

### FAQ

##### How do I create a single node certificate after i've run the original script to produce others?

Well, this is not supported from the script yet, but because we're usign openssl directly,
its easy to pick apart the information and create what you need. 

> This portion of the README is also to see how we can use openssl tools to get information
> from the certificates already created and how to use them.

First, get the Cluster UUID from the `cluster.crt`. You should see `OU=<UUID>` in the output from the command below, copy this UUID.
```
openssl x509 -in cluster.crt -text -noout
```

Then there are two options.

If you used Control DNS originally, put the below bash script in a file called `create-node.sh` next to the oringal script.
```bash
#!/bin/bash

# your new node certificate to create
node_hostname="node.local.example"

cluster_uuid="<UUID from above>" 
cluster_name="<your cluster name>" # whatever you used originally
openssl_cnf_path="<path to openssl.cnf>"
control_service_dns=<DNS name of control service> # whatever you used originally

export CERT_HOST_ID=DNS:control-service,DNS:$control_service_dns
control_host=$control_service_dns
cluster_crt_path=cluster.crt
cluster_key_path=cluster.key
mkdir $node_hostname
node_uuid=$(uuidgen)
node_key_path=$node_hostname/node-$node_uuid.key
node_csr_path=csr/node-$node_uuid.csr
node_crt_path=$node_hostname/node-$node_uuid.crt
# key
openssl genrsa -out $node_key_path 4096
# cert request
subject="/CN=node-$node_uuid/OU=$cluster_uuid"
openssl req -config $openssl_cnf_path -key $node_key_path -new -sha256 -subj "$subject" -out $node_csr_path
# cert
openssl ca -batch -config $openssl_cnf_path -keyfile $cluster_key_path -cert $cluster_crt_path -days 7300 -notext -md sha256 -in $node_csr_path -subj "$subject" -out $node_crt_path
```

If you used Control IP originally, put the below bash script in a file called `create-node.sh` next to the oringal script.
```bash
#!/bin/bash

# your new node certificate to create
node_hostname="node.local.example"

cluster_uuid="<UUID from above>" 
cluster_name="<your cluster name>" # whatever you used originally
openssl_cnf_path="<path to openssl.cnf>"
control_service_ip=<Your control service IP> # whatever you used originally

export CERT_HOST_ID=DNS:control-service,IP:$control_service_ip
control_host=$control_service_ip
cluster_crt_path=cluster.crt
cluster_key_path=cluster.key
mkdir $node_hostname
node_uuid=$(uuidgen)
node_key_path=$node_hostname/node-$node_uuid.key
node_csr_path=csr/node-$node_uuid.csr
node_crt_path=$node_hostname/node-$node_uuid.crt
# key
openssl genrsa -out $node_key_path 4096
# cert request
subject="/CN=node-$node_uuid/OU=$cluster_uuid"
openssl req -config $openssl_cnf_path -key $node_key_path -new -sha256 -subj "$subject" -out $node_csr_path
# cert
openssl ca -batch -config $openssl_cnf_path -keyfile $cluster_key_path -cert $cluster_crt_path -days 7300 -notext -md sha256 -in $node_csr_path -subj "$subject" -out $node_crt_path
```

Then, just run the script
```bash
chmod +x create-node.sh
./create-node.sh

# or
sh create-node.sh

```

### Contributions

Thanks to Brendan Cox for the heavy lifting. The rest of this was from guidance through:
- https://jamielinux.com/docs/openssl-certificate-authority/index.html
- and combined with the implementation in flocker/flocker/ca/_ca.py
