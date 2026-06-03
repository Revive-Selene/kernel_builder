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

echo ">>> Initializing ReSukiSU submodule..."
git submodule update --init --recursive

if [ ! -d "${maindir}/KernelSU/kernel" ]; then
  echo "ERROR: KernelSU/kernel not found after submodule init."
  echo "Make sure your kernel branch has .gitmodules and the KernelSU submodule."
  exit 1
fi

if [ ! -L "${maindir}/drivers/kernelsu" ]; then
  echo "WARNING: drivers/kernelsu symlink missing, creating..."
  ln -sf ../KernelSU/kernel "${maindir}/drivers/kernelsu"
fi

KSU_ver=$(cd "${maindir}/KernelSU" && git rev-list --count HEAD)
KSU_display=$(($KSU_ver + 10000 + 200))

echo ">>> ReSukiSU version: ${KSU_display} (git commits: ${KSU_ver})"

sed -i "s/\(CONFIG_LOCALVERSION=\)\(.*\)/\1\"-${kernel_name}-ks${KSU_display}\"/" "${defconfig_file}"
echo ">>> defconfig updated: $(grep 'CONFIG_LOCALVERSION=' ${defconfig_file})"

echo -e " \nincludes ReSukiSU, ver ${KSU_display}" >> banner_append

echo ">>> ReSukiSU submodule ready."
