#!/bin/bash

source  ./flotta-image-builder-common-functions.sh
set -e

# The script performs the following steps on rhel-8.5:
# * Create new rpms for yggdrasil, flotta-device-worker and Prometheus node_exporter
# * Publish rpms as yum repo to be consumed by image-builder
# * Publish rhel4edge image commit for edge-device
# * ./flotta-agent-sti-upgrade.sh -a <server_adress> -i <image_name> -o <operator_host_name:operator_port> -p <parent_commit> -v

export IMAGE_SERVER_ADDRESS=
export IMAGE_NAME=
export HTTP_API=
export FLOTTA_GITHUB_ORG=
export FLOTTA_GITHUB_BRANCH=
export VERBOSE=
export OSTREE_COMMIT=
export SUFFIX=$(date +%s)

usage()
{
cat << EOF
usage: $0 options
This script will create an image commit to be served for upgrade.
OPTIONS:
   -h      Show this message
   -a      Image server address
   -i      Original Image name(required)
   -o      Operator's HTTP API (required)
   -p      Ostree parent commit(required)
   -g      GitHub organization for flotta-device-worker repo (optional)
   -b      GitHub branch name for flotta-device-worker repo (optional)
   -v      Verbose
EOF
}

while getopts "h:a:i:o:p:g:b:v" option; do
    case "${option}"
    in
        h)
            usage
            exit 0
            ;;
        a) IMAGE_SERVER_ADDRESS=${OPTARG};;
        i) IMAGE_NAME=${OPTARG};;
        o) HTTP_API=${OPTARG};;
        p) OSTREE_COMMIT=${OPTARG};;
        g) FLOTTA_GITHUB_ORG=${OPTARG};;
        b) FLOTTA_GITHUB_BRANCH=${OPTARG};;
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
validates_input_parametes "check_ostree_commit"

#---------------------------------
# Set temporary variables
#---------------------------------
export SOURCE_NAME="flotta-agent-$SUFFIX"
export PACKAGES_REPO=flotta-repo-$SUFFIX
export PACKAGE_REPO_URL=http://$IMAGE_SERVER_ADDRESS/$PACKAGES_REPO
export BLUEPRINT_NAME=$IMAGE_NAME
export UPGRADED_IMAGE_NAME=$IMAGE_NAME-upgrade
export IMAGE_UPGRADE_FOLDER=/var/www/html/$UPGRADED_IMAGE_NAME
export IMAGE_UPGRADE_URL=http://$IMAGE_SERVER_ADDRESS/$UPGRADED_IMAGE_NAME

#---------------------------------
# Cleanup before running
#---------------------------------
rm -rf ~/rpmbuild/*
rm -rf /var/www/html/flotta-repo*
rm -rf /home/builder/yggdrasil
rm -rf /home/builder/flotta-device-worker
rm -rf /home/builder/prometheus-node_exporter-rpm
rm -rf $IMAGE_UPGRADE_FOLDER
# need to remove all sources
composer-cli sources delete agent

#-----------------------------------
# Build packages for Flotta from source
#-----------------------------------
build_packages

#---------------------------
# Create packages repository
#---------------------------
create_repo "$PACKAGES_REPO"

#-----------------------------------
# Create and publish rhel4edge new commit
#-----------------------------------
cd /home/builder/r4e
create_source "$SOURCE_NAME" "$PACKAGE_REPO_URL"

composer-cli blueprints depsolve "$BLUEPRINT_NAME"

# create an image commit
if [ "$ARCH" = "aarch64" ]; then
    REF="rhel/8/aarch64/edge"
else
    REF="rhel/8/x86_64/edge"
fi

echo "Creating commit $IMAGE_NAME"
BUILD_ID=$(composer-cli -j compose start-ostree --parent $OSTREE_COMMIT --ref $REF $BLUEPRINT_NAME edge-commit | jq '.build_id')
waiting_for_build_to_be_ready $BUILD_ID


#-----------------------------------
# extract image to web server folder
# and create an ISO image format
#-----------------------------------
# make sure image does not already exist
if [ -e "$IMAGE_UPGRADE_FOLDER" ] ; then
    echo "$IMAGE_UPGRADE_FOLDER already exists"
    exit 1
fi

extract_image_to_web_server $BUILD_ID $IMAGE_UPGRADE_FOLDER
create_kickstart_file $IMAGE_UPGRADE_FOLDER
save_image_in_iso_format $IMAGE_SERVER_ADDRESS $UPGRADED_IMAGE_NAME

composer-cli sources delete "$SOURCE_NAME"
echo "commit is available in $IMAGE_UPGRADE_URL"