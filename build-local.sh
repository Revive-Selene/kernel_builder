#!/bin/bash
# ============================================================
#  build-local.sh — Local/VPS kernel builder for selene
#  Converted from revive-selene/kernel_builder main.yml
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colors ──────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET} $*"; }
ok()      { echo -e "${GREEN}[OK]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*"; exit 1; }
section() { echo -e "\n${BOLD}━━━ $* ━━━${RESET}"; }

# ── Defaults (same as main.yml) ─────────────────────────────
DEFAULT_COMPILER="shattered-Clang-15"
DEFAULT_KREPO="https://github.com/Revive-Selene/android_kernel_xiaomi_selene"
DEFAULT_KBRANCH="4.14"
DEFAULT_KSU=""
DEFAULT_CONTAINER=""   # unused locally, just for reference
DEFAULT_NOTES=""
DEFAULT_VERBOSE=""
DEFAULT_ZREPO=""
DEFAULT_ZBRANCH=""

# ── Interactive prompt with default ─────────────────────────
ask() {
  local prompt="$1" default="$2" varname="$3"
  if [ -n "$default" ]; then
    read -rp "$(echo -e "${BOLD}${prompt}${RESET} [${CYAN}${default}${RESET}]: ")" val
    eval "$varname=\"${val:-$default}\""
  else
    read -rp "$(echo -e "${BOLD}${prompt}${RESET} [leave blank to skip]: ")" val
    eval "$varname=\"$val\""
  fi
}

# ── Parse args or go interactive ────────────────────────────
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
  echo "Usage: $0 [--yes]"
  echo "  --yes   Skip prompts, use all defaults"
  exit 0
fi

USE_DEFAULTS=0
[ "$1" = "--yes" ] && USE_DEFAULTS=1

section "Build Configuration"

if [ "$USE_DEFAULTS" = "1" ]; then
  COMPILER="$DEFAULT_COMPILER"
  KREPO="$DEFAULT_KREPO"
  KBRANCH="$DEFAULT_KBRANCH"
  KSU="$DEFAULT_KSU"
  NOTES="$DEFAULT_NOTES"
  VERBOSE="$DEFAULT_VERBOSE"
  ZREPO="$DEFAULT_ZREPO"
  ZBRANCH="$DEFAULT_ZBRANCH"
  info "Using all defaults."
else
  ask "Compiler to use"         "$DEFAULT_COMPILER"  COMPILER
  ask "Kernel repo URL"         "$DEFAULT_KREPO"     KREPO
  ask "Kernel branch"           "$DEFAULT_KBRANCH"   KBRANCH
  ask "Build with ReSukiSU? (yes = with KSU, blank = no KSU)" "$DEFAULT_KSU" KSU
  ask "Extra notes"             "$DEFAULT_NOTES"     NOTES
  ask "Verbose logging? (1 = yes, blank = no)" "$DEFAULT_VERBOSE" VERBOSE
  ask "Custom AnyKernel3 repo"  "$DEFAULT_ZREPO"     ZREPO
  ask "Custom AnyKernel3 branch" "$DEFAULT_ZBRANCH"  ZBRANCH
fi

# Override env zipper vars if custom provided
[ -n "$ZREPO" ]   && export zipper_repo="$ZREPO"
[ -n "$ZBRANCH" ] && export zipper_branch="$ZBRANCH"

# ── Summary ─────────────────────────────────────────────────
section "Summary"
echo -e "  Compiler      : ${CYAN}${COMPILER}${RESET}"
echo -e "  Kernel repo   : ${CYAN}${KREPO}${RESET}"
echo -e "  Branch        : ${CYAN}${KBRANCH}${RESET}"
echo -e "  ReSukiSU      : ${CYAN}${KSU:-none}${RESET}"
echo -e "  AK3 repo      : ${CYAN}${ZREPO:-from env}${RESET}"
echo -e "  AK3 branch    : ${CYAN}${ZBRANCH:-from env}${RESET}"
echo -e "  Notes         : ${CYAN}${NOTES:-none}${RESET}"
echo -e "  Verbose       : ${CYAN}${VERBOSE:-off}${RESET}"
echo ""
read -rp "$(echo -e "${BOLD}Proceed? [Y/n]: ${RESET}")" confirm
[[ "$confirm" =~ ^[Nn]$ ]] && { info "Aborted."; exit 0; }

# ── Validate KSU + branch combination ───────────────────────
section "Validating configuration"

if [ "$KSU" = "yes" ] && ! echo "$KBRANCH" | grep -q "rssu"; then
  error "KSU=yes requires a ReSukiSU branch (e.g. 4.14-rssu).\n  Your branch '$KBRANCH' does not contain ReSukiSU hooks.\n  Either set KSU blank or change branch to 4.14-rssu."
