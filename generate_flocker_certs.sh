#!/bin/bash

# README:
# the first time you run this, you'll need to setup your
# certificate store (feel free to create these directories
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

################################################################################
# Config: The user must fill in these variables based on their cluster setup:
#
# fill in one of the following variables with the ip/dns of the
# cluster's control-service
# TODO: these should be command line args
control_service_dns="ec2-52-36-190-217.us-west-2.compute.amazonaws.com"
control_service_ip=""

# fill in the nodes to generate certs for the nodes
nodes[0]=ec2-52-37-214-228.us-west-2.compute.amazonaws.com
nodes[1]=ec2-52-37-216-48.us-west-2.compute.amazonaws.com

# cluster name should be unique for each cluster you have
cluster_name=mycluster

# this is the path to
openssl_cnf_path=./openssl.cnf

################################################################################
# set the CERT_HOST_ID environment variable early on since its used in
# openssl.cnf
if [ $control_service_dns != "" ]; then
    export CERT_HOST_ID=DNS:control-service,DNS:$control_service_dns
    control_host=$control_service_dns
else
    export CERT_HOST_ID=DNS:control-service,IP:$control_service_ip
    control_host=$control_service_ip
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
