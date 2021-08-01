#!/bin/bash
rpmbuild -bb --define "_topdir $PWD" --buildroot=$PWD/rpmfiles --noclean spec
