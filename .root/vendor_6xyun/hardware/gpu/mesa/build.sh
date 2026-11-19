#!/usr/bin/env bash
#
# Mesa Panfrost 出树交叉构建（Android / arm64 + arm）
#
# 默认使用 AOSP 树内工具链（clang + bionic + libc++），不依赖外部 NDK。
# 只读引用 external/mesa3d 与 external/libdrm，不修改、不复制上游源码。
# 产物写入 out/artifacts/<arch>/，由 vendor/6xyun/prebuilts/gpu/mesa/ 的 Soong 模块交付。
#
# 同时构建 arm64 与 arm：Android 的 zygote64_32 会启动 32 位 app_process32，
# 它在预加载 EGL 时只搜索 /vendor/lib/egl，缺少 arm 产物会直接 abort。
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

die() { echo "错误: $*" >&2; exit 1; }
info() { echo "==> $*"; }

usage() {
    cat <<'EOF'
用法: build.sh [--toolchain=aosp|ndk] [--aosp-root=DIR] [--out-dir=DIR] [--install] [--prepare-only] [--clean]

脚本可以从任意目录调用：AOSP 根目录按 AOSP_ROOT / ANDROID_BUILD_TOP /
ANDROID_PRODUCT_OUT / 当前目录 / 脚本所在目录 依次自动定位。

工具链:
  aosp        默认。使用树内 clang + bionic 头/库 + 树内 libc++，不需要 NDK
  ndk         使用完整 Android NDK（需要 ANDROID_NDK_ROOT）

环境变量:
  AOSP_ROOT                          显式指定 AOSP 根目录
  OUT_DIR                            输出目录，默认 <脚本目录>/out
  ARCHES                             要构建的架构，默认 "arm64 arm"
  ANDROID_API_LEVEL                  目标 API 级别；aosp 默认 37，ndk 默认 35
  ANDROID_NDK_ROOT / ANDROID_NDK_HOME  仅 ndk 模式需要
  MESA_SRC / LIBDRM_SRC              源码目录覆盖
  PREFIX                             安装前缀根目录，默认 <OUT_DIR>/stage
  BUILD_DIR                          构建目录，默认 <OUT_DIR>/build
  PREBUILT_DIR                       预编译库目录，默认 <vendor>/prebuilts/gpu/mesa
  MESA_BUILDTYPE                     Mesa buildtype，默认 release

每个架构的产物安装到 <PREFIX>/<arch>，预编译库安装到 <PREBUILT_DIR>/<arch>。

--install       构建完成后把每个架构的五个 .so、Android.bp 与哈希复制到 PREBUILT_DIR
--prepare-only  只准备 sysroot 与交叉文件，不调用 meson
--clean         删除 OUT_DIR 后重新开始
EOF
}

CLEAN=0
PREPARE_ONLY=0
INSTALL=0
TOOLCHAIN_MODE="${TOOLCHAIN_MODE:-aosp}"
CLI_AOSP_ROOT="${AOSP_ROOT:-}"
CLI_OUT_DIR="${OUT_DIR:-}"
for arg in "$@"; do
    case "$arg" in
        -h|--help) usage; exit 0 ;;
        --clean) CLEAN=1 ;;
        --prepare-only) PREPARE_ONLY=1 ;;
        --install) INSTALL=1 ;;
        --toolchain=*) TOOLCHAIN_MODE="${arg#--toolchain=}" ;;
        --aosp-root=*) CLI_AOSP_ROOT="${arg#--aosp-root=}" ;;
        --out-dir=*) CLI_OUT_DIR="${arg#--out-dir=}" ;;
        *) die "未知参数: $arg（用 --help 查看用法）" ;;
    esac
done

read -r -a ARCH_LIST <<< "${ARCHES:-arm64 arm}"
[ "${#ARCH_LIST[@]}" -gt 0 ] || die "ARCHES 不能为空"
for arch in "${ARCH_LIST[@]}"; do
    case "$arch" in
        arm64|arm) ;;
        *) die "不支持的架构: $arch（可选 arm64 / arm）" ;;
    esac
done

if [ "$INSTALL" -eq 1 ] && [ "$PREPARE_ONLY" -eq 1 ]; then
    die "--install 与 --prepare-only 不能同时使用"
fi

case "$TOOLCHAIN_MODE" in
    aosp|ndk) ;;
    *) die "不支持的工具链: $TOOLCHAIN_MODE（可选 aosp / ndk）" ;;
esac

find_aosp_root() {
    local d="$1"
    [ -n "$d" ] || return 1
    [ -d "$d" ] || d="$(dirname -- "$d")"
    while [ "$d" != "/" ] && [ -n "$d" ]; do
        if [ -f "$d/build/envsetup.sh" ]; then
            printf '%s\n' "$d"
            return 0
        fi
        d="$(dirname -- "$d")"
    done
    return 1
}

