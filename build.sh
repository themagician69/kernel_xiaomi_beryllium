#!/bin/sh

echo -e "*****************************"
echo -e "**                         **"
echo -e "** Building Etude-KSU...   **"
echo -e "**                         **"
echo -e "*****************************"

export LLVM=1

# KernelSU-Next
curl -LSs "https://raw.githubusercontent.com/rifsxd/KernelSU-Next/next/kernel/setup.sh" | bash -s legacy

# --- APPLY FIX HERE (KernelSU commit fix) ---
echo "Applying KernelSU-Next commit fix..."
KSU_PATH=$(find . -maxdepth 3 -type d -name "kernelsu")
if [ -d "$KSU_PATH" ]; then
    cd "$KSU_PATH"
    git fetch https://github.com/KernelSU-Next/KernelSU-Next.git cfd00daefb846a525fee64dc884b64759c3d0424
    git cherry-pick cfd00daefb846a525fee64dc884b64759c3d0424 || true
    cd -
else
    echo "Warning: KernelSU directory not found for patching!"
fi

# --- HOOK PATCHING ---
if [ -f "syscall_hook_patches.sh" ]; then
    echo "Running syscall hook patches..."
    bash syscall_hook_patches.sh
else
    echo "Warning: syscall_hook_patches.sh not found in root directory!"
fi

# Clang
echo "Using Prelude-Clang"
git clone -b master https://gitlab.com/jjpprrrr/prelude-clang.git --depth=1 clang

# --- GLOBAL TOOLCHAIN EXPORTS (Fixes ld.lld: not found completely) ---
export COMPILERDIR="$(pwd)/clang"
export PATH="${COMPILERDIR}/bin:${PATH}"
export CC=clang
export LD=ld.lld

# Some general variables
KERNELNAME="Etude-Op.13-No.2-KSU-Next"
ARCH="arm64"
SUBARCH="arm64"
DEFCONFIG=beryllium_defconfig
COMPILER=clang
KERNEL_DIR="$(pwd)"

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
git clone --depth=1 https://github.com/Legendleo90/AnyKernel3.git AnyKernel3

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

# --- FINAL FIX FOR SELINUX_HIDE.C ON KERNEL 4.9 ---
TARGET_FILE="drivers/kernelsu/feature/selinux_hide.c"

if [ -f "$TARGET_FILE" ]; then
    echo "Patching security_context_to_sid in $TARGET_FILE for Kernel 4.9..."
    
    python3 -c '
file_path = "drivers/kernelsu/feature/selinux_hide.c"
with open(file_path, "r") as f:
    lines = f.readlines()

new_lines = []
for line in lines:
    if "security_context_to_sid(" in line and "selinux_state" not in line:
        line = line.replace("security_context_to_sid(", "security_context_to_sid(&selinux_state, ")
    new_lines.append(line)

with open(file_path, "w") as f:
    f.writelines(new_lines)

print("Successfully injected &selinux_state into security_context_to_sid calls.")
'
else
    echo "Error: $TARGET_FILE not found!"
    exit 1
fi

# Make defconfig
make O=out ARCH=${ARCH} ${DEFCONFIG}
if [ $? -ne 0 ]
then
    echo "Defconfig failed"
    exit 1
else
    echo "Made ${DEFCONFIG}"
fi

# Force direct execution of Build_lld with global exports active
echo "Running LLD build..."
make -j$(nproc --all) O=out \
ARCH=${ARCH} \
CC=${COMPILER} \
CROSS_COMPILE=${COMPILERDIR}/bin/aarch64-linux-gnu- \
CROSS_COMPILE_ARM32=${COMPILERDIR}/bin/arm-linux-gnueabi- \
LD=ld.lld \
AR=llvm-ar \
NM=llvm-nm \
OBJCOPY=llvm-objcopy \
OBJDUMP=llvm-objdump \
STRIP=llvm-strip \
ld-name=lld \
KBUILD_COMPILER_STRING="Prelude Clang"

if [ $? -ne 0 ]
then
    echo "Build failed"
    exit 1
else
    echo "Build successful"
fi

##----------------------------------------------------------------##
zipping() {
	# Copy Files To AnyKernel3 Zip
	cp $IMAGE AnyKernel3
	
	# Zipping and Push Kernel
	cd AnyKernel3 || exit 1
        zip -r9 ${FINAL_ZIP} *
        MD5CHECK=$(md5sum "$FINAL_ZIP" | cut -d' ' -f1)
        cd ..
}
##----------------------------------------------------------##

END=$(date +"%s")
zipping

BUILD_END=$(date +"%s")
DIFF=$(($BUILD_END - $BUILD_START))
echo -e "$yellow Build completed in $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds.$nocol"
