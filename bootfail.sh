#!/bin/bash

echo "greenboot detected a boot failure" >> /var/roothome/greenboot.log
date >> /var/roothome/greenboot.log
grub2-editenv list | grep boot_counter >> /var/roothome/greenboot.log
echo "----------------" >> /var/roothome/greenboot.log
echo "" >> /var/roothome/greenboot.log