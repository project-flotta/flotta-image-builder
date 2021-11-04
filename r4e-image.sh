#!/bin/bash
# script for creating an image that points to a certain ostree commit from web server
# the image includes the agent RPM that communicates with server that monitors edge devices
# at the end the following products will be available for download:
#   - ostree image
#   - kickstart file
# input:
#  - <image-server-address> - IP or hostname with port if different than 80 used for connecting to the local web server
#  - <image-name> - a name for the image. allows using different ostree image for different types of edge devices
#  - <agent-server-url> - URL for connecting to the server that monitors edge devices
#  - [packages-repo-url] - optional, URL for additional packages repository
# script assumes that files `edgedevice-blueprint.tmpl` and `edgedevice.ks.tmpl` are present in the working directory

function cleanup() {
    rm -f temp.out
    rm -f $REPO_DIR
    if [ -n "$BUILD_ID" ]; then
        rm -f $BUILD_ID-commit.tar
    fi
}
trap 'cleanup' EXIT

set -e
Usage() {
    echo "Usage:"
    echo $(basename "$0") "<image-server-address> <image-name> <agent-server-url> [packages-repo-url]"
}

# check usage
if [ "$#" -lt  3 ] ; then
    echo -e "bad usage\n"
    Usage
    exit 1
fi

# read input
IMAGE_HOST=$1
export IMAGE_NAME=$2
export AGENT_URL=$3

# prepare local variables
BLUEPRINT_TEMPLATE=edgedevice-blueprint.tmpl
BLUEPRINT_FILE=blueprint.toml
KICKSTART_TEMPLATE=edgedevice.ks.tmpl
KICKSTART_FILE=edgedevice.ks
IMAGE_BASE_URL=http://$IMAGE_HOST/$IMAGE_NAME
IMAGE_FOLDER=/var/www/html/$IMAGE_NAME
export REPO_URL=$IMAGE_BASE_URL/repo

# make sure image does not already exist
if [ -e "$IMAGE_FOLDER" ] ; then
    echo "$IMAGE_FOLDER already exists"
    exit 1
fi

# create source resource if rpm repository URL is provided
if [ -n "$4" ] ; then
  echo "creating source agent"
  REPO_DIR=$(mktemp -d)
  cat << EOF > $REPO_DIR/repo.toml
id = "agent"
name = "agent"
description = "k4e agent repository"
type = "yum-baseurl"
url = "$4"
check_gpg = false
check_ssl = false
system = false
EOF

  composer-cli sources add $REPO_DIR/repo.toml
  rm -rf $REPO_DIR
fi

# create blueprint
echo "creating blueprint $BLUEPRINT_FILE"
envsubst < $BLUEPRINT_TEMPLATE > $BLUEPRINT_FILE
composer-cli blueprints push $BLUEPRINT_FILE

# create image
echo "creating image $IMAGE_NAME"
composer-cli compose start $IMAGE_NAME rhel-edge-commit > temp.out
BUILD_ID=$(awk '{print $2}' temp.out)
echo "waiting for build $BUILD_ID to be ready..."
while [ "$(composer-cli compose status | grep $BUILD_ID | grep -c RUNNING)" != "0" ] ; do sleep 5 ; done
if [ "$(composer-cli compose status | grep $BUILD_ID | grep -c FINISHED)" == "0" ] ; then
    echo "image composition failed"
    echo "check 'composer-cli compose status'"
    exit 1
fi

# extract image to web server folder
echo "saving image to web folder $IMAGE_FOLDER"
composer-cli compose image $BUILD_ID
sudo mkdir $IMAGE_FOLDER
sudo tar -xvf $BUILD_ID-commit.tar -C $IMAGE_FOLDER

# create kickstart file and copy to web server
ARCH=$(uname -i)
if [ "$ARCH" = "aarc64" ]; then
    export OS_NAME="rhel-edge"
    export REMOTE_OS_NAME="rhel-edge"
    export REF="rhel/8/aarch64/edge"
else
    export OS_NAME="rhel"
    export REMOTE_OS_NAME="edge"
    export REF="rhel/8/x86_64/edge"
fi
echo "creating kickstart file $KICKSTART_FILE"
envsubst < $KICKSTART_TEMPLATE > $KICKSTART_FILE
sudo cp $KICKSTART_FILE $IMAGE_FOLDER

echo "Image build completed successfully"
