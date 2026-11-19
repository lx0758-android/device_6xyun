# GPU 用户态：Mesa Panfrost 出树构建

本目录只做一件事：用 Meson 交叉编译出设备可用的 Panfrost GLES 库（arm64 + arm），并记录可复现的版本与哈希。

- 默认使用 AOSP 树内工具链，不需要额外安装 NDK；
- 源码只读引用树内 `external/mesa3d` 与 `external/libdrm`，不修改、不复制；
- 产物以预编译库形式交付，由 `vendor/6xyun/prebuilts/gpu/mesa/` 下的 Soong 模块安装到镜像。

> 必须同时构建 arm64 与 arm。产品继承 `core_64_bit.mk` 后会启动 `zygote64_32`，32 位 `app_process32` 在预加载 EGL 时只搜索 `/vendor/lib/egl`；缺少 arm 产物会直接以 `couldn't find an OpenGL ES implementation` abort。

## 为什么出树构建

`external/mesa3d` 的 Soong 文件由 meson2hermetic 生成，只覆盖 gfxstream/virtgpu、llvmpipe/lavapipe 等目标，没有 gallium panfrost，也没有 `libEGL_mesa` / `libGLESv2_mesa` / `libgallium_dri`。

Soong 的 `srcs` / `local_include_dirs` 不允许跨包引用（`build/soong/android/paths.go` 拒绝 `..`），因此不能「在 vendor 里建模块、源码指向 external/mesa3d」。修改上游 Soong 文件又违反本项目的修改范围约束。

结论：出树 Meson 构建 + vendor 内预编译交付。Mesa 上游提供的 `src/android_stub` 正是为「平台库不全」的出树构建准备的。

## 工具链：树内 AOSP（默认）

`build.sh` 默认用树里已有的东西拼出等价于 NDK 的交叉环境：

| 组成 | 来源 |
|---|---|
| 编译器 | `prebuilts/clang/host/linux-x86/clang-r*/bin/clang{++}`（自动选最新且带 `android_libc++` 的） |
| bionic 头 | `bionic/libc/include`、`bionic/libc/kernel/uapi`、`bionic/libc/kernel/android/uapi` |
| Android 平台头 | `system/core/libcutils/include`、`libsystem`、`libsync`、`hardware/libhardware/include`、`frameworks/native/libs/{nativewindow,nativebase,arect}/include`、`system/logging/liblog/include` |
| libc/libm/libdl | `out/soong/.intermediates/bionic/*/*.ndk/android_{arm64,arm}_*_sdk_shared_<API>`（按 glob 自动选变体） |
| crt | `out/soong/.intermediates/bionic/libc/{crtbegin_so,crtend_so,crtbegin_dynamic,crtend_android}/android_{arm64,arm}_*` |
| libc++ | `prebuilts/clang/.../android_libc++/platform/{aarch64,arm}/lib/libc++_static.a` + `libc++abi.a`，头来自 `external/libcxx/include` |

因此前提是**已经完成过一次 AOSP 构建**，`out/soong/.intermediates/bionic` 下有 arm64 与 arm 产物。脚本会把这些内容软链到 `<OUT_DIR>/build/sysroot-<arch>`，每次构建前重建，不改动源码树。

脚本不限制调用目录：AOSP 根目录按 `AOSP_ROOT` / `ANDROID_BUILD_TOP` / `ANDROID_PRODUCT_OUT` / 当前目录 / 脚本所在目录 依次自动定位，也可以用 `--aosp-root=DIR` 显式指定；输出默认在脚本目录的 `out/`，可用 `OUT_DIR` 或 `--out-dir=DIR` 改到任意位置。

如果确实有完整 NDK，也可以显式切过去：

```bash
ANDROID_NDK_ROOT=/path/to/ndk ./build.sh --toolchain=ndk
```

## 前置条件

| 依赖 | 说明 |
|---|---|
| `meson` >= 1.4.0 | Mesa 26.1 的下限 |
| `ninja` | Meson 后端 |
| `pkg-config` | 用于找到本次构建的 libdrm |
| Python >= 3.10 + `mako`、`PyYAML`、`packaging` | Mesa 构建脚本依赖 |
| LLVM + libclc + LLVMSPIRVLib + SPIRV-Tools | Mesa 26.1 的 Panfrost 构建期需要 CLC 预编译 OpenCL 着色器 |

```bash
pip install meson ninja mako pyyaml packaging
```

Debian/Ubuntu 的 LLVM 一套（`LLVMSPIRVLib` 必须与 `llvm-config` 主次版本一致）：

```bash
sudo apt-get install llvm llvm-19-dev libclang-19-dev libclang-cpp19-dev \
    libclang-common-19-dev libclc-19-dev libllvmspirvlib-19-dev spirv-tools libdrm-dev
```

