# RHEL for edge
## Build ISO for edge devices
- prepare host with RHEL8.4+. 2 CPUs and 4GB should be enough for small scale requirements. It may be a VM, CNV VM or physical appliance. the host must be reachable by the edge devices at port 80/tcp. it also has to be reachable for booting the edge devices from network.
- use a user with sudo - make sure user does not need to enter password each time (set NOPASSWD in sudoers file)
- register the system
    ```
    sudo subscription-manager register --username <redhat_login_username> --password <redhat_login_password> --auto-attach
    ```
- clone or download this repository to the RHEL host
- download RHEL boot ISO to root folder of the repository
- execute r4e-setup.sh
- re-login with the same user
- execute r4e-iso.sh
- test that new image is ready:
  * browse to http://<host-ip>/<image-name> - you should see a listing of the image directory:
    - ISO file
    - kickstart file
    - rpeo folder
