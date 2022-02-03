#!/bin/bash

set -e

validates_input_parametes(){
  dnf install -y bind-utils
  if [[ -z $IMAGE_SERVER_ADDRESS ]]; then
      hostname_output=$(host $(hostname))
      for word in $hostname_output
      do
        if [[ ($word =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$)  && ($word != "127.0.0.1")]]; then
          echo "found hostname"
          IMAGE_SERVER_ADDRESS=$word
          break
        fi
      done
      if [[ -z $IMAGE_SERVER_ADDRESS ]]; then
        echo "ERROR: server address is required"
        usage
        exit 1
      fi
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

  if [[ -z $FLOTTA_GITHUB_ORG ]]; then
     FLOTTA_GITHUB_ORG="project-flotta"
  fi

  if [[ -z $FLOTTA_GITHUB_BRANCH ]]; then
     FLOTTA_GITHUB_BRANCH="main"
  fi

  if [[ $1 == "check_ostree_commit" ]]; then
    if [[ -z $OSTREE_COMMIT ]]; then
      echo "ERROR: Ostree parent commit is required"
      usage
      exit 1
    fi
  fi

  return
}

build_packages(){
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

  # Build flotta-device-worker rpm
  git clone https://github.com/$FLOTTA_GITHUB_ORG/flotta-device-worker.git /home/builder/flotta-device-worker
  cd /home/builder/flotta-device-worker
  git checkout $FLOTTA_GITHUB_BRANCH

  if [ "$ARCH" = "aarch64" ]; then
      make build-arm64
      make rpm-arm64
  else
      make build
      make rpm
  fi

  # Build Prometheus node_exporter rpm
  git clone https://github.com/project-flotta/prometheus-node_exporter-rpm.git /home/builder/prometheus-node_exporter-rpm
  cd /home/builder/prometheus-node_exporter-rpm
  make rpm

  return
}

create_repo(){
  PACKAGES_REPO=$1
  dnf install -y createrepo httpd
  systemctl enable --now httpd
  firewall-cmd --zone=public --add-port=80/tcp --permanent
  firewall-cmd --reload

  mkdir /var/www/html/"$PACKAGES_REPO"
  cp /root/rpmbuild/RPMS/${ARCH}/*.${ARCH}.rpm /var/www/html/"$PACKAGES_REPO"/
  createrepo /var/www/html/"$PACKAGES_REPO"/

  return

}

create_source(){
  echo "creating source agent"
  SOURCE_NAME=$1
  PACKAGE_REPO_URL=$2

  REPO_DIR=$(mktemp -d)
  cat << EOF > $REPO_DIR/repo.toml
id = "$SOURCE_NAME"
name = "$SOURCE_NAME"
description = "Flotta agent repository"
type = "yum-baseurl"
url = "$PACKAGE_REPO_URL"
check_gpg = false
check_ssl = false
system = false
EOF

  composer-cli sources add $REPO_DIR/repo.toml
  rm -rf $REPO_DIR

}

extract_image_to_web_server(){
  BUILD_ID=$1
  IMAGE_FOLDER=$2

  echo "Saving image to web folder $IMAGE_FOLDER"
  composer-cli compose image $BUILD_ID
  sudo mkdir $IMAGE_FOLDER
  sudo tar -xvf ${BUILD_ID//\"/}-commit.tar -C $IMAGE_FOLDER

}

create_kickstart_file(){
  IMAGE_FOLDER=$1
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
}

save_image_in_iso_format(){
  IMAGE_SERVER_ADDRESS=$1
  IMAGE_NAME=$2

  cd /home/builder/r4e
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

  # Save image in ISO format
  dnf install -y jq isomd5sum genisoimage
  composer-cli blueprints push $ISO_BLUEPRINT
  BUILD_ID=$(composer-cli -j compose start-ostree --ref $REF --url http://$IMAGE_SERVER_ADDRESS/$IMAGE_NAME/repo/ edgedevice-iso edge-installer | jq '.build_id')
  waiting_for_build_to_be_ready $BUILD_ID

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
}

waiting_for_build_to_be_ready(){
  BUILD_ID=$1

  echo "waiting for build $BUILD_ID to be ready..."
  while [ $(composer-cli -j compose status  | jq -r '.[] | select( .id == '$BUILD_ID' ).status') == "RUNNING" ] ; do sleep 5 ; done
  if [ $(composer-cli -j compose status  | jq -r '.[] | select( .id == '$BUILD_ID' ).status') != "FINISHED" ] ; then
      echo "image composition failed"
      echo "check 'composer-cli compose status'"
      exit 1
  fi
}