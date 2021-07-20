# script for creating an ISO that pulls a certain ostree image/rpeo from web server
# the image includes the agent RPM that communicates with server that monitors edge devices
# at the end the following products will be available for download:
#   - ISO file
#   - ostree image
#   - kickstart file (ISO already points to it)
# input:
#  - ip or hostname used for connecting to the local web server
#  - a name for the image. allows using different ISO and ostree image for different types of edge devices
#  - URL for connecting to the server that monitors edge devices
#  - path to boot ISO file
# script assumes that files `blueprint.template` and `ks.cfg.template` are present in the working directory
set -e
Usage() {
    echo "Usage:"
    echo `basename $0` "<image-server-host> <image-name> <agent-server-url> <path-to-boot-iso>"
}

# check usage
if [ $# != 4 ] ; then
    echo -e "bad usage\n"
    Usage
    exit 1
fi

# read input
IMAGE_HOST=$1
export IMAGE_NAME=$2
export AGENT_URL=$3
BOOT_ISO=$4

# prepare local variables
IMAGE_BASE_URL=http://$IMAGE_HOST:80/$IMAGE_NAME
BLUEPRINT_TEMPLATE=blueprint.template
BLUEPRINT_FILE=blueprint.toml
KICKSTART_TEMPLATE=ks.cfg.template
KICKSTART_FILE=ks.cfg
KICKSTART_URL=$IMAGE_BASE_URL/$KICKSTART_FILE
export REPO_URL=$IMAGE_BASE_URL/repo
IMAGE_FOLDER=/var/www/html/$IMAGE_NAME
ISO_FILE=$IMAGE_FOLDER/$IMAGE_NAME-boot.iso

# make sure image does not already exist
if [ -e $IMAGE_FOLDER ] ; then
    echo "$IMAGE_FOLDER already exists"
    exit 1
fi

# create blueprint
echo "creating blueprint $BLUEPRINT_FILE"
envsubst < $BLUEPRINT_TEMPLATE > $BLUEPRINT_FILE
composer-cli blueprints push $BLUEPRINT_FILE

# create image
echo "creating image $IMAGE_NAME"
composer-cli compose start $IMAGE_NAME rhel-edge-commit > temp.out
BUILD_ID=`cat temp.out | awk '{print $2}'`
echo "waiting for build $BUILD_ID to be ready..."
while [ "`composer-cli compose status | grep $BUILD_ID | grep -c RUNNING`" != "0" ] ; do sleep 5 ; done
if [ "`composer-cli compose status | grep $BUILD_ID | grep -c FINISHED`" == "0" ] ; then
    echo "image composition failed"
    echo "check 'composer-cli compose status'"
    exit 1
fi

# extract image to web server folder
echo "saving image to web folder"
composer-cli compose image $BUILD_ID
sudo mkdir /var/www/html/$IMAGE_NAME
sudo tar -xvf $BUILD_ID-commit.tar -C $IMAGE_FOLDER
rm -f $BUILD_ID-commit.tar

# create kickstart file and copy to web server
echo "creating kickstart file $KICKSTART_FILE"
envsubst < $KICKSTART_TEMPLATE > $KICKSTART_FILE
sudo cp $KICKSTART_FILE $IMAGE_FOLDER

# edit ISO content
echo "copy and edit ISO contents of $BOOT_ISO"
ISO_MNT=`mktemp -d`
ISO_DIR=`mktemp -d`
sudo mount $BOOT_ISO $ISO_MNT
sudo cp -Rf $ISO_MNT/* $ISO_DIR
sudo umount $ISO_MNT
rm -rf $ISO_MNT
sudo chown -R $USER:$GROUPS $ISO_DIR
chmod -R 777 $ISO_DIR
KICKSTART_URL_ESCAPED=$(echo $KICKSTART_URL | sed 's/\//\\\//g')
sed -i "s/append initrd=initrd\.img/append initrd=initrd.img inst.ks=$KICKSTART_URL_ESCAPED/" $ISO_DIR/isolinux/isolinux.cfg

# create new ISO file
echo "create $ISO_FILE from $ISO_DIR"
VOLUME_ID=`isoinfo -d -i $BOOT_ISO  | grep 'Volume id:' | cut -d ':' -f2 | tr -d ' '`
cd $ISO_DIR
sudo genisoimage -U -r -v -T -J -joliet-long -V $VOLUME_ID -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e images/efiboot.img -no-emul-boot -o $ISO_FILE .
cd -
sudo implantisomd5 $ISO_FILE

# cleanup
rm -rf $ISO_DIR

echo "ISO build completed successfully"
