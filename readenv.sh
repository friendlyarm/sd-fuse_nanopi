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
	echo "Usage: $0 DEVICE [ sd | sdhc ]"
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

if [ "sd$2" = "sdsd" ]; then
	echo "Card type: SD"
	RSD_BLKCOUNT=0
else
	echo "Card type: SDHC (default)"
	RSD_BLKCOUNT=1024
fi

let ENV_POSITION=${BLOCK_CNT}-${RSD_BLKCOUNT}-2-16-32


# ----------------------------------------------------------
# Read ENV data

ENV_FILE=sdenv.raw

echo "---------------------------------"
echo "Dump uboot env part to file ${ENV_FILE}..."

dd if=$1 of=${ENV_FILE} skip=${ENV_POSITION} bs=512 count=32
sync

echo "...done."

