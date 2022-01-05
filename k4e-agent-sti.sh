#!/bin/bash

set -e

# The script performs the following steps on rhel-8.5:
# * Install image-builder
# * Create rpms for yggdrasil and k4e-device-worker
# * Publish rpms as yum repo to be consumed by image-builder
# * Publish rhel4edge image for edge-device


IMAGE_NAME=
HTTP_API=
VERBOSE=

usage()
{
cat << EOF
usage: $0 options
This script will create an image file and ISO to be served for download.
OPTIONS:
   -h      Show this message
   -i      Image name (required)
   -o      Operator's HTTP API (required)
   -v      Verbose
EOF
}

while getopts "h:i:o:v" option; do
    case "${option}"
    in
        h)
            usage
            exit 0
            ;;
        i) IMAGE_NAME=${OPTARG};;
        o) HTTP_API=${OPTARG};;
        v) VERBOSE=1;;
    esac
done

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
rm -rf /var/www/html/k4e-repo
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
# Build packages for k4e from source
#-----------------------------------
mkdir -p /home/builder
dnf install -y dbus-devel systemd-devel git golang rpm-build make
rm -rf ~/rpmbuild/*

# Build yggdrasil rpm
git clone https://github.com/jakub-dzon/yggdrasil.git /home/builder/yggdrasil
cd /home/builder/yggdrasil
export CGO_ENABLED=0

export ARCH=$(uname -i)
GOPROXY=proxy.golang.org,direct PWD=$PWD spec=$PWD outdir=$PWD make -f .copr/Makefile srpm
rpm -ihv $(ls -ltr yggdrasil-*.src.rpm | tail -n 1 | awk '{print $NF}')
if [ "$ARCH" = "aarch64" ]; then
    # Turn ELF binary stripping off in %post
    sed -i '1s/^/%global __os_install_post %{nil}/' ~/rpmbuild/SPECS/yggdrasil.spec
fi
rpmbuild -bb ~/rpmbuild/SPECS/yggdrasil.spec --target $ARCH

# Build k4e-device-worker rpm
git clone https://github.com/jakub-dzon/k4e-device-worker.git /home/builder/k4e-device-worker
cd /home/builder/k4e-device-worker
if [ "$ARCH" = "aarch64" ]; then
    make build-arm64
    make rpm-arm64
else
    make build
    make rpm
fi

# Build Prometheus node_exporter rpm
git clone https://github.com/jakub-dzon/prometheus-node_exporter-rpm.git /home/builder/prometheus-node_exporter-rpm
cd /home/builder/prometheus-node_exporter-rpm
make rpm


#---------------------------
# Create packages repository
#---------------------------
dnf install -y createrepo httpd
systemctl enable --now httpd
firewall-cmd --zone=public --add-port=80/tcp --permanent
firewall-cmd --reload

mkdir /var/www/html/k4e-repo
cp /root/rpmbuild/RPMS/${ARCH}/*.${ARCH}.rpm /var/www/html/k4e-repo/
createrepo /var/www/html/k4e-repo/

#-----------------------------------
# Create and publish rhel4edge image
#-----------------------------------
git clone https://github.com/ydayagi/r4e.git /home/builder/r4e
cd /home/builder/r4e
./r4e-image.sh -s $(hostname) -i $IMAGE_NAME -o $HTTP_API -p http://$(hostname)/k4e-repo/

#----------------------------------------
# Create ISO for image and serve via http
#----------------------------------------
ISO_BLUEPRINT=$(mktemp)
cat << EOF > $ISO_BLUEPRINT
name = "edgedevice-iso"
description = "Empty blueprint for ISO creation"
version = "0.0.1"
EOF

if [ "$ARCH" = "aarch64" ]; then
    REF="rhel/8/aarch64/edge"
else
    REF="rhel/8/x86_64/edge"
fi

#-------------------------
# Save image in ISO format
#-------------------------
dnf install -y jq isomd5sum genisoimage
composer-cli blueprints push $ISO_BLUEPRINT
BUILD_ID=$(composer-cli -j compose start-ostree --ref $REF --url http://$(hostname)/$IMAGE_NAME/repo/ edgedevice-iso edge-installer | jq '.build_id')
echo "waiting for build $BUILD_ID to be ready..."
while [ $(composer-cli -j compose status  | jq -r '.[] | select( .id == '$BUILD_ID' ).status') == "RUNNING" ] ; do sleep 5 ; done
if [ $(composer-cli -j compose status  | jq -r '.[] | select( .id == '$BUILD_ID' ).status') != "FINISHED" ] ; then
    echo "image composition failed"
    echo "check 'composer-cli compose status'"
    exit 1
fi
composer-cli compose image $BUILD_ID
ISO_FILE=${BUILD_ID//\"/}-installer.iso

echo "copy and edit ISO contents of $ISO_FILE"
ISO_TMP_DIR=$(mktemp -d)
ISO_MNT_DIR=$(mktemp -d)
mount -o loop $ISO_FILE $ISO_MNT_DIR
cp -ra $ISO_MNT_DIR/* $ISO_TMP_DIR
cp -ra $ISO_MNT_DIR/.??* $ISO_TMP_DIR
umount $ISO_MNT_DIR
rm -rf $ISO_MNT_DIR

# edit kickstart file
if [ "$ARCH" = "aarch64" ]; then
    OS_NAME="rhel-edge"
    REF="rhel/8/aarch64/edge"
else
    OS_NAME="rhel"
    REF="rhel/8/x86_64/edge"
fi

WWW_DIR=/var/www/html/$IMAGE_NAME
sed "s#^ostreesetup.*#ostreesetup --osname=$OS_NAME --url=file:///run/install/repo/ostree/repo --ref=$REF --nogpg#" $WWW_DIR/edgedevice.ks > $ISO_TMP_DIR/osbuild.ks

VOLUME_ID=$(isoinfo -d -i $ISO_FILE  | grep 'Volume id:')
rm $ISO_FILE
cd $ISO_TMP_DIR
if [ "$ARCH" = "aarch64" ]; then
    dnf install -y xorriso
    xorriso -as mkisofs -V ${VOLUME_ID#*:} -r -o $WWW_DIR/$ISO_FILE -J -joliet-long -cache-inodes -efi-boot-part --efi-boot-image -e images/efiboot.img -no-emul-boot .
else
    genisoimage -U -r -v -T -J -joliet-long -V ${VOLUME_ID#*:} -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e images/efiboot.img -no-emul-boot -o $WWW_DIR/$ISO_FILE .
fi

implantisomd5 $WWW_DIR/$ISO_FILE
rm -rf $ISO_TMP_DIR
rm -f $ISO_BLUEPRINT
