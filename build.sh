#!/bin/sh

echo -e "*****************************"
echo -e "**                         **"
echo -e "** Building Etude-xxKSU... **"
echo -e "**                         **"
echo -e "*****************************"

export LLVM=1

# 1. Clone xxKSU (backslashxx/KernelSU) into drivers/kernelsu
echo "Cloning xxKSU (backslashxx/KernelSU)"
git clone https://github.com/backslashxx/KernelSU.git drivers/kernelsu

# 2. Execute Syscall Hook Patches Script
# (Ensure syscall_hook_patches.sh is present in your kernel root directory)
if [ -f "syscall_hook_patches.sh" ]; then
    bash syscall_hook_patches.sh ./
    echo "[+] Executed syscall hook patches successfully."
else
    echo "[-] syscall_hook_patches.sh not found in kernel root!"
    exit 1
fi

# 3. Apply Sed Logic for Non-Kprobe / Static State (Linux 4.9 Compatible)
echo "[+] Applying SELinux and static state sed patches..."
KERNEL_VERSION=$(head -n 3 Makefile | grep -E 'VERSION|PATCHLEVEL' | awk '{print $3}' | paste -sd '.')
FIRST_VERSION=$(echo "$KERNEL_VERSION" | awk -F '.' '{print $1}')
SECOND_VERSION=$(echo "$KERNEL_VERSION" | awk -F '.' '{print $2}')

if ! grep -rq "check_symbol_export" "drivers/kernelsu/tools/static_export_check.mk" >/dev/null 2>&1; then
    echo "[-] Your KernelSU needn't this check progress, Skipped."
else
    if grep "const write_op" "security/selinux/selinuxfs.c" >/dev/null 2>&1; then
        sed -i 's/static ssize_t (\*const write_op\[\])(struct file \*, char \*, size_t)/ssize_t (*const write_op[])(struct file *, char *, size_t)/' security/selinux/selinuxfs.c
    else
        sed -i 's/static ssize_t (\*write_op\[\])(struct file \*, char \*, size_t)/ssize_t (*write_op[])(struct file *, char *, size_t)/' security/selinux/selinuxfs.c
    fi
    sed -i 's/^static const struct file_operations sel_handle_status_ops = {/const struct file_operations sel_handle_status_ops = {/' security/selinux/selinuxfs.c
    sed -i 's/static void security_dump_masked_av(struct policydb \*policydb,/void security_dump_masked_av(struct policydb *policydb,/' security/selinux/ss/services.c
    sed -i 's/static void context_struct_compute_av(struct policydb \*policydb,/void context_struct_compute_av(struct policydb *policydb,/' security/selinux/ss/services.c

    if [ "$FIRST_VERSION" -lt 5 ] && [ "$SECOND_VERSION" -lt 15 ]; then
        if grep -q "sel_mutex" "security/selinux/selinuxfs.c" >/dev/null 2>&1; then
            sed -i 's/^static DEFINE_MUTEX(sel_mutex)/DEFINE_MUTEX(sel_mutex)/' security/selinux/selinuxfs.c
            echo "[+] Removed sel_mutex static state."
        fi
        if grep -q "selinux_status_page" "security/selinux/ss/status.c" >/dev/null 2>&1; then
            sed -i 's/^static struct page \*selinux_status_page/struct page *selinux_status_page/' security/selinux/ss/status.c
            echo "[+] Removed selinux_status_page static state."
        fi
        if grep -q "selinux_status_lock" "security/selinux/ss/status.c" >/dev/null 2>&1; then
            sed -i 's/^static DEFINE_MUTEX(selinux_status_lock)/DEFINE_MUTEX(selinux_status_lock)/' security/selinux/ss/status.c
            echo "[+] Removed selinux_status_lock static state."
        fi
    fi

    echo "[+] Checked and patched static state successfully."
fi

# Clang
echo "Using Prelude-Clang"
git clone -b master https://gitlab.com/jjpprrrr/prelude-clang.git --depth=1 clang

# Some general variables
KERNELNAME="Etude-Op.13-No.2-xxKSU"
ARCH="arm64"
SUBARCH="arm64"
DEFCONFIG=beryllium_defconfig
COMPILER=clang
LINKER=""
KERNEL_DIR="$(pwd)"
COMPILERDIR="${KERNEL_DIR}/clang"

# Export shits
export KBUILD_BUILD_USER=Dramoled
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
ZIPNAME=Etude-xxKSU-beryllium
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
