# script for creating an update ISO
# the image includes the updated agent RPM that communicates with server that monitors edge devices
# at the end an upgraded ostree image will be available
# input:
#  - original-image-name that was chosen for the first step (Build ISO for edge devices)
#  - parrent-ostree-commit can be found in the original image webserver under in compose.json file under the key 'ostree-commit'
#  - image-version-number the new version of the image
# script assumes that file `blueprint.toml` is present and updated in the working directory and also that jq already install
set -e
Usage() {
    echo "Usage:"
    echo `basename $0` "<original-image-name> <parrent-ostree-commit> <image-version-number>"
}

# check usage
if [ $# != 3 ] ; then
    echo -e "bad usage\n"
    Usage
    exit 1
fi

# read input
export IMAGE_NAME=$1
export OSTREE_COMMIT=$2
export IMAGE_VERSION=$3
export NEW_IMAGE_NAME=${IMAGE_NAME}-${IMAGE_VERSION}

# prepare local variables
IMAGE_FOLDER=/var/www/html/${NEW_IMAGE_NAME}
BLUEPRINT_FILE=blueprint.toml
BLUEPRINT_NAME=${IMAGE_NAME}


# create a new blueprint
composer-cli blueprints push $BLUEPRINT_FILE

# validate blueprint
echo "validating blueprint $BLUEPRINT_NAME"
composer-cli blueprints depsolve $BLUEPRINT_NAME

# build image using the composer based on the parent commit create a new commit- first find the parent commit hash in http://<host-ip>/<image-name>/compose.json under "ostree-commit"
echo "creating a new commit from parrent $OSTREE_COMMIT using blueprint $BLUEPRINT_NAME"
BUILD_ID=$(composer-cli -j compose start-ostree $BLUEPRINT_NAME rhel-edge-commit --parent $OSTREE_COMMIT| jq '.build_id'| tr -d '"')
echo "waiting for build $BUILD_ID to be ready..."
while [ "$(composer-cli -j compose status | jq -r '.[] | select( .id == '$BUILD_ID' ).status')" == "RUNNING" ] ; do sleep 5 ; done
if [ "$(composer-cli -j compose status  | jq -r '.[] | select( .id == '$BUILD_ID' ).status')" != "FINISHED" ] ; then
    echo "image composition failed"
    echo "check 'composer-cli compose status'"
    exit 1
fi

# saving image to web folder
echo "saving the new image to the web folder $IMAGE_FOLDER"
composer-cli compose image $BUILD_ID
sudo mkdir $IMAGE_FOLDER
sudo tar -xvf $BUILD_ID-commit.tar -C $IMAGE_FOLDER
rm -f $BUILD_ID-commit.tar
