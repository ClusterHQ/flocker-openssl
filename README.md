# OpenSSL with Flocker

> WARNING: This is EXPERIMENTAL support for using openssl tools with Flocker.

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
$ ./flocker-openssl/generate_flocker_certs.sh -h
Usage:

  ./generate_flocker_certs.sh new (-i=<control_ip> | -d=<control_fqdn>) [--force] [-f=openssl_conf] [-n=<node>[,<node> ... ]] -c=<cluster_name>
  ./generate_flocker_certs.sh node [-f=openssl_conf] [--force] -c=<cluster_name> -n=<node>[,<node> ... ]

# Positional arguments
  new                   Creates new cluster keypair group
  node                  Creates/signs node keypairs with existing cluster keypair
                          (Assumes output dir contains cluster.crt and key)

# Arguments
  -i=, --control_ip=    Control Service IP
  -d=, --control_fqdn=  Control Service FQDN
  -c=, --cluster_name=  Cluster name. Should be unique (Default=mycluster)
  -k=, --key_size=      RSA keysize (Default=4096)
  -o=, --output-dir=    Key destination (Default=./clusters/<cluster_name>)
  -f=, --openssl_file=  OpenSSL conf file location (Default=./openssl.cnf)
  -n=, --nodes=         Comma seperated list of nodes
  --force               Force overwrite of files if they already exist

# Other
  -h, --help            This help message
```

Examples:

```
./flocker-openssl/generate_flocker_certs.sh new -d=www.foobar.com -k=1024 -c=staging-1 -n=one,two
```
```
./flocker-openssl/generate_flocker_certs.sh new -d="ec2-52-91-11-106.compute-1.amazonaws.com" -n="ec2-52-91-11-106.compute-1.amazonaws.com,node2,node3" -f=/etc/flocker/ssl/flockeropenssl/openssl.cnf
```
```
# Control service node
./flocker-openssl/generate_flocker_certs.sh new -o=/etc/flocker -d=www.foobar.com -k=2048 -c=staging-1

# New node added to cluster
./flocker-openssl/generate_flocker_certs.sh node -o=/etc/flocker -k=2048 -c=staging-1 -n=new-node
```

All relevant certificates can be found in `clusters/<cluster_name>`unless `-o` override is specified.


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

### Contributions

See AUTHORS.md
