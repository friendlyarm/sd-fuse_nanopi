#!/bin/bash

rootfspkg=prebuilt/rootfs.tgz
vendorpatch=vendor/rootfs-patch.tgz
IMAGE_FILE=nanopi.img
IMAGE_SIZE_MB=500
FAT_SIZE_MB=128

if [ ! -f ${rootfspkg} ]; then
    cat prebuilt/rootfs-split/x* > ${rootfspkg}
fi

touch ${IMAGE_FILE}

if [ $(id -u) -ne 0 ]; then
    echo "Rerunning script under sudo..."
    sudo $0 $@
    exit
fi

BLOCK_SIZE=512
let IMAGE_SIZE=(${IMAGE_SIZE_MB}*1000*1000)/${BLOCK_SIZE}
FAT_POSITION=2048
let FAT_SIZE=(${FAT_SIZE_MB}*1000*1000)/${BLOCK_SIZE}
let EXT4_POSITION=${FAT_POSITION}+${FAT_SIZE}
let EXT4_SIZE=${IMAGE_SIZE}-${FAT_SIZE}-${FAT_POSITION}

LOOP_DEVICE=$(losetup -f)

STAGE=0

cleanup() {
    if [ ${STAGE} -ge 4 ]; then
        umount rootfs/boot
    fi
    if [ ${STAGE} -ge 3 ]; then
        umount rootfs
        rmdir rootfs
    fi
    if [ ${STAGE} -ge 2 ]; then
        losetup --detach ${LOOP_DEVICE}
    fi
}

try() {
    output=$("$@" 2>&1)
    if [ $? -ne 0 ]; then
        echo "error running \"$@\""
        cleanup
        if [ ${STAGE} -ge 1 ]; then
            rm ${IMAGE_FILE}
        fi
        echo $output
        exit 1
    fi
}

try dd if=/dev/zero of=${IMAGE_FILE} bs=${BLOCK_SIZE} count=0 seek=${IMAGE_SIZE}
STAGE=1

echo "Creating partitions..."
try sfdisk -u S --Linux ${IMAGE_FILE} << EOF
${FAT_POSITION},${FAT_SIZE},0x0C,-
${EXT4_POSITION},${EXT4_SIZE},0x83,-
EOF

try losetup -P ${LOOP_DEVICE} ${IMAGE_FILE}
STAGE=2

echo "Creating filesystems..."
try mkfs -t vfat ${LOOP_DEVICE}p1
try mkfs -t ext4 ${LOOP_DEVICE}p2

try tune2fs -o journal_data_writeback ${LOOP_DEVICE}p2
try tune2fs -O ^has_journal ${LOOP_DEVICE}p2

try mkdir -p rootfs
try mount -t ext4 ${LOOP_DEVICE}p2 rootfs
STAGE=3

try mkdir -p rootfs/boot
try mount -t vfat ${LOOP_DEVICE}p1 rootfs/boot
STAGE=4

echo "Extracting rootfs..."
try tar -zxf prebuilt/rootfs.tgz -C rootfs --strip-components=1

if [ -f ${vendorpatch} ]; then
    try tar -zxf ${vendorpatch} -C rootfs --strip-components=1
fi

cat > rootfs/etc/fstab << EOF
devpts /dev/pts devpts gid=5,mode=620 0 0                                       
/dev/mmcblk0p2 / ext4 errors=remount-ro,noatime,nodiratime,data=writeback 0 1
/dev/mmcblk0p1 /boot vfat defaults,noatime,nodiratime 0 2
EOF

echo "Copying kernel..."
cp prebuilt/zImage rootfs/boot

cat > rootfs/boot/firstboot.txt << EOF
EXPAND_ROOTFS=1
MAKE_SWAP=1
SWAP_SIZE=128
EOF

echo "Cleaning up..."
cleanup