# 依次尝试：envsetup -> product out -> 当前目录 -> 脚本目录
resolve_aosp_root() {
    local cand
    if [ -n "${ANDROID_BUILD_TOP:-}" ] && [ -f "$ANDROID_BUILD_TOP/build/envsetup.sh" ]; then
        (cd -- "$ANDROID_BUILD_TOP" && pwd -P)
        return 0
    fi
    if [ -n "${ANDROID_PRODUCT_OUT:-}" ]; then
        if cand="$(find_aosp_root "$ANDROID_PRODUCT_OUT")"; then
            printf '%s\n' "$cand"
            return 0
        fi
    fi
    if cand="$(find_aosp_root "$PWD")"; then
        printf '%s\n' "$cand"
        return 0
    fi
    find_aosp_root "$SCRIPT_DIR"
}

if [ -n "$CLI_AOSP_ROOT" ]; then
    AOSP_ROOT="$(cd -- "$CLI_AOSP_ROOT" 2>/dev/null && pwd -P)" \
        || die "指定的 AOSP 根目录不存在: $CLI_AOSP_ROOT"
    [ -f "$AOSP_ROOT/build/envsetup.sh" ] \
        || die "不是 AOSP 根目录（缺少 build/envsetup.sh）: $AOSP_ROOT"
else
    AOSP_ROOT="$(resolve_aosp_root)" \
        || die "找不到 AOSP 根目录；可用 --aosp-root=DIR 或 AOSP_ROOT 指定"
fi
info "AOSP: $AOSP_ROOT"

OUT_DIR="${CLI_OUT_DIR:-$SCRIPT_DIR/out}"
MESA_SRC="${MESA_SRC:-$AOSP_ROOT/external/mesa3d}"
LIBDRM_SRC="${LIBDRM_SRC:-$AOSP_ROOT/external/libdrm}"
BUILD_DIR="${BUILD_DIR:-$OUT_DIR/build}"
STAGE_ROOT="${PREFIX:-$OUT_DIR/stage}"
ARTIFACT_ROOT="$OUT_DIR/artifacts"
PREBUILT_DIR="${PREBUILT_DIR:-$SCRIPT_DIR/../../../prebuilts/gpu/mesa}"
MESA_BUILDTYPE="${MESA_BUILDTYPE:-release}"

declare -A CROSS_FILES=()
declare -A API_LEVELS=()
declare -A SYSROOTS=()
NDK_ROOT=""

[ -d "$MESA_SRC" ] || die "Mesa 源码不存在: $MESA_SRC"
[ -d "$LIBDRM_SRC" ] || die "libdrm 源码不存在: $LIBDRM_SRC"
[ -f "$MESA_SRC/VERSION" ] || die "Mesa 源码不完整（缺 VERSION）"

if [ "$CLEAN" -eq 1 ]; then
    info "清理 $OUT_DIR"
    rm -rf "$OUT_DIR"
fi

# ---------------------------------------------------------------------------
# 通用检查
# ---------------------------------------------------------------------------
info "检查构建工具"
command -v python3 >/dev/null 2>&1 || die "缺少 python3"


if [ "$PREPARE_ONLY" -eq 0 ]; then
    command -v meson >/dev/null 2>&1 || die "缺少 meson >= 1.4.0，可执行: pip install meson"
    command -v ninja >/dev/null 2>&1 || die "缺少 ninja，可执行: pip install ninja"
    command -v pkg-config >/dev/null 2>&1 || die "缺少 pkg-config"
    python3 - <<'PY' || die "缺少 Python 构建依赖，可执行: pip install mako pyyaml packaging"
import sys
missing = []
for mod, pkg in (("mako", "mako"), ("yaml", "PyYAML"), ("packaging", "packaging")):
    try:
        __import__(mod)
    except ImportError:
        missing.append(pkg)
if missing:
    print("缺少 Python 模块: " + ", ".join(missing), file=sys.stderr)
    sys.exit(1)
PY
    meson_version="$(meson --version)"
    python3 - "$meson_version" <<'PY' || die "meson 版本过低，Mesa 26.1 需要 >= 1.4.0（当前 $meson_version）"
import sys
cur = tuple(int(x) for x in sys.argv[1].split('.')[:2])
sys.exit(0 if cur >= (1, 4) else 1)
PY
fi

# Mesa 26.1 的 Panfrost 在构建期需要 CLC（LLVM + libclc + SPIRV-LLVM-Translator + SPIRV-Tools）
if [ "$PREPARE_ONLY" -eq 0 ]; then
    if ! command -v llvm-config >/dev/null 2>&1; then
        llvm_cfg="$(compgen -c 2>/dev/null | grep -E '^llvm-config-[0-9]+$' | sort -V | tail -n 1)"
        if [ -n "$llvm_cfg" ]; then
            llvm_cfg="$(command -v "$llvm_cfg")"
            mkdir -p "$BUILD_DIR/bin"
            ln -sf "$llvm_cfg" "$BUILD_DIR/bin/llvm-config"
            export PATH="$BUILD_DIR/bin:$PATH"
            hash -r
        fi
    fi

    clc_missing=""
    for pc in libclc LLVMSPIRVLib SPIRV-Tools libdrm; do
        pkg-config --exists "$pc" || clc_missing="$clc_missing $pc"
    done

    llvm_config_bin="$(command -v llvm-config || true)"
    llvm_version=""
    if [ -n "$llvm_config_bin" ]; then
        llvm_version="$("$llvm_config_bin" --version 2>/dev/null || true)"
    fi

    if [ -z "$llvm_config_bin" ] || [ -z "$llvm_version" ] || [ -n "$clc_missing" ]; then
        cat >&2 <<'EOM'
