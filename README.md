# RHEL for edge
## Build ISO for edge devices
- prepare host with RHEL8.6+ - 2 CPUs, 4GB memory and 20GB of storage. It may be a VM, CNV VM or physical appliance. Web server running must be reachable by edge devices.
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
- use a user with sudo - make sure user does not need to enter password each time (set NOPASSWD in sudoers file)
- make sure selinux is running in permissive mode
- register the system
    ```
    sudo subscription-manager register --username <redhat_login_username> --password <redhat_login_password> --auto-attach
    ```
- execute flotta-agent-sti.sh for creating rhel4edge image for edge-device
    ```
    ./flotta-agent-sti.sh -a <image-server-address>  -i <image-name> -o <operator_host_name:operator_port> -v
    ```
 
 
## Upgrade device
In the builder machine:
- execute flotta-agent-sti-upgrade.sh for creating rhel4edge commit on top of image or commit for upgrading edge-device
    ```
    ./flotta-agent-sti-upgrade.sh -a <server_adress> -i <image_name> -o <operator_host_name:operator_port> -p <parent_commit> -v

    ```
  
In the edge device machine:
- update the remote url of edge (you might see it under `/etc/ostree/remotes.d/edge.conf`) to point the url of the new commit 
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
   