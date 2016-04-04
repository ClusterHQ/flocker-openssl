# OpenSSL with Flocker

### Generating Flocker Certificates OpenSSL

This script will help generate the following certificates for Flocker in `./cluster/<cluster_name>` directory.

* Cluster CA (cluster.crt/.key)
* Control Cert (control-service.crt/.key)
* Node Cert (node-<AGENT_NODE>.crt/.key)
* API User (api_user.crt/.key)

For more information on [Flocker Authentication](https://docs.clusterhq.com/en/latest/flocker-standalone/configuring-authentication.html) see:

https://docs.clusterhq.com/en/latest/flocker-standalone/configuring-authentication.html

#### Generate Flocker Certificates

You can view help message by
```
$ ./flockeropenssl/generate_flocker_certs.sh -h
Usage: $0 (-i=<control_ip> | -d=<control_fqdn>) [-f=openssl_conf] -c=<cluster_name> -n=<node>[,<node> ... ]


-i= | --control_ip= (Control Service IP)
-d= | --control_fqdn= (Control Service FQDN)

# Optional
-c= | --cluster_name= (Name of your cluster, should be unique. Default=mycluster)
-k= | --key_size= (Size of RSA keys - defaults to 4096)
-o= | --output-dir= (Location to place the keys. Default=./clusters/<cluster_name>)
-f= | --openssl_file= (Location of openssl.cnf. Default=./openssl.cnf)
--force=  (If a cluster has previously been created, force overwrite of the files)

# Required
-n= | --nodes= (Comma seperated list of node DNS names or unique names)

# Other
-h | --help (This help message)
```

Examples:

```
./flockeropenssl/generate_flocker_certs.sh -d=www.foobar.com -k=1024 -c=staging-1 -n=one,two
```
```
./flockeropenssl/generate_flocker_certs.sh -d="ec2-52-91-11-106.compute-1.amazonaws.com" -n="ec2-52-91-11-106.compute-1.amazonaws.com,node2,node3" -f=/etc/flocker/ssl/flockeropenssl/openssl.cnf
```

All relevant certificates can be found in `clusters/<cluster_name>`


### How to use the certificates?

#### Control node

```
$ scp cluster/cluster-1/cluster.crt user@cluster-master:/etc/flocker/
$ scp cluster/cluster-1/control-service.* user@cluster-master:/etc/flocker/
```

#### Node

```
$ scp cluster/cluster-1/cluster.crt user@cluster-master:/etc/flocker/
$ scp cluster/cluster-1/plugin.* user@cluster-master:/etc/flocker/
$ scp cluster/cluster-1/node-1.crt user@cluster-master:/etc/flocker/node.crt
$ scp cluster/cluster-1/node-1.key user@cluster-master:/etc/flocker/node.key
```

Then start the Flocker services. Learn more [here.](https://docs.clusterhq.com/en/latest/)

### FAQ

##### How do I create a single node certificate after i've run the original script to produce others?

Well, this is not supported from the script yet (TODO), but because we're using openssl directly,
its easy to pick apart the information and create what you need.

> This portion of the README is also to see how we can use openssl tools to get information
> from the certificates already created and how to use them.

First, get the Cluster UUID from the `cluster.crt`. You should see `OU=<UUID>` in the output from the command below, copy this UUID.
```
openssl x509 -in cluster.crt -text -noout
```

Then there are two options.

If you used Control DNS originally, put the below bash script in a file called `create-node.sh` next to the original script.
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

If you used Control IP originally, put the below bash script in a file called `create-node.sh` next to the original script.
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
