#!/bin/bash

source  ./flotta-image-builder-common-functions.sh
# script for creating an image that points to a certain ostree commit from web server
# the image includes the agent RPM that communicates with server that monitors edge devices
# at the end the following products will be available for download:
#   - ostree image
#   - kickstart file
# input:
#  - <image-server-address> - IP or hostname with port if different than 80 used for connecting to the local web server
#  - <image-name> - a name for the image. allows using different ostree image for different types of edge devices
#  - <operator-http-api> - URL for connecting to the server that monitors edge devices
#  - [packages-repo-url] - optional, URL for additional packages repository
# script assumes that files `edgedevice-blueprint.tmpl` and `edgedevice.ks.tmpl` are present in the working directory

set -e

function cleanup() {
    rm -f $REPO_DIR
    if [ -n "$BUILD_ID" ]; then
        rm -f $BUILD_ID-commit.tar
    fi
}
trap 'cleanup' EXIT

IMAGE_SERVER_ADDRESS=
IMAGE_NAME=
HTTP_API=
PACKAGE_REPO_URL=
VERBOSE=

usage()
{
cat << EOF
usage: $0 options
This script will create an image file and serve it for download.
OPTIONS:
   -h      Show this message
   -s      Image server address (required)
   -i      Image name (required)
   -o      Operator's HTTP API (required)
   -p      Package repo URL (defaults to ${RAM})
   -v      Verbose
EOF
}

while getopts "h:s:i:o:p:v" option; do
    case "${option}"
    in
        h)
            usage
            exit 0
            ;;
        s) IMAGE_SERVER_ADDRESS=${OPTARG};;
        i) IMAGE_NAME=${OPTARG};;
        o) HTTP_API=${OPTARG};;
        p) PACKAGE_REPO_URL=${OPTARG};;
        v) VERBOSE=1;;
    esac
done

if [[ -z $IMAGE_SERVER_ADDRESS ]]; then
    echo "ERROR: Image Server address is required"
    usage
    exit 1
fi

if [[ -z $IMAGE_NAME ]]; then
    echo "ERROR: Image name is required"
    usage
    exit 1
fi

if [[ -z $HTTP_API ]]; then
    echo "ERROR: Operator's HTTP-API url is required"
    usage
    exit 1
fi

if [[ ! -z $VERBOSE ]]; then
    echo "Building ${IMAGE_NAME} image for Operator's HTTP-API ${HTTP_API}"
    set -xv
fi

# export for use in templates
export IMAGE_NAME
export HTTP_API

# prepare local variables
IMAGE_BASE_URL=http://$IMAGE_SERVER_ADDRESS/$IMAGE_NAME
IMAGE_FOLDER=/var/www/html/$IMAGE_NAME
export REPO_URL=$IMAGE_BASE_URL/repo

# make sure image does not already exist
if [ -e "$IMAGE_FOLDER" ] ; then
    echo "$IMAGE_FOLDER already exists"
    exit 1
fi

# create source resource if rpm repository URL is provided
if [[ ! -z $PACKAGE_REPO_URL ]] ; then
  create_source "agent" "$PACKAGE_REPO_URL"
fi

# create blueprint
BLUEPRINT_TEMPLATE=edgedevice-blueprint.tmpl
BLUEPRINT_FILE=blueprint.toml
echo "Creating blueprint $BLUEPRINT_FILE"
envsubst < $BLUEPRINT_TEMPLATE > $BLUEPRINT_FILE
composer-cli blueprints push $BLUEPRINT_FILE

# create image
echo "Creating image $IMAGE_NAME"
BUILD_ID=$(composer-cli -j compose start $IMAGE_NAME edge-commit | jq '.build_id')
waiting_for_build_to_be_ready $BUILD_ID

# extract image to web server folder
extract_image_to_web_server $BUILD_ID $IMAGE_FOLDER

# create kickstart file and copy to web server
create_kickstart_file $IMAGE_FOLDER

