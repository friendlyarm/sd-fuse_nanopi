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

# Automatically re-run script under sudo if not root
if [ $(id -u) -ne 0 ]; then
  echo "Rerunning script under sudo..."
  sudo "$0" "$@"
  exit
fi

try() {
	output=$("$@" 2>&1)
	if [ $? -ne 0 ]; then
		echo "error running \"$@\""
		echo "$output"
		exit 1
	fi
}

# ----------------------------------------------------------
# Prebuilt images and host tool

UBOOT_BIN=./prebuilt/u-boot.bin
KERNELIMG=./prebuilt/zImage
ENV_FILE=./prebuilt/sdenv.raw

# ----------------------------------------------------------
# Checking device for fusing

if [ -z $1 ]; then
	echo "Usage: $0 DEVICE [sd]"
	exit 0
fi

case $1 in
/dev/sd[a-z] | /dev/loop0)
	if [ ! -e $1 ]; then
		echo "Error: $1 does not exist."
		exit 1
	fi
	DEV_NAME=`basename $1`
	BLOCK_CNT=`cat /sys/block/${DEV_NAME}/size`;;
*)
	echo "Error: Unsupported SD reader"
	exit 0
esac

if [ -z ${BLOCK_CNT} -o ${BLOCK_CNT} -le 0 ]; then
	echo "Error: $1 is inaccessible. Stop fusing now!"
	exit 1
fi

if [ ${BLOCK_CNT} -gt 134217727 ]; then
	echo "Error: $1 size (${BLOCK_CNT}) is too large"
	exit 1
fi

if [ "sd$2" = "sdsd" -o ${BLOCK_CNT} -le 4194303 ]; then
	echo "Card type: SD"
	BL1_OFFSET=0
else
	echo "Card type: SDHC"
	BL1_OFFSET=1024
fi

BL1_SIZE=16
ENV_SIZE=32
BL2_SIZE=512
KERNEL_SIZE=12288

DEBUG_PRINT=0
USE_SWAP=1
FAT_POSITION=2048
FAT_SIZE=250000
SWAP_SIZE=262144

let BL1_POSITION=${BLOCK_CNT}-${BL1_OFFSET}-${BL1_SIZE}-2
let ENV_POSITION=${BL1_POSITION}-${ENV_SIZE}
let BL2_POSITION=${ENV_POSITION}-${BL2_SIZE}
let KERNEL_POSITION=${BL2_POSITION}-${KERNEL_SIZE}
#echo ${KERNEL_POSITION}

let EXT4_POSITION=${FAT_POSITION}+${FAT_SIZE}
let EXT4_SIZE=${KERNEL_POSITION}-${FAT_POSITION}-${FAT_SIZE}

if [ ${USE_SWAP} -eq 1 ]; then
	let EXT4_SIZE=${EXT4_SIZE}-${SWAP_SIZE}
	let SWAP_POSITION=${EXT4_POSITION}+${EXT4_SIZE}
fi

if [ ${DEBUG_PRINT} -eq 1 ]; then
	let FAT_END=${FAT_POSITION}+${FAT_SIZE}
	let EXT4_END=${EXT4_POSITION}+${EXT4_SIZE}
	let SWAP_END=${SWAP_POSITION}+${SWAP_SIZE}
	let KERNEL_END=${KERNEL_POSITION}+${KERNEL_SIZE}
	let BL2_END=${BL2_POSITION}+${BL2_SIZE}
	let ENV_END=${ENV_POSITION}+${ENV_SIZE}
	let BL1_END=${BL1_POSITION}+${BL1_SIZE}

	echo
	printf "%8s %9s %9s %8s\n" "" SIZE START END
	echo "--------------------------------------"
	printf "%8s %9d %9d %9d\n" FAT: ${FAT_SIZE} ${FAT_POSITION} ${FAT_END}
	printf "%8s %9d %9d %9d\n" EXT4: ${EXT4_SIZE} ${EXT4_POSITION} ${EXT4_END}
	if [ ${USE_SWAP} ]; then
		printf "%8s %9d %9d %9d\n" SWAP: ${SWAP_SIZE} ${SWAP_POSITION} ${SWAP_END}
	fi
	printf "%8s %9d %9d %9d\n" KERNEL: ${KERNEL_SIZE} ${KERNEL_POSITION} ${KERNEL_END}
	printf "%8s %9d %9d %9d\n" BL2: ${BL2_SIZE} ${BL2_POSITION} ${BL2_END}
	printf "%8s %9d %9d %9d\n" ENV: ${ENV_SIZE} ${ENV_POSITION} ${ENV_END}
	printf "%8s %9d %9d %9d\n" BL1: ${BL1_SIZE} ${BL1_POSITION} ${BL1_END}
	echo "--------------------------------------"
	printf "%-28s %9d\n" "TOTAL BLOCKS" ${BLOCK_CNT}
	echo "--------------------------------------"
	echo
fi

# ----------------------------------------------------------
# partition card

echo "---------------------------------"
echo "make $1 partition"

# umount all at first
umount /dev/${DEV_NAME}* > /dev/null 2>&1

if [ ${USE_SWAP} ]; then
	try sfdisk -u S -f --Linux /dev/${DEV_NAME} << EOF
${FAT_POSITION},${FAT_SIZE},0x0C,-
${EXT4_POSITION},${EXT4_SIZE},0x83,-
${SWAP_POSITION},${SWAP_SIZE},0x82,-
EOF
else
	try sfdisk -u S -f --Linux /dev/${DEV_NAME} << EOF
${FAT_POSITION},${FAT_SIZE},0x0C,-
${EXT4_POSITION},${EXT4_SIZE},0x83,-
EOF
fi

# ----------------------------------------------------------
# Create a u-boot binary for movinand/mmc boot

# padding to 256k u-boot
dd if=/dev/zero bs=1k count=256 2> /dev/null | tr "\000" "\377" > u-boot-256k.bin
dd if=${UBOOT_BIN} of=u-boot-256k.bin conv=notrunc 2> /dev/null

# ----------------------------------------------------------
# Fusing uboot, kernel to card

echo "---------------------------------"
echo "BL2 fusing"
dd if=u-boot-256k.bin of=/dev/${DEV_NAME} bs=512 seek=${BL2_POSITION} count=512

echo "---------------------------------"
echo "BL1 fusing"
dd if=u-boot-256k.bin of=/dev/${DEV_NAME} bs=512 seek=${BL1_POSITION} count=16

# remove generated files
rm u-boot-256k.bin

if [ -f ${ENV_FILE} ]; then
  echo "---------------------------------"
  echo "ENV fusing"
  dd if=${ENV_FILE} of=/dev/${DEV_NAME} bs=512 seek=${ENV_POSITION} count=32
fi

echo "---------------------------------"
echo "zImage fusing"
dd if=${KERNELIMG} of=/dev/${DEV_NAME} bs=512 seek=${KERNEL_POSITION}

sync

#<Message Display>
echo "---------------------------------"
echo "U-boot and kernel image is fused successfully."

sync

partprobe /dev/${DEV_NAME}
if [ $? -ne 0 ]; then
    echo "Re-read the partition table failed."
    exit 1
fi

sleep 1

./mkrootfs.sh /dev/${DEV_NAME}

echo "---------------------------------"
echo "Rootfs is fused successfully."
echo "All done."

