#!/bin/bash

if [ -x /usr/libexec/yggdrasil/device-worker ]; then
echo "device-worker found, check passed!"
exit 0
else
echo "device-worker not found, check failed!"
exit 1
fi