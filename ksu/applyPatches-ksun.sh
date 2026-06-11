#!/bin/bash
#
# applyPatches.sh — ReSukiSU integration for Revive-Selene
#
# This script assumes the kernel source was cloned from a branch
# that already has ReSukiSU manual hooks integrated (e.g. 4.14-rssu).
# The KernelSU/ folder is a git submodule pointing to ReSukiSU/ReSukiSU.
# This script simply initializes the submodule so the driver source is present.

export maindir="$(pwd)"
export outside="${maindir}/.."
source "${outside}/$1env"

echo ">>> Initializing KernelSU-Next submodule..."
git submodule update --init --recursive

if [ ! -d "${maindir}/KernelSU-Next/kernel" ]; then
  echo "ERROR: KernelSU-Next/kernel not found after submodule init."
  echo "Make sure your kernel branch has .gitmodules and the KernelSU-Next submodule."
  exit 1
fi

if [ ! -L "${maindir}/drivers/kernelsu" ]; then
  echo "WARNING: drivers/kernelsu symlink missing, creating..."
  ln -sf ../KernelSU-Next/kernel "${maindir}/drivers/kernelsu"
fi

KSU_hashcommit=$(cd "${maindir}/KernelSU-Next" && git rev-parse --short=7 HEAD)

echo ">>> KernelSU-Next commit: ${KSU_hashcommit}"

# Build localversion string — avoid double dash if kernel_name is empty
if [ -n "$kernel_name" ]; then
  KSU_localversion="-${kernel_name}-ksun${KSU_hashcommit}"
else
  KSU_localversion="-ksun${KSU_hashcommit}"
fi
if grep -q 'CONFIG_LOCALVERSION=' "${defconfig_file}"; then
  sed -i "s/\(CONFIG_LOCALVERSION=\)\(.*\)/\1\"${KSU_localversion}\"/" "${defconfig_file}"
else
  echo "CONFIG_LOCALVERSION=\"${KSU_localversion}\"" >> "${defconfig_file}"
fi
echo ">>> defconfig updated: $(grep 'CONFIG_LOCALVERSION=' ${defconfig_file})"

echo -e " \nincludes KernelSU-Next (KernelSU), commit ${KSU_hashcommit}" >> banner_append

echo ">>> KernelSU-Next submodule ready."
