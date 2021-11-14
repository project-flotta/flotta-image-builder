#!/bin/bash

if [ -x /usr/libexec/yggdrasil/device-worker ]; then
    echo "device-worker found, check passed!"
else
    echo "device-worker not found, check failed!"
    exit 1
fi

if [ "$(systemctl is-active yggdrasild.service)" = "active" ]; then
    echo "yggdrasild.service is active, check passed!"
else
    echo "yggdrasild.service is not active, check failed!"
    exit 1
fi

if [ "$(systemctl is-active nftables.service)" = "active" ]; then
    echo "nftables.service is active, check passed!"
else
    echo "nftables.service is not active, check failed!"
    exit 1
fi

if [ "$(systemctl is-active podman.service)" = "active" ]; then
    echo "podman.service is active, check passed!"
else
    echo "podman.service is not active, check failed!"
    exit 1
fi

if [ "$(systemctl is-active podman.socket)" = "active" ]; then
    echo "podman.socket is active, check passed!"
else
    echo "podman.socket is not active, check failed!"
    exit 1
fi

exit 0