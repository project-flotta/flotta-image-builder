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
- make sure there is yum repo available with [yggdrasil](https://github.com/jakub-dzon/yggdrasil) and [device-worker](https://github.com/jakub-dzon/k4e-device-worker/)
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
- execute r4e-iso.sh
- test that new image is ready:
  * browse to
    ```
    http://<host-ip>/<image-name>
    ```
    you should see a listing of the image directory:
    ```
    - ISO file
    - kickstart file
    - rpeo folder
    ```
