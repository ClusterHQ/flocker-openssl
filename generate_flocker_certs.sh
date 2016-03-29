#!/bin/bash -e

IFS=","

# README:
# the first time you run this, you'll need to setup your
# certificate store (feel free to create these example directories
# whereever you feel is appropriate):
#
# mkdir $HOME/ssl
# cd $HOME/ssl
# mkdir csr newcerts
# touch index.txt
# echo 1000 > serial
#
# you will also need to update the CA_default section of openssl.cnf
# to point at your ssl directory.
#
# most of this was taken from this tutorial:
# https://jamielinux.com/docs/openssl-certificate-authority/index.html
# and combined with the implementation in flocker/flocker/ca/_ca.py
#
# authors: Brendan Cox "justnoise" , and Ryan Wallner "wallnerryan"
#
################################################################################

HELP_MSG="""
Usage: $0 (-i=<control_ip> | -d=<control_fqdn>) [-f=openssl_conf] -c=<cluster_name> -n=<node>[,<node> ... ]


-i= | --control_ip= (Control Service IP)
-d= | --control_fqdn= (Control Service FQDN)

# Optional
-c= | --cluster_name= (Name of your cluster, should be unique. Default=mycluster)
-f= | --openssl_file= (Location of openssl.cnf. Default=./openssl.cnf)

# Required
-n= | --nodes= (Comma seperated list of node DNS names or unique names)

# Other
-h | --help (This help message)
"""

for arg in "$@"; do
  case $arg in
    -i=*|--control_ip=*)
      CONTROL_IP="${arg#*=}"
      shift # past argument=value
      ;;
    -d=*|--control_fqdn=*)
      CONTROL_FQDN="${arg#*=}"
      shift # past argument=value
      ;;
    -c=*|--cluster_name=*)
      CLUSTER_NAME="${arg#*=}"
      shift # past argument=value
      ;;
    -f=*|--openssl_file=*)
      OPENSSL_FILE="${arg#*=}"
      shift # past argument with no value
      ;;
    -n=*|--nodes=*)
      NODES="${arg#*=}"
      shift # past argument with no value
      ;;
    -h|--help)
      echo -e $HELP_MSG && exit 0;
      shift # past argument with no value
      ;;
    *)
      # unknown option
      ;;
  esac
done
# Config: The user must pass variables based on their cluster setup:
# or receive defaults
control_service_fqdn=${CONTROL_FQDN:=""}
control_service_ip=${CONTROL_IP:=""}

# fill in the nodes to generate certs for the nodes
# pass as a list of nodes
# Example:  --nodes=node1,node2,node3...
# maybe we want the ability to pass a json/yaml/csv to this?
if [ -z "$NODES" ] || [ -z "${NODES// }" ]; then
  echo "No nodes provided! Exiting!"
  echo "${HELP_MSG}"
  exit 1
fi

if [ -z "$CLUSTER_NAME" ] || [ -z "${CLUSTER_NAME// }" ]; then
  echo "No cluster name provided! Exiting!"
  echo "${HELP_MSG}"
  exit 1
fi

declare -a nodes
for node in $NODES; do
  nodes+=( $node )
done

cluster_name=${CLUSTER_NAME}
openssl_cnf_path=${OPENSSL_FILE:="./openssl.cnf"}

# set the CERT_HOST_ID environment variable early on since its used in
# openssl.cnf. Use FQDN first if its there.
if [ "$control_service_fqdn" != "" ]; then
  export CERT_HOST_ID=DNS:control-service,DNS:$control_service_fqdn
  control_host=$control_service_fqdn
elif [ "$control_service_ip" != "" ]; then
  export CERT_HOST_ID=DNS:control-service,IP:$control_service_ip
  control_host=$control_service_ip
else
  echo "No control service FQDN or IP provided! Exiting!"
  echo "${HELP_MSG}"
  exit 1
fi

# ----------------------------------------
# generate the CA:
# ----------------------------------------
cluster_uuid=$(uuidgen)
cluster_key_path=cluster.key
cluster_crt_path=cluster.crt
subject="/CN=$cluster_name/OU=$cluster_uuid"
openssl genrsa -out $cluster_key_path 4096
openssl req -batch -config $openssl_cnf_path -key $cluster_key_path -new -x509 -days 7300 -sha256 -extensions v3_ca -subj "$subject" -out $cluster_crt_path

# ----------------------------------------
# generate the control cert and keypair
# ----------------------------------------
# these end up getting copied to the nodes as control-service.(key|crt)
# but we'll create them like the docs tell us to...
control_key_path=control-$control_host.key
control_csr_path=csr/control-$control_host.csr
control_crt_path=control-$control_host.crt
subject="/CN=control-service/OU=$cluster_uuid"
# key
openssl genrsa -out $control_key_path 4096
# cert request
#openssl req -config $openssl_cnf_path -key $control_key_path -new -days 7300 -sha256 -subj "$subject" -out $control_csr_path
openssl req -config $openssl_cnf_path -key $control_key_path -new -days 7300 -sha256 -subj "$subject" -extensions control_service_extension -out $control_csr_path
# cert
#openssl ca -batch -config $openssl_cnf_path -keyfile $cluster_key_path -cert $cluster_crt_path -days 7300 -notext -md sha256 -extfile $host_extension_path -in $control_csr_path -subj "$subject" -out $control_crt_path
openssl ca -batch -config $openssl_cnf_path -keyfile $cluster_key_path -cert $cluster_crt_path -days 7300 -notext -md sha256 -extensions control_service_extension -in $control_csr_path -subj "$subject" -out $control_crt_path

#----------------------------------------
# Generate the node cert and keypair
#----------------------------------------
# you will need to do this for each node in your cluster
for node_hostname in ${nodes[@]}; do
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
done

#generate api cert and keypair
#----------------------------------------
api_username=api_user
api_key_path=$api_username.key
api_csr_path=csr/$api_username.csr
api_crt_path=$api_username.crt
subject="/CN=user-$api_username/OU=$cluster_uuid"
# key
openssl genrsa -out $api_key_path 4096
# cert request
openssl req -config $openssl_cnf_path -key $api_key_path -new -sha256 -subj "$subject" -out $api_csr_path
# cert
openssl ca -batch -config $openssl_cnf_path -keyfile $cluster_key_path -cert $cluster_crt_path -days 7300 -notext -md sha256 -in $api_csr_path -subj "$subject" -extensions client_api_ext -out $api_crt_path