Mesa 的交叉构建不能把宿主的 `libclang-cpp.so` 当作目标架构库来链接（目标链接器会拒绝 x86_64 ELF）。因此脚本先用宿主编译器把 `mesa_clc`、`vtn_bindgen2`、`panfrost_compile` 构建到 `out/host-tools/`，再让交叉构建以 `-Dmesa-clc=system -Dprecomp-compiler=system` 调用它们；交叉侧因此可以保持 `-Dllvm=disabled`，并用 `-Dspirv-tools=disabled` 避免把宿主 SPIRV-Tools 头文件带进目标编译。交叉构建的 `PKG_CONFIG_LIBDIR` 只指向本次 libdrm 的 prefix，宿主 `.pc` 不会泄漏进来。

`build.sh` 会在配置 Mesa 前检查 `llvm-config` 与 `libclc` / `LLVMSPIRVLib` / `SPIRV-Tools`，缺任何一项都会直接给出安装提示，不会先编完 libdrm 再失败。

## 使用

```bash
# 默认：树内工具链，API 37
./build.sh

# 从任意目录调用，输出放到指定位置
/path/to/build.sh --aosp-root=/path/to/aosp --out-dir=/tmp/mesa-out

# 覆盖 API 级别（可用值由 out/soong 下的 bionic NDK 库决定）
ANDROID_API_LEVEL=35 ./build.sh

# 只准备 sysroot 与交叉文件，不调用 meson（用于排查工具链）
./build.sh --prepare-only

# 只重建某一个架构（调试用；正式交付需要两个架构）
ARCHES=arm ./build.sh

# 清理后重来
./build.sh --clean
```

构建按架构循环，每个架构做两步：

1. 用该架构的交叉文件把 `external/libdrm` 装到 `out/stage/<arch>/`；
2. 用该 prefix 的 pkg-config 构建 `external/mesa3d`，装到同一个 prefix。

Mesa 侧关闭了 zlib/zstd/shader-cache/libbacktrace，避免拉取外部 wrap 和引入额外的平台头；`android-stub=true` 会把 cutils/hardware/log/nativewindow/sync 以 stub 形式链接，运行时使用系统真实库。

## 编完之后怎么交付

```bash
./build.sh --install
```

`--install` 会先完成两个架构的构建，然后把每个架构的五个库复制到 `vendor/6xyun/prebuilts/gpu/mesa/<arch>/`，并一起生成：

| 文件 | 作用 |
|---|---|
| `arm64/libEGL_mesa.so`、`arm64/libGLESv1_CM_mesa.so`、`arm64/libGLESv2_mesa.so` | 由 Soong 模块装到 `/vendor/lib64/egl/` |
| `arm64/libgallium_dri.so` | 由 Soong 模块装到 `/vendor/lib64/` |
| `arm64/libvulkan_panfrost.so` | 由 Soong 模块按模块名装成 `/vendor/lib64/hw/vulkan.panfrost.so` |
| `arm/libEGL_mesa.so`、`arm/libGLESv1_CM_mesa.so`、`arm/libGLESv2_mesa.so` | 由 Soong 模块装到 `/vendor/lib/egl/` |
| `arm/libgallium_dri.so` | 由 Soong 模块装到 `/vendor/lib/` |
| `arm/libvulkan_panfrost.so` | 由 Soong 模块按模块名装成 `/vendor/lib/hw/vulkan.panfrost.so` |
| `Android.bp` | 由 `Android.bp.template` 生成，定义五个 `cc_prebuilt_library_shared`，每个都声明 `arm64` 与 `arm` |
| `SHA256SUMS`、`build-info.txt` | 两个架构的产物哈希与可复现信息 |

预编译目录只放上面这些内容，不要手工替换 `.so`，也不要手改生成后的 `Android.bp`。

注意：`Android.bp` 是由 `--install` 从模板重新生成的。在重新跑 `--install`、产出 `libvulkan_panfrost.so` 之前，不要先构建 `vendorimage`，否则 `PRODUCT_PACKAGES` 里的 `vulkan.panfrost` 会因模块/源文件缺失而失败。

接入产品配置（task 2.6 / 2.12）的现状是：

1. `device/6xyun/orangepi_3b/ProductConfig.mk` 的 `PRODUCT_PACKAGES` 已包含 `libEGL_mesa`、`libGLESv1_CM_mesa`、`libGLESv2_mesa`、`libgallium_dri` 与 `vulkan.panfrost`、`vulkan.pastel`；
2. 同一文件通过 `PRODUCT_EGL_TYPE`（默认 `mesa`）与 `PRODUCT_VULKAN_TYPE`（默认 `panfrost`）生成 `ro.hardware.egl` / `ro.hardware.vulkan`；
3. `device/6xyun/orangepi_3b/sepolicy/file_contexts` 已把 `libgallium_dri.so`、`gralloc.minigbm.so`、`mapper.minigbm.so`、`libminigbm_gralloc.so` 与 `vulkan.{panfrost,pastel}.so` 标为 `same_process_hal_file`；
4. 重新构建 `vendorimage`，启动后确认无 avc，并确认 `/vendor/lib/egl` 与 `/vendor/lib64/egl` 都存在对应库，`/vendor/lib64/hw/vulkan.panfrost.so` 存在。

