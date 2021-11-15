set -e
sudo yum install -y osbuild-composer composer-cli cockpit-composer genisoimage isomd5sum httpd jq
sudo systemctl enable --now cockpit.socket osbuild-composer.socket httpd
sudo usermod -aG weldr $USER
