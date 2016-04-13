#!/bin/bash -e
#
# Script for generating Flocker certificated based on OpenSSL CLI
#
# Authors: See AUTHORS.md

# Ensure that we're in the right directory for the config paths to be correct
# when invoked from other dirs

SCRIPT_DIR="$(dirname $(readlink -f $0))"
CURRENT_DIR="$(pwd)"
cd "$SCRIPT_DIR"

HELP_MSG="""
Usage:

  $0 new (-i=<control_ip> | -d=<control_fqdn>) [--force] [-f=openssl_conf] [-n=<node>[,<node> ... ]] -c=<cluster_name>
  $0 node [-f=openssl_conf] [--force] -c=<cluster_name> -n=<node>[,<node> ... ]

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
"""

# XXX: Doing the assignment after check is to ensure we have >1 args
OP_TYPE=""
if [ "${1}" == "node" ] || [ "${1}" == "new" ]; then
  OP_TYPE="${1}"
  shift
else
  echo "ERROR! Operation type not specified!"
  echo "${HELP_MSG}"
  exit 1
fi

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
if [ ! -z "$NODES" ] && [ -z "${NODES// }" ]; then
  echo "ERROR! Node list is empty! Exiting!"
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
nodes=()
for node in ${NODES}; do
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
elif [ ! "${OP_TYPE}" == "node" ]; then
  echo "ERROR! No control service FQDN or IP provided! Exiting!"
  echo "${HELP_MSG}"
  exit 1
else
  # XXX: The conf requires this env var even for non-ctrl-service keypair
  #      generation which is an error but for now we just make sure it's
  #      not empty
  export CERT_HOST_ID=""
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

generate_and_sign_node_certs() {
  # generate_and_sign_node_certs <ca_keypair> <nodes> <output_dir>

  # Sanity check
  if [ $# -lt 3 ]; then
    echo "ERROR! generate_and_sign_node_certs not properly invoked! Exiting!"
    exit 1
  fi

  local ca_keypair="${1}"
  local nodes=("${!2}")     # De-ref the array name
  local output_dir="${3}"

  echo "- Will create ${#nodes[@]} node keypair(s)"

  local cluster_uuid=$(openssl x509 -noout -subject -in $ca_keypair.crt \
                       | sed -e 's/.*\/OU=\(.*\)[\/]*.*/\1/')
  echo "- Using Cluster UUID: $cluster_uuid"

  for node_hostname in ${nodes[@]}; do
    if [ -e "$output_dir/node-${node_hostname}.key" ] && \
       [ ! "$FORCE_OVERWRITE" == "true" ]; then
      echo "Node '$node_hostname' keypair already created. Skipping"
      continue
    fi

    generate_and_sign_cert "$output_dir/node-$node_hostname" \
                           "/CN=node-$(uuidgen)/OU=$cluster_uuid" \
                           "$ca_keypair"
  done
}


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
    rm -f "${output_dir}/*.crt"
    rm -f "${output_dir}/*.key"
  elif [ "$OP_TYPE" == "new" ]; then
    echo "ERROR! Cluster already created and '--force' not specified! Exiting!"
    exit 1
  fi
fi

mkdir -p $output_dir

cluster_keypair_path="$output_dir/cluster"

# Special case of us needing to create/sign node certs
if [ "${OP_TYPE}" == "node" ]; then
  echo "Generating and signing node keypair(s)"
  # XXX: Array passed as a name, not a value
  generate_and_sign_node_certs $cluster_keypair_path \
                               "nodes[@]" \
                               $output_dir
  echo

  exit
fi

cluster_uuid=$(uuidgen)

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
# XXX: Array passed as a name, not a value
generate_and_sign_node_certs $cluster_keypair_path \
                             "nodes[@]" \
                             $output_dir
echo

echo "Generating API keypair"
api_username=plugin
generate_and_sign_cert "$output_dir/$api_username" \
                       "/CN=user-$api_username/OU=$cluster_uuid" \
                       "$cluster_keypair_path" \
                       "client_api_ext"
echo "Done!"
