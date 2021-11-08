#!/bin/bash
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
  echo "creating source agent"
  REPO_DIR=$(mktemp -d)
  cat << EOF > $REPO_DIR/repo.toml
id = "agent"
name = "agent"
description = "k4e agent repository"
type = "yum-baseurl"
url = "$PACKAGE_REPO_URL"
check_gpg = false
check_ssl = false
system = false
EOF

  composer-cli sources add $REPO_DIR/repo.toml
  rm -rf $REPO_DIR
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
echo "waiting for build $BUILD_ID to be ready..."
while [ $(composer-cli -j compose status  | jq -r '.[] | select( .id == '$BUILD_ID' ).status') == "RUNNING" ] ; do sleep 5 ; done
if [ $(composer-cli -j compose status  | jq -r '.[] | select( .id == '$BUILD_ID' ).status') != "FINISHED" ] ; then
    echo "image composition failed"
    echo "check 'composer-cli compose status'"
    exit 1
fi

# extract image to web server folder
echo "Saving image to web folder $IMAGE_FOLDER"
composer-cli compose image $BUILD_ID
sudo mkdir $IMAGE_FOLDER
sudo tar -xvf ${BUILD_ID//\"/}-commit.tar -C $IMAGE_FOLDER

# create kickstart file and copy to web server
ARCH=$(uname -i)
if [ "$ARCH" = "aarch64" ]; then
    export OS_NAME="rhel-edge"
    export REMOTE_OS_NAME="rhel-edge"
    export REF="rhel/8/aarch64/edge"
else
    export OS_NAME="rhel"
    export REMOTE_OS_NAME="edge"
    export REF="rhel/8/x86_64/edge"
fi

KICKSTART_TEMPLATE=edgedevice.ks.tmpl
KICKSTART_FILE=edgedevice.ks
echo "Creating kickstart file $KICKSTART_FILE"
envsubst < $KICKSTART_TEMPLATE > $KICKSTART_FILE
sudo cp $KICKSTART_FILE $IMAGE_FOLDER

echo "Image build completed successfully"
