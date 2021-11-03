#!/bin/bash

set -e

# The scripts performs the following steps on rhel-8.5:
# * Install imagebuilder 
# * Create rpms for yggdrasil and k4e-device-worker
# * Publish rpms as yum repo to be consumed by imagebuilder
# * Publish aarch64 rhel-image for edge-device

# The script assumes the machine is registered via subscription-manager
#if ! `subscription-manager status | grep -q Disabled`; then
#   echo  "The machine is not registered."
#   exit 1
#fi

#---------------------------
# Install osbuild components
#---------------------------
dnf install -y osbuild-composer composer-cli cockpit-composer bash-completion
systemctl enable osbuild-composer.socket --now
systemctl enable cockpit.socket --now
systemctl start firewalld
firewall-cmd --add-service=cockpit && firewall-cmd --add-service=cockpit --permanent
source  /etc/bash_completion.d/composer-cli

#-----------------------------------
# Build packages for k4e from source
#-----------------------------------
mkdir /home/builder

dnf install -y dbus-devel systemd-devel git golang rpm-build
rm -rf ~/rpmbuild/rpmbuild/*

# Build yggdrasil rpm
git clone https://github.com/jakub-dzon/yggdrasil.git /home/builder/yggdrasil
cd /home/builder/yggdrasil
export CGO_ENABLED=0

export ARCH=$(uname -i)
GOPROXY=proxy.golang.org,direct PWD=$PWD spec=$PWD outdir=$PWD make -f .copr/Makefile srpm
rpm -ihv `ls -ltr yggdrasil-*.src.rpm | tail -n 1 | awk '{print $NF}'`
if [ $ARCH = "aarc64" ]; then
    # Turn ELF binary stripping off in %post
    sed -i '1s/^/%global __os_install_post %{nil}/' ~/rpmbuild/SPECS/yggdrasil.spec
fi
rpmbuild -bb ~/rpmbuild/SPECS/yggdrasil.spec --target $ARCH

# Build k4e-device-worker rpm
git clone https://github.com/jakub-dzon/k4e-device-worker.git /home/builder/k4e-device-worker
cd /home/builder/k4e-device-worker
if [ $ARCH = "aarc64" ]; then
    make build-arm64
    make rpm-arm64
else
    make build
    make rpm
fi

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

if [ $ARCH = "aarc64" ]; then
    ./r4e-aarch-image.sh `hostname` edgedevice helios05.lab.eng.tlv2.redhat.com:8888 http://`hostname`/k4e-repo/
else
    ./
fi

#----------------------------------------
# Create ISO for image and serve via http
#----------------------------------------
cat << EOF > /tmp/empty.toml
name = "empty"
description = "Empty blueprint"
version = "0.0.1"
EOF

cd /var/www/html/edgedevice
composer-cli blueprints push /tmp/empty.toml
composer-cli compose start-ostree --ref "rhel/8/aarch64/edge" --url http://`hostname`/edgedevice/repo/ empty edge-installer > temp.out
BUILD_ID=`cat temp.out | awk '{print $2}'`
echo "waiting for build $BUILD_ID to be ready..."
while [ "`composer-cli compose status | grep $BUILD_ID | grep -c RUNNING`" != "0" ] ; do sleep 5 ; done
if [ "`composer-cli compose status | grep $BUILD_ID | grep -c FINISHED`" == "0" ] ; then
    echo "image composition failed"
    echo "check 'composer-cli compose status'"
    exit 1
fi
composer-cli compose image $BUILD_ID
