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

# 2. Execute Manual / Syscall Hook Patches Script
if [ -f "syscall_hook_patches.sh" ]; then
    bash syscall_hook_patches.sh ./
    echo "[+] Executed syscall hook patches successfully."
else
    echo "[-] Error: syscall_hook_patches.sh not found in kernel root!"
    exit 1
fi

# 3. Apply SELinux and static state sed patches for Linux 4.9
echo "[+] Applying static state sed patches..."
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
        fi
        if grep -q "selinux_status_page" "security/selinux/ss/status.c" >/dev/null 2>&1; then
            sed -i 's/^static struct page \*selinux_status_page/struct page *selinux_status_page/' security/selinux/ss/status.c
        fi
        if grep -q "selinux_status_lock" "security/selinux/ss/status.c" >/dev/null 2>&1; then
            sed -i 's/^static DEFINE_MUTEX(selinux_status_lock)/DEFINE_MUTEX(selinux_status_lock)/' security/selinux/ss/status.c
        fi
    fi
    echo "[+] Static state patches applied."
fi

# Clang
echo "Using Prelude-Clang"
git clone -b master https://gitlab.com/jjpprrrr/prelude-clang.git --depth=1 clang

# General variables
KERNELNAME="Etude-Op.13-No.2-xxKSU"
ARCH="arm64"
SUBARCH="arm64"
DEFCONFIG=beryllium_defconfig
COMPILER=clang
LINKER=""
KERNEL_DIR="$(pwd)"
COMPILERDIR="${KERNEL_DIR}/clang"

export KBUILD_BUILD_USER=NotDheeraj06
export KBUILD_BUILD_HOST=ArchLinux

DISABLE_LTO=0
THIN_LTO=1

IMAGE=$(pwd)/out/arch/arm64/boot/Image.gz-dtb

# Clone AnyKernel
echo "Cloning AnyKernel3"
git clone --depth=1 https://github.com/Legendleo90/AnyKernel3.git -b electro AnyKernel3

exec 2> >(tee -a out/error.log >&2)

ZIPNAME=Etude-xxKSU-beryllium
FINAL_ZIP=${ZIPNAME}-${DEVICE}.zip

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
CROSS
