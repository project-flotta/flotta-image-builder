# RHEL for edge
## Build ISO for edge devices
- prepare host with RHEL8.4+ - 2 CPUs, 4GB memory and 20GB of storage. It may be a VM, CNV VM or physical appliance. Web server running must be reachable by edge devices.
- use a user with sudo - make sure user does not need to enter password each time (set NOPASSWD in sudoers file)
- make sure selinux is running in permissive mode
- register the system
    ```
    sudo subscription-manager register --username <redhat_login_username> --password <redhat_login_password> --auto-attach
    ```
- clone or download this repository to the RHEL host
- [download](https://access.redhat.com/downloads/content/479/ver=/rhel---8/8.4/x86_64/product-software) RHEL boot ISO to root folder of the repository
- make sure there is yum repo available with [yggdrasil](https://github.com/jakub-dzon/yggdrasil) and [device-worker](https://github.com/project-flotta/flotta-device-worker/)
- create repo.toml pointing to above repo
    ```
    id = "agent"
    name = "agent"
    type = "yum-baseurl"
    url = "<repo-url>"
    check_gpg = false
    check_ssl = false
    system = false
    ```
- execute r4e-setup.sh
- add the repo as composer source by running;
    ```
    composer-cli sources add repo.toml
    ```
- execute r4e-img-builder-iso.sh
- test that new image is ready:
  * browse to
    ```
    http://<host-ip>/<image-name>
    ```
    you should see a listing of the image directory:
    ```
    - ISO file
    - kickstart file
    - repo folder
    ```
 
 
## update the image
In the builder machine:
- The root folder should have more than 15GB available, you can extend it by:
  * resize the virtual machine disk before that step make sure the VM isn't running
   ```
     qemu-img resize <img> +15G
   ```  
  * run the VM and resize the root partition and the filesystem (inside the VM):
   ```   
     growpart /dev/sda 3
     resize2fs /dev/sda3
   ```
- source specifying the repository for the packages - copy the RPM new version file to the yum repo directory that was mentioned before
- edit `blueprint.toml` to include the new version(s) packages. example of `blueprint.toml` can be
     ``` 
     name = "edge-nov3-1-0"
     description = "RHEL for Edge"
     version = "0.0.1"
     modules = []
     groups = []
     
     [[packages]]
     name = "yggdrasil"
     version = "*"
     [[packages]]
     name = "flotta-agent"
     version = "1.1"
     ```
- run r4e-img-upgrade-iso.sh which:
  * creates a new blueprint
  * creates a commit (by using start-ostree) 
  * builds an upgrade image
  * save the image as an iso file
  Be sure 'jq' was installed before running that command  

In the edge device machine:
- update the file `/etc/ostree/remotes.d/edge.conf` to point the url of the new commit 
- for checking there is an updated image available 
    ``` 
    rpm-ostree update --preview
    ```
- configure automate rolling upgrade by using greenboot 
 
- copy the script greenboot-health-check.sh to `/etc/greenboot/check/required.d/greenboot-health-check.sh` 
  An health check script that must not fail (if they do, GreenBoot will initiate a rollback)
  ```
  chmod +x /etc/greenboot/check/required.d/greenboot-health-check.sh
  ```
- copy the script bootfail.sh to `/etc/greenboot/red.d/bootfail.sh`
  scripts that should be run after GreenBoot has declared the boot as failed.
  ```
  chmod +x /etc/greenboot/red.d/bootfail.sh
  ```
- for updating run
    ```
    rpm-ostree update
    rpm-ostree status 
    systemctl reboot
   ```
  if the greenboot would be failed after several runs greenboot would roll back automatically 
- in order to see greenboot logs: 
   ```
  systemctl status greenboot-status
   ```
   