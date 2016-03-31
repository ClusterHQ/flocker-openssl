#!/bin/bash -e
#
################################################################################
# Most of this was taken from this tutorial:
# https://jamielinux.com/docs/openssl-certificate-authority/index.html
# and combined with the implementation in flocker/flocker/ca/_ca.py
#
# Authors:
# - Brendan Cox "justnoise"
# - Ryan Wallner "wallnerryan"
# - Srdjan Grubor <sgnn7@sgnn7.org>
#
################################################################################

CURRENT_DIR="$(dirname $0)"

HELP_MSG="""
Usage: $0 (-i=<control_ip> | -d=<control_fqdn>) [-f=openssl_conf] -c=<cluster_name> -n=<node>[,<node> ... ]


-i= | --control_ip= (Control Service IP)
-d= | --control_fqdn= (Control Service FQDN)

# Optional
-c= | --cluster_name= (Name of your cluster, should be unique. Default=mycluster)
-k= | --key_size= (Size of RSA keys - defaults to 4096)
-f= | --openssl_file= (Location of openssl.cnf. Default=./openssl.cnf)

# Required
-n= | --nodes= (Comma seperated list of node DNS names or unique names)

# Other
-h | --help (This help message)
"""

IFS=","
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
    -k=*|--key_size=*)
      KEY_SIZE="${arg#*=}"
      shift
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

control_service_fqdn=${CONTROL_FQDN:=""}
control_service_ip=${CONTROL_IP:=""}
key_size=${KEY_SIZE:="4096"}

# Sanity checks
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

# Split nodes into discrete values
declare -a nodes
for node in $NODES; do
  nodes+=( $node )
done

cluster_name=${CLUSTER_NAME}
openssl_cnf_path=${OPENSSL_FILE:="$CURRENT_DIR/openssl.cnf"}

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

# Create needed CA fs layout
CSR_DIR=$CURRENT_DIR/ssl/csr
NEW_CERTS_DIR=$CURRENT_DIR/ssl/newcerts
rm -rf $CURRENT_DIR/ssl
mkdir -p $CSR_DIR
mkdir -p $NEW_CERTS_DIR
touch $(dirname $0)/ssl/index.txt
echo 'unique_subject = no' > $(dirname $0)/ssl/index.txt.attr
echo '1000' > ssl/serial

echo "Generating the CA keypair"
cluster_uuid=$(uuidgen)
cluster_key_path=cluster.key
cluster_crt_path=cluster.crt
subject="/CN=$cluster_name/OU=$cluster_uuid"
openssl genrsa -out $cluster_key_path $key_size
openssl req -batch \
            -config $openssl_cnf_path \
            -key $cluster_key_path \
            -new \
            -x509 \
            -days 7300 \
            -sha256 \
            -extensions v3_ca \
            -subj "$subject" \
            -out $cluster_crt_path

echo "Generating the control service keypair"
# these end up getting copied to the nodes as control-service.(key|crt)
control_key_path=control-$control_host.key
control_csr_path=$CURRENT_DIR/ssl/csr/control-$control_host.csr
control_crt_path=control-$control_host.crt
subject="/CN=control-service/OU=$cluster_uuid"
openssl genrsa -out $control_key_path $key_size
openssl req -config $openssl_cnf_path -key $control_key_path -new -days 7300 -sha256 -subj "$subject" -out $control_csr_path
openssl ca -batch \
           -config "$openssl_cnf_path" \
           -keyfile "$cluster_key_path" \
           -cert "$cluster_crt_path" \
           -days 7300 \
           -notext \
           -md sha256 \
           -extensions "control_service_extension" \
           -in "$control_csr_path" \
           -subj "$subject" \
           -out "$control_crt_path"

echo "Generating node keypair(s)"
for node_hostname in ${nodes[@]}; do
    mkdir -p $node_hostname

    node_uuid=$(uuidgen)
    node_key_path=$node_hostname/node-$node_uuid.key
    node_csr_path=$CURRENT_DIR/ssl/csr/node-$node_uuid.csr
    node_crt_path=$node_hostname/node-$node_uuid.crt

    openssl genrsa -out $node_key_path $key_size
    subject="/CN=node-$node_uuid/OU=$cluster_uuid"
    openssl req -config $openssl_cnf_path -key $node_key_path -new -sha256 -subj "$subject" -out $node_csr_path
    openssl ca -batch \
               -config "$openssl_cnf_path" \
               -keyfile "$cluster_key_path" \
               -cert "$cluster_crt_path" \
               -days 7300 \
               -notext \
               -md sha256 \
               -in "$node_csr_path" \
               -subj "$subject" \
               -out "$node_crt_path"
done

echo "Generating API keypair"
api_username=api_user
api_key_path=$api_username.key
api_csr_path=$CURRENT_DIR/ssl/csr/$api_username.csr
api_crt_path=$api_username.crt
subject="/CN=user-$api_username/OU=$cluster_uuid"
openssl genrsa -out $api_key_path $key_size
openssl req -config $openssl_cnf_path -key $api_key_path -new -sha256 -subj "$subject" -out $api_csr_path
openssl ca -batch \
           -config "$openssl_cnf_path" \
           -keyfile "$cluster_key_path" \
           -cert "$cluster_crt_path" \
           -days 7300 \
           -notext \
           -md sha256 \
           -in "$api_csr_path" \
           -subj "$subject" \
           -extensions "client_api_ext" \
           -out "$api_crt_path"
echo "Done!"