错误: Mesa 26.1 的 Panfrost 构建期需要 CLC（LLVM 工具链）。
缺少: llvm-config / libclc / LLVMSPIRVLib / SPIRV-Tools 中的一项或多项。

Debian/Ubuntu 可安装一套匹配的 LLVM 19（LLVMSPIRVLib 必须与 llvm-config 主次版本一致）：
  sudo apt-get install llvm llvm-19-dev libclang-19-dev libclang-cpp19-dev \
      libclang-common-19-dev libclc-19-dev libllvmspirvlib-19-dev spirv-tools libdrm-dev

安装后请确认下列命令都有输出：
  llvm-config --version
  pkg-config --modversion libclc LLVMSPIRVLib SPIRV-Tools
EOM
        exit 1
    fi

    spv_version="$(pkg-config --modversion LLVMSPIRVLib 2>/dev/null || true)"
    llvm_mm="$(printf '%s' "$llvm_version" | cut -d. -f1-2)"
    case "$spv_version" in
        "$llvm_mm".*) ;;
        *)
            die "LLVMSPIRVLib $spv_version 与 llvm-config $llvm_version 主次版本不一致；请安装匹配的一套"
            ;;
    esac
    llvm_libdir="$("$llvm_config_bin" --libdir 2>/dev/null || true)"
    if [ -n "$llvm_libdir" ] && [ ! -e "$llvm_libdir/libclang-cpp.so" ] && [ ! -e "$llvm_libdir/libclangBasic.a" ]; then
        die "找不到 clang 库（$llvm_libdir/libclang-cpp.so 或 libclangBasic.a）；请安装 libclang-19-dev、libclang-cpp19-dev、libclang-common-19-dev"
    fi
    export LLVM_CONFIG="$llvm_config_bin"
    info "LLVM: $llvm_version ($llvm_config_bin)"
    info "LLVMSPIRVLib: $spv_version"
fi

# AOSP 中的 Android 平台头文件（两种工具链都需要）
ANDROID_INCLUDES=(
    "$AOSP_ROOT/system/core/libcutils/include"
    "$AOSP_ROOT/system/core/libsystem/include"
    "$AOSP_ROOT/system/core/libsync/include"
    "$AOSP_ROOT/hardware/libhardware/include"
    "$AOSP_ROOT/frameworks/native/libs/nativewindow/include"
    "$AOSP_ROOT/frameworks/native/libs/nativebase/include"
    "$AOSP_ROOT/frameworks/native/libs/arect/include"
    "$AOSP_ROOT/system/logging/liblog/include"
)
for d in "${ANDROID_INCLUDES[@]}"; do
    [ -d "$d" ] || die "缺少 Android 平台头文件目录: $d"
done

mkdir -p "$BUILD_DIR" "$STAGE_ROOT" "$ARTIFACT_ROOT"

# ---------------------------------------------------------------------------
# 准备工具链与交叉文件
# ---------------------------------------------------------------------------
arch_cpu_family() {
    case "$1" in
        arm64) echo "aarch64" ;;
        arm) echo "arm" ;;
        *) die "未知架构: $1" ;;
    esac
}

# AOSP/Soong 的中间产物目录与 Soong arch 名使用 arm64，不是 aarch64
arch_bionic_prefix() {
    case "$1" in
        arm64) echo "arm64" ;;
        arm) echo "arm" ;;
        *) die "未知架构: $1" ;;
    esac
}

arch_cpu_name() {
    case "$1" in
        arm64) echo "armv8" ;;
        arm) echo "armv7" ;;
        *) die "未知架构: $1" ;;
    esac
}

arch_aosp_target() {
    case "$1" in
        arm64) echo "aarch64-linux-android" ;;
        arm) echo "armv7a-linux-androideabi" ;;
        *) die "未知架构: $1" ;;
    esac
}

arch_ndk_target() {
    case "$1" in
        arm64) echo "aarch64-linux-android" ;;
        arm) echo "armv7a-linux-androideabi" ;;
        *) die "未知架构: $1" ;;
    esac
}

arch_sysroot_libdir() {
    case "$1" in
        arm64) echo "aarch64-linux-android" ;;
        arm) echo "arm-linux-androideabi" ;;
        *) die "未知架构: $1" ;;
    esac
}

arch_kernel_asm() {
    case "$1" in
        arm64) echo "asm-arm64" ;;
        arm) echo "asm-arm" ;;
        *) die "未知架构: $1" ;;
    esac
}

arch_libcxx_platform() {
    case "$1" in
        arm64) echo "aarch64" ;;
        arm) echo "arm" ;;
        *) die "未知架构: $1" ;;
    esac
}

