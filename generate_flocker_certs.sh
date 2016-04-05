#!/bin/bash -e
#
# Script for generating Flocker certificated based on OpenSSL CLI
#
# Authors: See AUTHORS.md

# Ensure that we're in the right directory for the config paths to be correct
# when invoked from other dirs
SCRIPT_DIR="$(dirname $0)"
CURRENT_DIR="$(pwd)"
cd "$SCRIPT_DIR"

HELP_MSG="""
Usage: $0 (-i=<control_ip> | -d=<control_fqdn>) [-f=openssl_conf] -c=<cluster_name> -n=<node>[,<node> ... ]


-i= | --control_ip= (Control Service IP)
-d= | --control_fqdn= (Control Service FQDN)

# Optional
-c= | --cluster_name= (Name of your cluster, should be unique. Default=mycluster)
-k= | --key_size= (Size of RSA keys. Default=4096)
-o= | --output-dir= (Location to place the keys. Default=./clusters/<cluster_name>)
-f= | --openssl_file= (Location of openssl.cnf. Default=./openssl.cnf)
--force=  (If a cluster has previously been created, force overwrite of the files)

# Required
-n= | --nodes= (Comma seperated list of node DNS names or unique names)

# Other
-h | --help (This help message)
"""

FORCE_OVERWRITE=false
for arg in "$@"; do
  case $arg in
    -i=*|--control_ip=*)
      CONTROL_IP="${arg#*=}"
      shift
      ;;
    -d=*|--control_fqdn=*)
      CONTROL_FQDN="${arg#*=}"
      shift
      ;;
    -c=*|--cluster_name=*)
      CLUSTER_NAME="${arg#*=}"
      shift
      ;;
    -f=*|--openssl_file=*)
      OPENSSL_FILE="${arg#*=}"
      shift
      ;;
    -n=*|--nodes=*)
      NODES="${arg#*=}"
      shift
      ;;
    -o=*|--output-dir=*)
      OUTPUT_DIR="${arg#*=}"
      shift
      ;;
    --force)
      FORCE_OVERWRITE=true
      shift
      ;;
    -k=*|--key_size=*)
      KEY_SIZE="${arg#*=}"
      shift
      ;;
    -h|--help)
      echo "${HELP_MSG}" && exit 0;
      shift
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
IFS=","
declare -a nodes
for node in $NODES; do
  nodes+=( $node )
done
unset IFS

cluster_name=${CLUSTER_NAME}
openssl_cnf_path=${OPENSSL_FILE:="openssl.cnf"}

# set the CERT_HOST_ID environment variable early on since its used in
# openssl.cnf. Use FQDN first if its there.
if [ "$control_service_fqdn" != "" ]; then
  export CERT_HOST_ID=DNS:control-service,DNS:$control_service_fqdn
  control_host=$control_service_fqdn
elif [ "$control_service_ip" != "" ]; then
  export CERT_HOST_ID=DNS:control-service,IP:$control_service_ip
  control_host=$control_service_ip
else
  echo "ERROR! No control service FQDN or IP provided! Exiting!"
  echo "${HELP_MSG}"
  exit 1
fi

echo "Cleaning up old CA dirs"
rm -rf flockerssl

echo "Create needed CA fs layout"
mkdir -p flockerssl/csr
mkdir -p flockerssl/newcerts

touch flockerssl/index.txt
echo '1000' > flockerssl/serial
echo 'unique_subject = no' > flockerssl/index.txt.attr

generate_key(){
  # generate_key <output_path>
  local output_path="${1}"

  echo -n "- Generating key $output_path"
  openssl genrsa -out "$output_path" $key_size &>/dev/null
  echo " [OK]"
}