## 产物

`out/artifacts/<arch>/` 下各应出现五个库：

| 文件 | 安装位置（由 Soong 模块决定） |
|---|---|
| `libEGL_mesa.so` | `/vendor/lib64/egl/`、`/vendor/lib/egl/` |
| `libGLESv1_CM_mesa.so` | `/vendor/lib64/egl/`、`/vendor/lib/egl/` |
| `libGLESv2_mesa.so` | `/vendor/lib64/egl/`、`/vendor/lib/egl/` |
| `libgallium_dri.so` | `/vendor/lib64/`、`/vendor/lib/` |
| `libvulkan_panfrost.so` | `/vendor/lib64/hw/vulkan.panfrost.so`、`/vendor/lib/hw/vulkan.panfrost.so` |

Mesa 26.1 的 `libglapi` 是静态库，不再单独交付；`libGLES_mesa` 是旧别名，不需要。

32 位构建同样覆盖 PanVK：`vulkan.panfrost.so` 会同时安装到 `/vendor/lib/hw/`，32 位 Vulkan 应用在 `ro.hardware.vulkan=panfrost` 时使用 Mesa PanVK；回退时两个架构都使用 `pastel`。

### PanVK 在 Bifrost 上的使能开关

Mesa 26.1 的 `panvk_physical_device_init()` 对 arch 6/7 增加了“未充分测试”闸门：没有 `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER` 时返回 `VK_ERROR_INCOMPATIBLE_DRIVER`，设备被当作不兼容设备跳过，`cmd gpu vkjson` 会得到空的 `devices`（instance 与扩展枚举仍正常，不要误判为 dlopen 失败）。G52 属于 arch 7。

Android 上 Mesa 的 `os_get_option()` 在环境变量缺失时回落到属性：变量名转小写、`_` 换成 `.`、加 `debug.` 前缀，所以对应属性是：

```text
debug.mesa.pan.i.want.a.broken.vulkan.driver=1
```

该属性由 `device/6xyun/orangepi_3b/ProductConfig.mk` 始终注入，不改动 `external/mesa3d`；`vulkan.panfrost.so` 与 `vulkan.pastel.so` 都会装进镜像，设备上改 `ro.hardware.vulkan` 重启即可切换。临时验证可以直接在设备上 `setprop`，`os_get_option()` 每次都实时读取属性，不需要重启。

同时生成：

- `out/artifacts/<arch>/SHA256SUMS`：该架构五个产物的哈希；
- `out/artifacts/<arch>/build-info.txt`：该架构的 Mesa/libdrm 实际 commit、Meson/Ninja/工具链/API 版本、交叉文件内容；
- 安装到预编译目录后，顶层 `SHA256SUMS` 与 `build-info.txt` 汇总所有已安装架构。

## Vulkan 冒烟测试（panvk_smoke）

`panvk_smoke/` 是随本目录交付的最小 Vulkan 1.0 用例，用于 PanVK 验收，不参与 Mesa 出树构建（`build.sh` 不编译它），由平台构建按 `PRODUCT_PACKAGES` 编译。

- 源码：`panvk_smoke/panvk_smoke.cpp`；Soong 模块 `panvk_smoke`（`vendor: true`），安装到 `/vendor/bin/panvk_smoke`；
- 流程：创建 instance/device → 64×64 `R8G8B8A8_UNORM` 图像 → `vkCmdClearColorImage` → 屏障切 `TRANSFER_SRC` → `vkCmdCopyImageToBuffer` → fence 等待 → 回读校验红/绿/混合三种颜色；
- clear/copy 在 PanVK 内部走运行时 meta 着色器，所以该用例会经过 Bifrost 着色器编译与 GPU 提交，而不只是枚举设备；
- 只按 Vulkan 1.0 编写，不启用设备扩展。HWUI 的 `skiavk` 要求物理设备 `apiVersion >= 1.1`，G52 的 PanVK 只报 1.0，不能用 `debug.hwui.renderer=skiavk` 验收；
- 用法（root）：

  ```bash
  panvk_smoke
  ```

  输出 `RESULT: PASS` 且退出码 0 表示通过；同一用例也可对 `pastel` 运行，作为回退对照。

## 约束

- 不允许手工替换 `.so`；升级 Mesa/libdrm 后必须重跑本脚本并更新哈希；
- `readelf -d` 只允许依赖 bionic、libdrm、libnativewindow、libsync 等平台库与自身；出现平台不存在的库时回到构建参数修正，不得在设备上补库绕过；
- C++ 运行时静态链接，避免额外交付 `libc++_shared.so`；
- 产物先留在 `out/artifacts/<arch>/`，由 `2.5` 再复制到 `vendor/6xyun/prebuilts/gpu/mesa/<arch>/`，两边不要手工同步。