write_cross_file_aosp() {
    local arch="$1" out="$2" sysroot="$3" clang_root="$4" api="$5"
    local triple cpu_family cpu
    triple="$(arch_aosp_target "$arch")"
    cpu_family="$(arch_cpu_family "$arch")"
    cpu="$(arch_cpu_name "$arch")"

    python3 - "$out" "$sysroot" "$api" "$triple" "$cpu_family" "$cpu" \
        "$clang_root/bin/clang" "$clang_root/bin/clang++" \
        "$clang_root/bin/llvm-ar" "$clang_root/bin/llvm-strip" \
        "$llvm_config_bin" "${ANDROID_INCLUDES[@]}" <<'PY'
import sys
(out, sysroot, api, triple, cpu_family, cpu, cc, cxx, ar, strip, llvm_config, *includes) = sys.argv[1:]

def q(v):
    return "'" + v.replace("'", "'\\''") + "'"

def arr(values):
    return "[" + ", ".join(q(v) for v in values) + "]"

target = ["--target=" + triple + api, "--sysroot=" + sysroot]
inc = []
for d in includes:
    inc += ["-isystem", d]
common = target + inc

lines = []
lines.append("[binaries]")
lines.append("c = " + q(cc))
lines.append("cpp = " + q(cxx))
lines.append("ar = " + q(ar))
lines.append("strip = " + q(strip))
lines.append("pkg-config = 'pkg-config'")
if llvm_config:
    lines.append("llvm-config = " + q(llvm_config))
lines.append("")
lines.append("[built-in options]")
lines.append("c_args = " + arr(common))
lines.append("cpp_args = " + arr(common + ["-stdlib=libc++", "-isystem", sysroot + "/usr/include/c++/v1"]))
lines.append("c_link_args = " + arr(target))
lines.append("cpp_link_args = " + arr(target + ["-nostdlib++", "-lc++_static", "-lc++abi"]))
lines.append("")
lines.append("[host_machine]")
lines.append("system = 'android'")
lines.append("cpu_family = " + q(cpu_family))
lines.append("cpu = " + q(cpu))
lines.append("endian = 'little'")
lines.append("")
lines.append("[properties]")
lines.append("needs_exe_wrapper = true")
open(out, "w", encoding="utf-8").write("\n".join(lines) + "\n")
PY
    info "交叉文件: $out ($arch)"
}

# 在 .../libc.ndk 之类目录下按 API 选指定架构变体；优先精确 API，其次不超过目标的最高 API
pick_ndk_lib_dir() {
    local base="$1" want="$2" arch="$3" d a prefix
    prefix="$(arch_bionic_prefix "$arch")"
    d="$(ls -d "$base"/android_"$prefix"_*_sdk_shared_"$want" 2>/dev/null | sort | head -n 1)"
    if [ -n "$d" ]; then
        printf '%s\n' "$d"
        return 0
    fi
    for a in $(ls -d "$base"/android_"$prefix"_*_sdk_shared_* 2>/dev/null \
                   | sed 's/.*_sdk_shared_//' | grep -E '^[0-9]+$' | sort -rn -u); do
        [ "$a" -le "$want" ] || continue
        d="$(ls -d "$base"/android_"$prefix"_*_sdk_shared_"$a" 2>/dev/null | sort | head -n 1)"
        [ -n "$d" ] && { printf '%s\n' "$d"; return 0; }
    done
    a="$(ls -d "$base"/android_"$prefix"_*_sdk_shared_* 2>/dev/null \
             | sed 's/.*_sdk_shared_//' | grep -E '^[0-9]+$' | sort -n -u | head -n 1)"
    [ -n "$a" ] || return 1
    ls -d "$base"/android_"$prefix"_*_sdk_shared_"$a" 2>/dev/null | sort | head -n 1
}

# 在 crt 目录下选一个普通指定架构变体，避开 sdk/apex/vendor 等专用副本
pick_plain_arch_dir() {
    local base="$1" arch="$2" d prefix
    prefix="$(arch_bionic_prefix "$arch")"
    for d in $(ls -d "$base"/android_"$prefix"_* 2>/dev/null | sort); do
        case "$(basename "$d")" in
            *_sdk_*|*_apex*|*_ramdisk*|*_recovery*|*_vendor*) continue ;;
        esac
        printf '%s\n' "$d"
        return 0
    done
    ls -d "$base"/android_"$prefix"_* 2>/dev/null | sort | head -n 1
}

