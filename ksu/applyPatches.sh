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

KSU_hashcommit=$(cd "${maindir}/KernelSU" && git rev-parse --short=7 HEAD)

echo ">>> ReSukiSU commit: ${KSU_hashcommit}"

# Build localversion string — preserve '#' if it was originally in defconfig
orig_localversion=$(grep 'CONFIG_LOCALVERSION=' "${defconfig_file}" 2>/dev/null | sed 's/CONFIG_LOCALVERSION=//g' | sed 's/"//g')
if [[ "$orig_localversion" == *"#"* ]]; then
  clean_name="${kernel_name#(HASTAG)}"
  KSU_localversion="-#${clean_name}-rssu${KSU_hashcommit}"
else
  if [ -n "$kernel_name" ]; then
    KSU_localversion="-${kernel_name}-rssu${KSU_hashcommit}"
  else
    KSU_localversion="-rssu${KSU_hashcommit}"
  fi
fi
if grep -q 'CONFIG_LOCALVERSION=' "${defconfig_file}"; then
  sed -i "s/\(CONFIG_LOCALVERSION=\)\(.*\)/\1\"${KSU_localversion}\"/" "${defconfig_file}"
else
  echo "CONFIG_LOCALVERSION=\"${KSU_localversion}\"" >> "${defconfig_file}"
fi
echo ">>> defconfig updated: $(grep 'CONFIG_LOCALVERSION=' ${defconfig_file})"

echo -e " \nincludes ReSukiSU (KernelSU), commit ${KSU_hashcommit}" >> banner_append

echo ">>> ReSukiSU submodule ready."
