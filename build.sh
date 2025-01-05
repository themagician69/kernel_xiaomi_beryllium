#!/bin/sh

echo -e "*****************************"
echo -e "**                         **"
echo -e "** Building Etude-KSU...   **"
echo -e "**                         **"
echo -e "*****************************"

export LLVM=1

# KernelSU-Next
curl -LSs "https://raw.githubusercontent.com/rifsxd/KernelSU-Next/next/kernel/setup.sh" | bash -s v1.0.2-R14

# Clang
echo "Using Prelude-Clang"
git clone -b master https://gitlab.com/jjpprrrr/prelude-clang.git --depth=1 clang

# Some general variables
KERNELNAME="Etude-Op.13-No.2-KSU-Next"
ARCH="arm64"
SUBARCH="arm64"
DEFCONFIG=beryllium_defconfig
#DEFCONFIG=beryllium_defconfig
COMPILER=clang
LINKER=""
KERNEL_DIR="$(pwd)"
COMPILERDIR="${KERNEL_DIR}/clang"

# Export shits
export KBUILD_BUILD_USER=NotDheeraj06
export KBUILD_BUILD_HOST=ArchLinux

# Select LTO variant ( Full LTO by default )
DISABLE_LTO=0
THIN_LTO=1

# Files
IMAGE=$(pwd)/out/arch/arm64/boot/Image.gz-dtb

# Clone AnyKernel
echo "Cloning AnyKernel3"
git clone --depth=1 https://github.com/Legendleo90/AnyKernel3.git -b etude AnyKernel3

# Create Logs
exec 2> >(tee -a out/error.log >&2)

# Specify Final Zip Name
ZIPNAME=Etude-KSU-Next-beryllium
FINAL_ZIP=${ZIPNAME}-${DEVICE}.zip

# Speed up build process
MAKE="./makeparallel"

# Basic build function
BUILD_START=$(date +"%s")
blue='\033[0;34m'
cyan='\033[0;36m'
yellow='\033[0;33m'
red='\033[0;31m'
nocol='\033[0m'

Build () {
PATH="${COMPILERDIR}/bin:${PATH}" \
make -j$(nproc --all) O=out \
ARCH=${ARCH} \
CC=${COMPILER} \
CROSS_COMPILE=${COMPILERDIR}/bin/aarch64-linux-gnu- \
CROSS_COMPILE_ARM32=${COMPILERDIR}/bin/arm-linux-gnueabi- \
LD_LIBRARY_PATH=${COMPILERDIR}/lib
}

Build_lld () {
PATH="${COMPILERDIR}/bin:${PATH}" \
make -j$(nproc --all) O=out \
ARCH=${ARCH} \
CC=${COMPILER} \
CROSS_COMPILE=${COMPILERDIR}/bin/aarch64-linux-gnu- \
CROSS_COMPILE_ARM32=${COMPILERDIR}/bin/arm-linux-gnueabi- \
LD=ld.${LINKER} \
AR=llvm-ar \
NM=llvm-nm \
OBJCOPY=llvm-objcopy \
OBJDUMP=llvm-objdump \
STRIP=llvm-strip \
ld-name=${LINKER} \
KBUILD_COMPILER_STRING="Prelude Clang"
}

# Make defconfig

make O=out ARCH=${ARCH} ${DEFCONFIG}
if [ $? -ne 0 ]
then
    echo "Build failed"
else
    echo "Made ${DEFCONFIG}"
fi

# Build starts here
if [ -z ${LINKER} ]
then
    Build
else
    Build_lld
fi

if [ $? -ne 0 ]
then
    echo "Build failed"
else
    echo "Build succesful"
fi

##----------------------------------------------------------------##
function zipping() {
	# Copy Files To AnyKernel3 Zip
	cp $IMAGE AnyKernel3
	
	# Zipping and Push Kernel
	cd AnyKernel3 || exit 1
        zip -r9 ${FINAL_ZIP} *
        MD5CHECK=$(md5sum "$FINAL_ZIP" | cut -d' ' -f1)
        cd ..
        }
##----------------------------------------------------------##

Build
END=$(date +"%s")
zipping


BUILD_END=$(date +"%s")
DIFF=$(($BUILD_END - $BUILD_START))
echo -e "$yellow Build completed in $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds.$nocol"