prepare_aosp() {
    local arch="$1"
    local base="$AOSP_ROOT/prebuilts/clang/host/linux-x86"
    local platform
    platform="$(arch_libcxx_platform "$arch")"
    local clang_root=""
    local d
    for d in $(ls -d "$base"/clang-r* 2>/dev/null | sort -V -r); do
        if [ -x "$d/bin/clang" ] && [ -f "$d/android_libc++/platform/$platform/lib/libc++_static.a" ]; then
            clang_root="$d"
            break
        fi
    done
    [ -n "$clang_root" ] || die "树内找不到带 $platform libc++ 的 clang（prebuilts/clang/host/linux-x86/clang-r*）"
    info "clang: $clang_root ($arch)"

    local api="${ANDROID_API_LEVEL:-37}"
    local libc_base="$AOSP_ROOT/out/soong/.intermediates/bionic/libc/libc.ndk"
    local libm_base="$AOSP_ROOT/out/soong/.intermediates/bionic/libm/libm.ndk"
    local libdl_base="$AOSP_ROOT/out/soong/.intermediates/bionic/libdl/libdl.ndk"

    if [ ! -d "$libc_base" ] || [ ! -d "$libm_base" ] || [ ! -d "$libdl_base" ]; then
        die "缺少 bionic NDK 产物，请先完成一次 AOSP 构建（或改用 --toolchain=ndk）"
    fi

    local libc_dir libm_dir libdl_dir prefix
    prefix="$(arch_bionic_prefix "$arch")"
    libc_dir="$(pick_ndk_lib_dir "$libc_base" "$api" "$arch")" \
        || die "找不到可用的 $arch bionic libc（$libc_base）"
    api="$(basename "$libc_dir" | sed 's/.*_sdk_shared_//')"
    libm_dir="$(ls -d "$libm_base"/android_"$prefix"_*_sdk_shared_"$api" 2>/dev/null | sort | head -n 1)"
    libdl_dir="$(ls -d "$libdl_base"/android_"$prefix"_*_sdk_shared_"$api" 2>/dev/null | sort | head -n 1)"
    [ -n "$libm_dir" ] || die "找不到 API $api 的 $arch bionic libm（$libm_base）"
    [ -n "$libdl_dir" ] || die "找不到 API $api 的 $arch bionic libdl（$libdl_base）"

    local sysroot="$BUILD_DIR/sysroot-$arch"
    local cross_file="$BUILD_DIR/cross-$arch-android.ini"
    local sysroot_libdir
    sysroot_libdir="$(arch_sysroot_libdir "$arch")"
    local asm_dir
    asm_dir="$(arch_kernel_asm "$arch")"
    local libdir="$sysroot/usr/lib/$sysroot_libdir/$api"
    local incdir="$sysroot/usr/include"
    local crt_so crtend_so crt_dyn crtend_android
    crt_so="$(pick_plain_arch_dir "$AOSP_ROOT/out/soong/.intermediates/bionic/libc/crtbegin_so" "$arch")"
    crtend_so="$(pick_plain_arch_dir "$AOSP_ROOT/out/soong/.intermediates/bionic/libc/crtend_so" "$arch")"
    crt_dyn="$(pick_plain_arch_dir "$AOSP_ROOT/out/soong/.intermediates/bionic/libc/crtbegin_dynamic" "$arch")"
    crtend_android="$(pick_plain_arch_dir "$AOSP_ROOT/out/soong/.intermediates/bionic/libc/crtend_android" "$arch")"

    info "准备 sysroot: $sysroot ($arch, API $api)"
    rm -rf "$sysroot"
    mkdir -p "$incdir/linux" "$libdir" "$sysroot/usr/include/c++"

    # bionic 公共头
    local f
    for f in "$AOSP_ROOT"/bionic/libc/include/*; do
        ln -s "$f" "$incdir/"
    done

    # 内核 uapi：linux 目录需要与 android/uapi 的 compiler.h 合并
    for f in "$AOSP_ROOT"/bionic/libc/kernel/uapi/linux/*; do
        ln -s "$f" "$incdir/linux/"
    done
    ln -s "$AOSP_ROOT/bionic/libc/kernel/android/uapi/linux/compiler.h" "$incdir/linux/compiler.h"
    ln -s "$AOSP_ROOT/bionic/libc/kernel/uapi/asm-generic" "$incdir/asm-generic"
    ln -s "$AOSP_ROOT/bionic/libc/kernel/uapi/$asm_dir/asm" "$incdir/asm"
    local d
    for d in cxl drm fwctl misc; do
        ln -s "$AOSP_ROOT/bionic/libc/kernel/uapi/$d" "$incdir/$d"
    done

    # libc++ 头：树内平台头（clang 会通过 -stdlib=libc++ 自动搜索 sysroot 下的 c++/v1）
    ln -s "$AOSP_ROOT/external/libcxx/include" "$sysroot/usr/include/c++/v1"

    # 链接期运行库与 crt
    for f in libc.so libm.so libdl.so; do
        local dir
        case "$f" in
            libc.so) dir="$libc_dir" ;;
            libm.so) dir="$libm_dir" ;;
            libdl.so) dir="$libdl_dir" ;;
        esac
        [ -f "$dir/$f" ] || die "缺少 $dir/$f"
        ln -s "$dir/$f" "$libdir/$f"
    done
    [ -f "$crt_so/crtbegin_so.o" ] || die "缺少 $crt_so/crtbegin_so.o"
    [ -f "$crtend_so/crtend_so.o" ] || die "缺少 $crtend_so/crtend_so.o"
    [ -f "$crt_dyn/crtbegin_dynamic.o" ] || die "缺少 $crt_dyn/crtbegin_dynamic.o"
    [ -f "$crtend_android/crtend_android.o" ] || die "缺少 $crtend_android/crtend_android.o"
    ln -s "$crt_so/crtbegin_so.o" "$libdir/crtbegin_so.o"
    ln -s "$crtend_so/crtend_so.o" "$libdir/crtend_so.o"
    ln -s "$crt_dyn/crtbegin_dynamic.o" "$libdir/crtbegin_dynamic.o"
    ln -s "$crtend_android/crtend_android.o" "$libdir/crtend_android.o"

    local cxx_lib="$clang_root/android_libc++/platform/$platform/lib"
    [ -f "$cxx_lib/libc++_static.a" ] || die "缺少 $cxx_lib/libc++_static.a"
    [ -f "$cxx_lib/libc++abi.a" ] || die "缺少 $cxx_lib/libc++abi.a"
    ln -s "$cxx_lib/libc++_static.a" "$libdir/libc++_static.a"
    ln -s "$cxx_lib/libc++abi.a" "$libdir/libc++abi.a"

    write_cross_file_aosp "$arch" "$cross_file" "$sysroot" "$clang_root" "$api"
    CROSS_FILES[$arch]="$cross_file"
    API_LEVELS[$arch]="$api"
    SYSROOTS[$arch]="$sysroot"
}

prepare_ndk() {
    local arch="$1"
    local api="${ANDROID_API_LEVEL:-35}"
    local ndk="${ANDROID_NDK_ROOT:-${ANDROID_NDK_HOME:-}}"
    [ -n "$ndk" ] || die "ndk 模式需要 ANDROID_NDK_ROOT 或 ANDROID_NDK_HOME"
    local tc="$ndk/toolchains/llvm/prebuilt/linux-x86_64"
    [ -d "$tc/sysroot" ] || die "NDK 不完整: $ndk 缺少 toolchains/llvm/prebuilt/linux-x86_64/sysroot"
    local triple cpu_family cpu
    triple="$(arch_ndk_target "$arch")"
    cpu_family="$(arch_cpu_family "$arch")"
    cpu="$(arch_cpu_name "$arch")"
    local cc="$tc/bin/${triple}${api}-clang"
    local cxx="$tc/bin/${triple}${api}-clang++"
    [ -x "$cc" ] || die "NDK 缺少 $cc（请检查 ANDROID_API_LEVEL=$api）"
    [ -x "$cxx" ] || die "NDK 缺少 $cxx"
    [ -x "$tc/bin/llvm-ar" ] || die "NDK 缺少 llvm-ar"
    [ -x "$tc/bin/llvm-strip" ] || die "NDK 缺少 llvm-strip"

    local cross_file="$BUILD_DIR/cross-$arch-android.ini"
    python3 - "$cross_file" "$api" "$cpu_family" "$cpu" "$cc" "$cxx" \
        "$tc/bin/llvm-ar" "$tc/bin/llvm-strip" \
        "$llvm_config_bin" "${ANDROID_INCLUDES[@]}" <<'PY'
import sys
(out, api, cpu_family, cpu, cc, cxx, ar, strip, llvm_config, *includes) = sys.argv[1:]

def q(v):
    return "'" + v.replace("'", "'\\''") + "'"

def arr(values):
    return "[" + ", ".join(q(v) for v in values) + "]"

inc = []
for d in includes:
    inc += ["-isystem", d]
lines = [
    "[binaries]",
    "c = " + q(cc),
    "cpp = " + q(cxx),
    "ar = " + q(ar),
    "strip = " + q(strip),
    "pkg-config = 'pkg-config'",
    "",
    "[built-in options]",
    "c_args = " + arr(inc),
    "cpp_args = " + arr(inc),
    "",
    "[host_machine]",
    "system = 'android'",
    "cpu_family = " + q(cpu_family),
    "cpu = " + q(cpu),
    "endian = 'little'",
    "",
    "[properties]",
    "needs_exe_wrapper = true",
]
if llvm_config:
    lines.insert(6, "llvm-config = " + q(llvm_config))
open(out, "w", encoding="utf-8").write("\n".join(lines) + "\n")
PY
    CROSS_FILES[$arch]="$cross_file"
    API_LEVELS[$arch]="$api"
    SYSROOTS[$arch]="$tc/sysroot"
    NDK_ROOT="$ndk"
    info "NDK: $ndk ($arch, API $api)"
    info "交叉文件: $cross_file"
}

if [ -z "${llvm_config_bin:-}" ]; then
    llvm_config_bin="$(command -v llvm-config || true)"
fi

if [ "$TOOLCHAIN_MODE" = "aosp" ]; then
    for arch in "${ARCH_LIST[@]}"; do
        prepare_aosp "$arch"
    done
else
    for arch in "${ARCH_LIST[@]}"; do
        prepare_ndk "$arch"
    done
fi

if [ "$PREPARE_ONLY" -eq 1 ]; then
    info "--prepare-only：已生成 sysroot 与交叉文件，未调用 meson"
    for arch in "${ARCH_LIST[@]}"; do
        info "  $arch: ${CROSS_FILES[$arch]}"
    done
    exit 0
fi

# ---------------------------------------------------------------------------
# Host 侧编译器：mesa_clc / vtn_bindgen2 / panfrost_compile
# Mesa 的交叉构建不会用目标编译器去找 host 的 libclang-cpp，必须先用宿主
# 编译器把这三个工具编出来，再让交叉构建以 system 模式调用。
# ---------------------------------------------------------------------------
HOST_TOOLS_DIR="$OUT_DIR/host-tools"
HOST_TOOLS_BIN="$HOST_TOOLS_DIR/bin"
HOST_BUILD_DIR="$BUILD_DIR/host-mesa"
if [ ! -x "$HOST_TOOLS_BIN/mesa_clc" ] || \
   [ ! -x "$HOST_TOOLS_BIN/vtn_bindgen2" ] || \
   [ ! -x "$HOST_TOOLS_BIN/panfrost_compile" ]; then
    info "构建 host 侧 Mesa 工具 -> $HOST_TOOLS_DIR"
    HOST_SETUP_ARGS=()
    [ -d "$HOST_BUILD_DIR" ] && HOST_SETUP_ARGS+=(--wipe)
    env -u PKG_CONFIG_PATH -u PKG_CONFIG_LIBDIR -u PKG_CONFIG_SYSROOT_DIR \
        meson setup "$HOST_BUILD_DIR" "$MESA_SRC" \
        --prefix "$HOST_TOOLS_DIR" \
        --buildtype release \
        "${HOST_SETUP_ARGS[@]}" \
        -Dplatforms= \
        -Dgallium-drivers= \
        -Dvulkan-drivers= \
        -Dglx=disabled \
        -Dgbm=disabled \
        -Dopengl=false \
        -Dgles1=disabled \
        -Dgles2=disabled \
        -Dxmlconfig=disabled \
        -Dexpat=disabled \
        -Dzlib=disabled \
        -Dzstd=disabled \
        -Dshader-cache=disabled \
        -Dvalgrind=disabled \
        -Dbuild-tests=false \
        -Dllvm=enabled \
        -Dmesa-clc=enabled \
        -Dinstall-mesa-clc=true \
        -Dtools=panfrost \
        -Dinstall-precomp-compiler=true
    meson install -C "$HOST_BUILD_DIR"
fi
export PATH="$HOST_TOOLS_BIN:$PATH"

# ---------------------------------------------------------------------------
# 第一步/第二步：逐架构构建 libdrm + Mesa
# ---------------------------------------------------------------------------
for arch in "${ARCH_LIST[@]}"; do
    cross_file="${CROSS_FILES[$arch]}"
    stage="$STAGE_ROOT/$arch"
    api="${API_LEVELS[$arch]}"
    libdrm_build="$BUILD_DIR/libdrm-$arch"
    mesa_build="$BUILD_DIR/mesa-$arch"
    artifact="$ARTIFACT_ROOT/$arch"

    # 交叉构建只暴露本架构 libdrm 的 .pc，避免宿主 SPIRV-Tools / libelf / libudev 等被误用；
    # LLVM 相关依赖只由前面的 host 工具构建使用，host 构建里会显式清空这些变量。
    export PKG_CONFIG_LIBDIR="$stage/lib/pkgconfig:$stage/lib64/pkgconfig:$stage/share/pkgconfig"
    unset PKG_CONFIG_PATH || true
    unset PKG_CONFIG_SYSROOT_DIR || true

    mkdir -p "$stage" "$artifact"
    rm -rf "$artifact"/*
    rm -rf "$stage"/*

    info "构建 libdrm ($arch) -> $stage"
    LIBDRM_SETUP_ARGS=()
    [ -d "$libdrm_build" ] && LIBDRM_SETUP_ARGS+=(--wipe)
    meson setup "$libdrm_build" "$LIBDRM_SRC" \
        --cross-file "$cross_file" \
        --prefix "$stage" \
        --buildtype release \
        "${LIBDRM_SETUP_ARGS[@]}" \
        -Dtests=false \
        -Dman-pages=disabled \
        -Dvalgrind=disabled \
        -Dudev=false \
        -Dlibkms=false \
        -Dcairo-tests=disabled \
        -Dintel=disabled \
        -Dradeon=disabled \
        -Damdgpu=disabled \
        -Dnouveau=disabled \
        -Dvmwgfx=disabled \
        -Dvc4=disabled \
        -Dfreedreno=disabled \
        -Detnaviv=disabled
    meson install -C "$libdrm_build"

    info "构建 Mesa ($arch, panfrost / GLES) -> $stage"
    MESA_SETUP_ARGS=()
    [ -d "$mesa_build" ] && MESA_SETUP_ARGS+=(--wipe)
    meson setup "$mesa_build" "$MESA_SRC" \
        --cross-file "$cross_file" \
        --prefix "$stage" \
        --buildtype "$MESA_BUILDTYPE" \
        "${MESA_SETUP_ARGS[@]}" \
        -Dplatforms=android \
        -Dplatform-sdk-version="$api" \
        -Dandroid-stub=true \
        -Degl-native-platform=android \
        -Dgallium-drivers=panfrost \
        -Dvulkan-drivers=panfrost \
        -Dvideo-codecs= \
        -Dgallium-rusticl=false \
        -Dmicrosoft-clc=disabled \
        -Dmesa-clc=system \
        -Dprecomp-compiler=system \
        -Dglx=disabled \
        -Dgbm=disabled \
        -Dopengl=false \
        -Dgles1=enabled \
        -Dgles2=enabled \
        -Dxmlconfig=disabled \
        -Dexpat=disabled \
        -Dllvm=disabled \
        -Dspirv-tools=disabled \
        -Dvalgrind=disabled \
        -Dandroid-libbacktrace=disabled \
        -Dzlib=disabled \
        -Dzstd=disabled \
        -Dshader-cache=disabled \
        -Dtools= \
        -Dbuild-tests=false \
        -Degl-lib-suffix=_mesa \
        -Dgles-lib-suffix=_mesa \
        -Dstrip=false
    meson install -C "$mesa_build"

    # 收集五个产物（GLES 四个 + PanVK 一个）
    info "收集 $arch 产物 -> $artifact"
    for name in libEGL_mesa.so libGLESv1_CM_mesa.so libGLESv2_mesa.so libgallium_dri.so libvulkan_panfrost.so; do
        found="$(find "$stage" \( -name "$name" -type f -o -name "$name" -type l \) | head -n 1)"
        [ -n "$found" ] || die "构建完成但找不到 $name（$arch），请检查 Meson 安装路径"
        cp -L "$found" "$artifact/$name"
    done

    # 记录本架构的可复现信息
    {
        echo "arch=$arch"
        echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "toolchain=$TOOLCHAIN_MODE"
        echo "api_level=$api"
        echo "mesa_src=$MESA_SRC"
        echo "mesa_version=$(cat "$MESA_SRC/VERSION")"
        echo "mesa_commit=$(git -C "$MESA_SRC" rev-parse HEAD 2>/dev/null || echo unknown)"
        echo "vulkan_drivers=panfrost"
        echo "libdrm_src=$LIBDRM_SRC"
        echo "libdrm_commit=$(git -C "$LIBDRM_SRC" rev-parse HEAD 2>/dev/null || echo unknown)"
        echo "meson_version=$(meson --version)"
        echo "ninja_version=$(ninja --version)"
        echo "ndk_root=${NDK_ROOT:-<none>}"
        echo "buildtype=$MESA_BUILDTYPE"
        echo "--- cross file ---"
        sed 's/^/  /' "$cross_file"
    } > "$artifact/build-info.txt"

    ( cd "$artifact" && sha256sum ./*.so > SHA256SUMS )
done

if [ "$INSTALL" -eq 1 ]; then
    # 安装会生成同时引用 arm64 与 arm 的 Android.bp，缺任一架构都会让 Soong 构建失败。
    for arch in arm64 arm; do
        [ -d "$ARTIFACT_ROOT/$arch" ] || die "--install 需要同时存在 arm64 与 arm 产物；当前缺少 $ARTIFACT_ROOT/$arch"
        ls "$ARTIFACT_ROOT/$arch"/*.so >/dev/null 2>&1 \
            || die "--install 需要 $ARTIFACT_ROOT/$arch 下有 .so 产物"
    done
    [ -d "$PREBUILT_DIR" ] || mkdir -p "$PREBUILT_DIR"
    for arch in "${ARCH_LIST[@]}"; do
        mkdir -p "$PREBUILT_DIR/$arch"
        cp -f "$ARTIFACT_ROOT/$arch"/*.so "$PREBUILT_DIR/$arch"/
        cp -f "$ARTIFACT_ROOT/$arch/build-info.txt" "$PREBUILT_DIR/$arch/build-info.txt"
    done
    cp -f "$SCRIPT_DIR/Android.bp.template" "$PREBUILT_DIR/Android.bp"

    # 清理旧版扁平布局，避免同一份库既在顶层又在 <arch>/ 下。
    for name in libEGL_mesa.so libGLESv1_CM_mesa.so libGLESv2_mesa.so libgallium_dri.so libvulkan_panfrost.so; do
        rm -f "$PREBUILT_DIR/$name"
    done

    # 顶层 build-info 汇总所有已安装架构
    : > "$PREBUILT_DIR/build-info.txt"
    for arch in arm64 arm; do
        [ -f "$PREBUILT_DIR/$arch/build-info.txt" ] || continue
        {
            echo "=== $arch ==="
            cat "$PREBUILT_DIR/$arch/build-info.txt"
            echo
        } >> "$PREBUILT_DIR/build-info.txt"
    done

    # 顶层哈希覆盖所有已安装架构
    (
        cd "$PREBUILT_DIR"
        : > SHA256SUMS
        for arch in arm64 arm; do
            [ -d "$arch" ] || continue
            for f in "$arch"/*.so; do
                [ -e "$f" ] || continue
                sha256sum "$f" >> SHA256SUMS
            done
        done
    )
    info "已安装预编译库 -> $PREBUILT_DIR"
fi

info "完成。产物："
for arch in "${ARCH_LIST[@]}"; do
    echo "--- $arch"
    ls -l "$ARTIFACT_ROOT/$arch"
done
echo
if [ "$INSTALL" -eq 1 ]; then
    info "下一步：构建并刷写 vendorimage，确认 /vendor/lib/egl 与 /vendor/lib64/egl 都存在对应 Mesa 库"
else
    info "下一步：检查 NEEDED 后执行 ./build.sh --install，安装到 $PREBUILT_DIR"
fi

