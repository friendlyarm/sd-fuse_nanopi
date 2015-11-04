#!/bin/bash

# Copyright (C) Guangzhou FriendlyARM Computer Tech. Co., Ltd.
# (http://www.friendlyarm.com)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, you can access it online at
# http://www.gnu.org/licenses/gpl-2.0.html.

# ----------------------------------------------------------
# Checking device for fusing

if [ -z $1 ]; then
	echo "Usage: $0 DEVICE"
	exit 0
fi

case $1 in
/dev/sd[a-z] | /dev/loop0)
	DEV_NAME=`basename $1`
	BLOCK_CNT=`cat /sys/block/${DEV_NAME}/size`;;
*)
	echo "Error: Unsupported SD reader"
	exit 0
esac

if [ ${BLOCK_CNT} -le 0 ]; then
	echo "Error: $1 is inaccessible. Stop fusing now!"
	exit 1
fi

if [ ${BLOCK_CNT} -gt 134217727 ]; then
	echo "Error: $1 size (${BLOCK_CNT}) is too large"
	exit 1
fi

#----------------------------------------------------------
# Execute an action
FA_DoExec() {
	echo "==> Executing: '${@}'"
	eval $@ || exit $?
}

#----------------------------------------------------------
# make fs and copy files

rootfspkg=./prebuilt/nanopi-debian-jessie-rootfs.tgz
vendorpatch=./vendor/rootfs-patch.tgz
MNT=mnt

echo "Making rootfs for NanoPi on $1..."

[ ! -d ${MNT} ] && mkdir -p ${MNT}

# umount all at first
umount /dev/${DEV_NAME}? >/dev/null 2>&1

# vfat:
FA_DoExec mkfs.vfat -F 32 /dev/${DEV_NAME}1 -n FRIENDLYARM

# optional swap:
if [ -b /dev/${DEV_NAME}3 ]; then
	FA_DoExec mkswap /dev/${DEV_NAME}3 -L SWAP
fi

# ext4: rootfs
FA_DoExec mkfs.ext4 /dev/${DEV_NAME}2 -L NANOPI

if [ ! -f ${rootfspkg} ]; then
	# download rootfs
	cd /tmp/
	rm -f nanopi-debian-jessie-rootfs.tgz
	wget  http://wiki.friendlyarm.com/NanoPi/download/nanopi-debian-jessie-rootfs.tgz
	if [[ "$?" != 0 ]]; then
	    echo "Error downloading file: nanopi-debian-jessie-rootfs.tgz"
	    exit 1
	fi
	rm -f nanopi-debian-jessie-rootfs.tgz.hash.md5
	wget  http://wiki.friendlyarm.com/NanoPi/download/nanopi-debian-jessie-rootfs.tgz.hash.md5
	if [[ "$?" != 0 ]]; then
	    echo "Error downloading file: nanopi-debian-jessie-rootfs.tgz.hash.md5."
	    exit 1
	fi
	md5sum -c nanopi-debian-jessie-rootfs.tgz.hash.md5
	if [[ "$?" != 0 ]]; then
	    echo "Incorrect MD5 please restart the program and try again."
	    exit 1
	fi
	cd -
	mv /tmp/nanopi-debian-jessie-rootfs.tgz ./prebuilt/
fi

if [ -f ${rootfspkg} ]; then
	FA_DoExec mount -t ext4 /dev/${DEV_NAME}2 ${MNT}
	FA_DoExec tar xzf ${rootfspkg} -C ${MNT} --strip-components=1
	if [ -f ${vendorpatch} ]; then
		FA_DoExec tar xzf ${vendorpatch} -C ${MNT} --strip-components=1
	fi
	if [ -b /dev/${DEV_NAME}3 ]; then
		echo "/dev/mmcblk0p3 none swap sw 0 0" >> ${MNT}/etc/fstab
	fi
	FA_DoExec umount ${MNT}
fi

sync

#----------------------------------------------------------
echo "...done."

