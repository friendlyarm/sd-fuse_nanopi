#!/bin/bash

rootfspkg=prebuilt/nanopi-debian-jessie-rootfs.tgz
vendorpatch=vendor/rootfs-patch.tgz
IMAGE_FILE=nanopi.img
IMAGE_SIZE_MB=800
FAT_SIZE_MB=128

if [ ! -f ${rootfspkg} ]; then
    # download rootfs
    cd /tmp/
    rm -f nanopi-debian-jessie-rootfs.tgz
    wget http://wiki.friendlyarm.com/NanoPi/download/nanopi-debian-jessie-rootfs.tgz
    if [[ "$?" != 0 ]]; then
        echo "Error downloading file: nanopi-debian-jessie-rootfs.tgz"
        exit 1
    fi
    rm -f nanopi-debian-jessie-rootfs.tgz.hash.md5
    wget http://wiki.friendlyarm.com/NanoPi/download/nanopi-debian-jessie-rootfs.tgz.hash.md5
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
    sync
    if [ ${STAGE} -ge 3 ]; then
        umount ${PART_DEVICE}p?
        rmdir rootfs
    fi
    if [ ${STAGE} -ge 2 ]; then
        if [ ${USE_KPARTX} -ne 0 ]; then
            sleep 1
            kpartx -d ${LOOP_DEVICE}
        fi
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

if losetup -P ${LOOP_DEVICE} ${IMAGE_FILE} 2>/dev/null; then
    USE_KPARTX=0
    PART_DEVICE=${LOOP_DEVICE}
elif losetup ${LOOP_DEVICE} ${IMAGE_FILE}; then
    kpartx -a ${LOOP_DEVICE}
    USE_KPARTX=1
    PART_DEVICE=/dev/mapper/`basename ${LOOP_DEVICE}`
    sleep 1
else
    echo "Error: attach ${LOOP_DEVICE} failed, stop now."
    rm ${IMAGE_FILE}
    exit 1
fi
[ -b ${PART_DEVICE}p2 ] || {
    echo "Error: ${PART_DEVICE}p2 not exist, stop now."
    kpartx -d ${LOOP_DEVICE}
    losetup --detach ${LOOP_DEVICE}
    rm ${IMAGE_FILE}
    exit 1
}

STAGE=2

echo "Creating filesystems..."
try mkfs -t vfat ${PART_DEVICE}p1
try mkfs -t ext4 ${PART_DEVICE}p2

try tune2fs -o journal_data_writeback ${PART_DEVICE}p2
try tune2fs -O ^has_journal ${PART_DEVICE}p2

try mkdir -p rootfs
try mount -t ext4 ${PART_DEVICE}p2 rootfs
STAGE=3

try mkdir -p rootfs/boot
try mount -t vfat ${PART_DEVICE}p1 rootfs/boot
STAGE=4

echo "Extracting rootfs..."
try tar -zxf prebuilt/nanopi-debian-jessie-rootfs.tgz -C rootfs --strip-components=1

if [ -f ${vendorpatch} ]; then
    try tar -zxf ${vendorpatch} -C rootfs --strip-components=1
fi

cat > rootfs/etc/fstab << EOF
devpts /dev/pts devpts gid=5,mode=620 0 0                                       
/dev/mmcblk0p2 / ext4 errors=remount-ro,noatime,nodiratime,data=writeback 0 1
/dev/mmcblk0p1 /boot vfat defaults,noatime,nodiratime 0 2
EOF

echo "Copying kernel..."
try cp prebuilt/zImage rootfs/boot

echo "Cleaning up..."
cleanup