fi

if [ -z "$KSU" ] && echo "$KBRANCH" | grep -q "rssu"; then
  warn "Branch '$KBRANCH' has ReSukiSU integrated but KSU is blank."
  warn "Kernel will compile but ReSukiSU version string will NOT be applied."
fi

ok "Validation passed."

# ── Toolchain setup ──────────────────────────────────────────
section "Setting up toolchain: $COMPILER"
bash -x "${SCRIPT_DIR}/toolchains/${COMPILER}.sh" setup

# ── Clone or rebase kernel ───────────────────────────────────
section "Kernel source"

KERNEL_DIR="${SCRIPT_DIR}/kernel"

if [ -d "$KERNEL_DIR/.git" ]; then
  info "Kernel directory already exists, checking branch..."
  cd "$KERNEL_DIR"
  CURRENT_REMOTE=$(git remote get-url origin 2>/dev/null || echo "")
  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

  if [ "$CURRENT_REMOTE" != "$KREPO" ]; then
    warn "Remote mismatch (current: $CURRENT_REMOTE)"
    warn "Re-cloning from $KREPO..."
    cd "$SCRIPT_DIR"
    rm -rf "$KERNEL_DIR"
    git clone --depth=1 --single-branch --recurse-submodules -j4 "$KREPO" -b "$KBRANCH" kernel
  elif [ "$CURRENT_BRANCH" != "$KBRANCH" ]; then
    info "Switching branch from '$CURRENT_BRANCH' to '$KBRANCH'..."
    git fetch origin "$KBRANCH" --depth=1
    git checkout "$KBRANCH"
    git reset --hard "origin/$KBRANCH"
  else
    info "Already on branch '$KBRANCH', rebasing to latest..."
    git fetch origin "$KBRANCH" --depth=1
    git reset --hard "origin/$KBRANCH"
  fi
  ok "Kernel source up to date."
else
  info "Cloning kernel from: $KREPO (branch: $KBRANCH)"
  git clone --depth=1 --single-branch --recurse-submodules -j4 "$KREPO" -b "$KBRANCH" kernel
fi

cd "$KERNEL_DIR"
source "${SCRIPT_DIR}/env"

# ── Print kernel info ────────────────────────────────────────
section "Kernel info"
echo -e "  Name    : ${CYAN}${kernel_name:-N/A}${RESET}"
echo -e "  Version : ${CYAN}${kernel_ver:-N/A}${RESET}"
echo -e "  Head    : ${CYAN}$(git rev-parse --short HEAD)${RESET}"
echo -e "  Config  : ${CYAN}${defconfig:-N/A}${RESET}"
echo -e "  KSU     : ${CYAN}${KSU:-none}${RESET}"

# ── Notes ────────────────────────────────────────────────────
[ -n "$NOTES" ] && { section "Notes"; echo -e "  ${YELLOW}${NOTES}${RESET}"; }

# ── Apply ReSukiSU patches ───────────────────────────────────
if [ "$KSU" = "yes" ]; then
  section "Applying ReSukiSU patches"
  bash "${SCRIPT_DIR}/ksu/applyPatches.sh"
  ok "Patches applied."
fi

# ── Build ────────────────────────────────────────────────────
section "Building kernel"
BUILD_START=$(date +"%s")
export CUR_TOOLCHAIN="$COMPILER"
export VERBOSE

if [ -n "$VERBOSE" ]; then
  bash -x "${SCRIPT_DIR}/build.sh" "$COMPILER" 2>&1 | tee "${SCRIPT_DIR}/${COMPILER}.log"
else
  bash "${SCRIPT_DIR}/build.sh" "$COMPILER" 2>&1 | tee "${SCRIPT_DIR}/${COMPILER}.log"
fi

BUILD_END=$(date +"%s")
DIFF=$((BUILD_END - BUILD_START))

# ── Result ───────────────────────────────────────────────────
section "Result"
source "${SCRIPT_DIR}/env"

if ls "${SCRIPT_DIR}/kernel/"*.zip &>/dev/null 2>&1; then
  ok "Build succeeded in $((DIFF / 60))m $((DIFF % 60))s"
  echo ""
  echo -e "${BOLD}Output files:${RESET}"
  ls -lh "${SCRIPT_DIR}/kernel/"*.zip
else
  echo -e "${RED}❌ Build failed in $((DIFF / 60))m $((DIFF % 60))s${RESET}"
  echo -e "   Check log: ${SCRIPT_DIR}/${COMPILER}.log"
  exit 1
fi