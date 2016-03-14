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

Generate Flocker Certificates

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