generate_csr() {
  # generate_csr <key_path> <subject> <output_path>
  local key_path="${1}"
  local subject="${2}"
  local output_path="${3}"

  # Sanity check
  if [ $# -lt 3 ]; then
    echo "ERROR! generate_csr not properly invoked! Exiting!"
    exit 1
  fi

  echo -n "- Creating csr for $key_path"
  openssl req -config "$openssl_cnf_path" \
              -key "$key_path" \
              -new \
              -days 7300 \
              -sha256 \
              -subj "$subject" \
              -out "$output_path" &>/dev/null
  echo " ($output_path) [OK]"
}

sign_csr() {
  # sign_csr <csr_path> <ca_keypair> <output_path> [<extension>]

  # Sanity check
  if [ $# -lt 3 ]; then
    echo "ERROR! sign_csr not properly invoked! Exiting!"
    exit 1
  fi

  local csr_path="${1}"
  local ca_key="${2}.key"
  local ca_crt="${2}.crt"
  local output_path="${3}"

  local extensions=""
  if [ $# -gt 3 ] && [ ! -z "${4}" ]; then
    extensions="-extensions ${4}"
  fi

  openssl ca -batch \
             -config "$openssl_cnf_path" \
             -keyfile "$ca_key" \
             -cert "$ca_crt" \
             -days 7300 \
             -notext \
             -md sha256 \
             $extensions \
             -in "$csr_path" \
             -out "$output_path"
}

generate_and_sign_cert() {
  # generate_and_sign_cert <keypair_path> <subject> <ca_keypair> [<extensions>]

  # Sanity check
  if [ $# -lt 3 ]; then
    echo "ERROR! generate_and_sign_cert not properly invoked! Exiting!"
    exit 1
  fi

  local key_path="${1}.key"
  local crt_output="${1}.crt"
  local subject="${2}"
  local ca_keypair="${3}"
  local extensions="${4}"

  local temp_csr_path=$(mktemp -q "$(basename $0).XXXXX.tmp")

  generate_key "$key_path"
  generate_csr "$key_path" "$subject" "$temp_csr_path"
  sign_csr "$temp_csr_path" \
         "$ca_keypair" \
         "$crt_output" \
         "$extensions"

  rm -f "$temp_csr_path"
}

cluster_uuid=$(uuidgen)

# If we want an output path and its relative, we need to root it in our
# invocation directory and not where we are right now
if [ ! -z "$OUTPUT_DIR" ] && [ ! "${OUTPUT_DIR:0:1}" = "/" ]; then
  OUTPUT_DIR="$CURRENT_DIR/$OUTPUT_DIR"
fi

output_dir=${OUTPUT_DIR:="$CURRENT_DIR/clusters/$cluster_name"}
echo "Output directory is $output_dir"

if [ -d $output_dir ]; then
  if [ "$FORCE_OVERWRITE" == "true" ]; then
    echo "Forcefuly removing old data from old cluster"
    rm -rf "$output_dir"
  else
    echo "ERROR! Cluster already created and '--force' not specified! Exiting!"
    exit 1
  fi
fi

mkdir -p $output_dir

cluster_keypair_path="$output_dir/cluster"

echo "Generating the CA keypair (cluster_keypair_path)"
generate_key "$cluster_keypair_path.key"

echo -n "Self-signing CA cert"
openssl req -batch \
            -config "$openssl_cnf_path" \
            -key "${cluster_keypair_path}.key" \
            -new \
            -x509 \
            -days 7300 \
            -sha256 \
            -extensions v3_ca \
            -subj "/CN=$cluster_name/OU=$cluster_uuid" \
            -out "${cluster_keypair_path}.crt"

echo " [OK]"
echo

echo "Generating the control service keypair"
generate_and_sign_cert "$output_dir/control-service" \
                       "/CN=control-service/OU=$cluster_uuid" \
                       "$cluster_keypair_path" \
                       "control_service_extension"
echo

echo "Generating node keypair(s)"
for node_hostname in ${nodes[@]}; do
  generate_and_sign_cert "$output_dir/node-$node_hostname" \
                         "/CN=node-$(uuidgen)/OU=$cluster_uuid" \
                         "$cluster_keypair_path"
done
echo

echo "Generating API keypair"
api_username=plugin
generate_and_sign_cert "$output_dir/$api_username" \
                       "/CN=user-$api_username/OU=$cluster_uuid" \
                       "$cluster_keypair_path" \
                       "client_api_ext"
echo "Done!"
