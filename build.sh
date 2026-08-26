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

# --- FOOLPROOF SELINUX_HIDE FIX WITH CLEANUP ---
SELINUX_HIDE_FILE=$(find . -name "selinux_hide.c" -path "*/drivers/kernelsu/*")
if [ -f "$SELINUX_HIDE_FILE" ]; then
    echo "Cleaning any previous edits on selinux_hide.c..."
    # Discard any local modifications to this specific file to start fresh
    git -C "$(dirname "$SELINUX_HIDE_FILE")" checkout selinux_hide.c 2>/dev/null || true

    echo "Patching security_context_to_sid via string matching in $SELINUX_HIDE_FILE..."
    
    # Apply the clean 5-argument transformation
    sed -i 's/security_context_to_sid("u:r:ksu:s0"/security_context_to_sid(\&selinux_state, "u:r:ksu:s0"/g' "$SELINUX_HIDE_FILE"
    sed -i 's/security_context_to_sid("u:r:priv_app:s0/security_context_to_sid(\&selinux_state, "u:r:priv_app:s0/g' "$SELINUX_HIDE_FILE"
    
    echo "Checking modified lines in selinux_hide.c:"
    grep -n "security_context_to_sid" "$SELINUX_HIDE_FILE"
else
    echo "Warning: selinux_hide.c not found!"
fi


# Clang
echo "Using Prelude-Clang"
git clone -b master https://gitlab.com/jjpprrrr/prelude-clang.git --depth=1 clang

# Some general variables
KERNELNAME="Etude-Op.13-No.2-KSU-Next"
ARCH="arm64"
SUBARCH="arm64"
DEFCONFIG=beryllium_defconfig
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
