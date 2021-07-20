set -e
sudo yum install -y osbuild-composer composer-cli lorax cockpit-composer genisoimage isomd5sum httpd
sudo systemctl enable --now cockpit.socket osbuild-composer.socket httpd
sudo usermod -aG weldr $USER
