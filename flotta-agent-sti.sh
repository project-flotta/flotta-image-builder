#!/bin/bash

source ./flotta-image-builder-common-functions.sh
set -e

# The script performs the following steps on rhel-8.5:
# * Install image-builder
# * Create rpms for yggdrasil and flotta-device-worker
# * Publish rpms as yum repo to be consumed by image-builder
# * Publish rhel4edge image for edge-device


export IMAGE_NAME=
export HTTP_API=
export VERBOSE=
export IMAGE_SERVER_ADDRESS=


usage()
{
cat << EOF
usage: $0 options
This script will create an image file and ISO to be served for download.
OPTIONS:
   -h      Show this message
   -a      Image server address
   -i      Image name (required)
   -o      Operator's HTTP API (required)
   -v      Verbose
EOF
}

while getopts "h:a:i:o:v" option; do
    case "${option}"
    in
        h)
            usage
            exit 0
            ;;
        a) IMAGE_SERVER_ADDRESS=${OPTARG};;
        i) IMAGE_NAME=${OPTARG};;
        o) HTTP_API=${OPTARG};;
        v) VERBOSE=1;;
    esac
done

if [[ ! -z $VERBOSE ]]; then
    echo "Building ${IMAGE_NAME} image for Operator's HTTP-API ${HTTP_API}"
    set -xv
fi

#---------------------------------
# Validate input parameters
#---------------------------------
validates_input_parametes "no_need_check_ostree_commit"

# The script assumes the machine is registered via subscription-manager
if ! subscription-manager refresh; then
   echo  "The machine is not registered."
   exit 1
fi

#---------------------------------
# Cleanup before running
#---------------------------------
rm -rf ~/rpmbuild/*
rm -rf /home/builder
rm -rf /var/www/html/flotta-repo
rm -rf /var/www/html/$IMAGE_NAME

#---------------------------------
# Install image-builder components
#---------------------------------
dnf install -y osbuild-composer composer-cli cockpit-composer bash-completion jq firewalld
systemctl enable osbuild-composer.socket --now
systemctl enable cockpit.socket --now
systemctl start firewalld
firewall-cmd --add-service=cockpit && firewall-cmd --add-service=cockpit --permanent
source  /etc/bash_completion.d/composer-cli

#-----------------------------------
# Build packages for Flotta from source
#-----------------------------------
build_packages

#---------------------------
# Create packages repository
#---------------------------
create_repo "flotta-repo"

#-----------------------------------
# Create and publish rhel4edge image
#-----------------------------------
git clone https://github.com/project-flotta/flotta-image-builder.git /home/builder/r4e
cd /home/builder/r4e
./r4e-image.sh -s $IMAGE_SERVER_ADDRESS -i $IMAGE_NAME -o $HTTP_API -p http://$IMAGE_SERVER_ADDRESS/flotta-repo/

#----------------------------------------
# Create ISO for image and serve via http
#----------------------------------------
save_image_in_iso_format $IMAGE_SERVER_ADDRESS $IMAGE_NAME
