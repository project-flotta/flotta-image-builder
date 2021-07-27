#!/bin/bash
rpmbuild -bb --define "_topdir ." --buildroot=rpmfiles --noclean spec
