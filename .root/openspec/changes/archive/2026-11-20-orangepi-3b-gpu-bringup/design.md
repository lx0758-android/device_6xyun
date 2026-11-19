# Design

## Context

见 proposal.md - Why。当前可核实的状态：

- 图形：设备树 `&gpu`（`rockchip,rk3568-mali` / `arm,mali-bifrost`）已 `okay`，`mali-supply`、`gpu_opp_table`（200–800 MHz）与 GPU 电源域已就绪；内核没有任何 GPU 驱动模块，`/dev/dri/renderD*` 不存在。
- 内核配置：上一次 GKI 构建的 `.config` 已确认 `IOMMU_IO_PGTABLE_LPAE=y`、`DRM_GEM_SHMEM_HELPER=y`、`DEVFREQ_GOV_SIMPLE_ONDEMAND=y`、`WANT_DEV_COREDUMP=y`，`DRM_SCHED` 未设置。因此 GPU 侧只需要 `CONFIG_DRM_PANFROST=m`；`DRM_SCHED` 会由 panfrost 选为模块，产物是 `gpu-sched.ko`。
- 用户态：产品属性为 `ro.hardware.egl=angle`、`ro.hardware.vulkan=pastel`、`ro.opengles.version=196608`，界面由 ANGLE + SwiftShader 纯 CPU 渲染。
- Mesa：树内 `external/mesa3d` 为 26.1.0-devel（当前 commit `875160e`，2026-03-24）。上游文档确认 Mali-G52 的 Panfrost GLES 3.1 是 conformant；PanVK 只有 G610 conformant，G52 为 Vulkan 1.0 且非 conformant。

约束：

- 内核是 6.18.32 + AOSP 补丁的 mixed build，板级只能加模块，bool 选项要动 `gki_defconfig`；
- 不引入闭源 GPU 驱动；
- 所有能力必须有可回退路径，不允许"设个属性假装支持"；
- 不修改 `external/mesa3d`：图形库以出树交叉编译的预编译产物交付，构建脚本与来源记录放在 `vendor/6xyun`。

## Goals / Non-Goals

**Goals:**

- GPU 提供可用的 GLES 硬件渲染，界面退出纯 CPU 渲染；同时交付 Mesa PanVK 硬件 Vulkan 实现，并在通过 Vulkan 1.0 冒烟用例后设为默认。
- 图形库以预编译形式交付，但版本、构建参数、工具链与产物哈希可追溯、可重建。

**Non-Goals:**

- 不做 AFBC 压缩与带宽优化（列为后续变更）；
- 不引入 Vulkan 强制路径，不要求界面跑在 Vulkan 上；
- 不改动音频、相机与视频编解码栈。

## Decisions

### D1：GPU 采用 Mesa Panfrost，不采用闭源 libmali

- 闭源 `libmali` 依赖 ARM kbase 内核驱动 `/dev/mali0`，主线与 GKI 均无此驱动（`drivers/gpu/arm` 不存在），Rockchip 的 kbase 面向其 5.10 BSP；
- 采用闭源等于把内核退回 BSP 分支，推翻现有 `kernel-6.18` mixed build 与 KMI 体系；
- Panfrost 在 6.18 树内，G52（Bifrost v7）为受支持型号；上游文档明确 G52 的 GLES 3.1 为 conformant。

备选与取舍：

- kbase + libmali：性能上限更高，但与主线内核不兼容，维护成本不可控，拒绝；
- 继续 SwiftShader：零成本，但 CPU 占用与功耗不可接受，只能作为回退。

### D2：Mesa Panfrost 以出树 meson 构建、vendor 内交付预编译库

事实约束：

- `external/mesa3d` 的 Soong 文件由 meson2hermetic 生成，当前只包含 gfxstream/virtgpu、部分 gallium 辅助库、llvmpipe/lavapipe 与 Vulkan runtime，没有 gallium panfrost，也没有 `libEGL_mesa`/`libGLESv2_mesa`/`libgallium_dri`；
- Soong 的 `srcs` / `local_include_dirs` 不允许越出模块所在包（`build/soong/android/paths.go` 直接拒绝 `..`），所以"vendor 里建工程、源码只读引用 `external/mesa3d`"不可行；`include_dirs` 虽可跨包，但解决不了源文件；
- 修改 `external/mesa3d` 违反本项目"不轻易改上游"的约束；
- Mesa 上游为出树 Android 构建提供了 `src/android_stub`，README 明确说明它是为"NDK 平台库不全"的出树构建准备的。

方案：**出树 meson 交叉编译 + vendor 内预编译交付**。

- 构建工程放 `vendor/6xyun/hardware/gpu/mesa/`：交叉文件、`build.sh`、版本与哈希记录；
- 源码只读引用树内 `external/mesa3d` 与 `external/libdrm`，不复制、不修改；
- 先用同一份交叉文件把 libdrm 编到临时 sysroot，再构建 Mesa；arm64 与 arm 各用独立 sysroot/prefix，libdrm 与 Mesa 逐架构构建；
- Mesa 关键参数：`-Dplatforms=android -Degl-native-platform=android -Dandroid-stub=true -Dplatform-sdk-version=<API> -Dgallium-drivers=panfrost -Dvulkan-drivers=panfrost -Dglx=disabled -Dgbm=disabled -Dopengl=false -Dgles1=enabled -Dgles2=enabled -Dxmlconfig=disabled -Dexpat=disabled -Dllvm=disabled -Dmesa-clc=system -Dprecomp-compiler=system -Dspirv-tools=disabled -Dvalgrind=disabled -Dzstd=disabled -Dtools= -Dbuild-tests=false -Degl-lib-suffix=_mesa -Dgles-lib-suffix=_mesa`；
- `-Dplatforms=android` 会让 `libgallium_dri` 自动去掉版本号，不需要额外的 `unversion-libgallium`；
- Mesa 26.1 的 Panfrost 在构建期需要 CLC：`src/panfrost/libpan` 会把 `.cl` 预编译成 SPIR-V，因此必须有可用的 LLVM、`libclc`、`LLVMSPIRVLib` 与 `SPIRV-Tools`；`LLVMSPIRVLib` 的主次版本必须与 `llvm-config` 一致，本机 Debian 用 LLVM 19 一套；
- CLC 相关工具必须用**宿主编译器**构建：Mesa 交叉构建里的 `dep_clang` 走目标 C++ 编译器，无法链接宿主 x86_64 的 `libclang-cpp`。因此 `build.sh` 先在 `out/host-tools/` 生成 `mesa_clc`、`vtn_bindgen2`、`panfrost_compile`，交叉构建再用 `-Dmesa-clc=system -Dprecomp-compiler=system -Dllvm=disabled`；
- 产物每个架构五个：`libEGL_mesa.so`、`libGLESv1_CM_mesa.so`、`libGLESv2_mesa.so`、`libgallium_dri.so`、`libvulkan_panfrost.so`（安装时改名为 `vulkan.panfrost.so`）。Mesa 26.1 的 `libglapi` 是静态库，不再单独交付；`libGLES_mesa` 是旧别名，不需要；
- 必须同时交付 arm64 与 arm：产品继承 `core_64_bit.mk`，`ro.zygote=zygote64_32` 会启动 32 位 `app_process32`；`frameworks/native/opengl/libs/EGL/Loader.cpp` 在 32 位进程里只搜索 `/vendor/lib/egl`，缺少 arm 产物会以 “couldn't find an OpenGL ES implementation” abort；
- 前三个按架构安装到 `/vendor/lib64/egl/` 与 `/vendor/lib/egl/`，`libgallium_dri.so` 安装到 `/vendor/lib64/` 与 `/vendor/lib/`；`libvulkan_panfrost.so` 由模块 `vulkan.panfrost` 按模块名安装为 `vulkan.panfrost.so`，放到 `/vendor/lib64/hw/` 与 `/vendor/lib/hw/`（`libvulkan` 按 `ro.hardware.vulkan` 拼出 `vulkan.<值>.so` 后 dlopen）；用 `cc_prebuilt_library_shared` 定义，`compile_multilib: "both"`、`strip: { none: true }`、`check_elf_files: false`；
- 使用树内 AOSP clang + 由 bionic/out 产物组装的 sysroot，不依赖外部 NDK：编译器取 `prebuilts/clang/host/linux-x86/clang-r*`（需带 `android_libc++`），libc/libm/libdl 取 `out/soong/.intermediates/bionic/*/*.ndk` 的 `android_arm64_*` 与 `android_arm_*`，crt 取 `out/soong/.intermediates/bionic/libc/*`，libc++ 用 `android_libc++/platform/{aarch64,arm}` 的静态库；
- 出树构建所需的 AOSP 头文件通过交叉文件加入：`system/core/libcutils/include`、`system/core/libsystem/include`、`system/core/libsync/include`、`hardware/libhardware/include`、`frameworks/native/libs/{nativewindow,nativebase,arect}/include`、`system/logging/liblog/include`；bionic 头取自 `bionic/libc/include` 与 `bionic/libc/kernel/{uapi,android/uapi}`；
- C++ 运行时静态链接，避免额外交付 `libc++_shared.so`；
- 每个产物记录 SHA256，记录 Mesa/libdrm/NDK/meson 版本与交叉文件哈希，按项目规则放 `~/temp/docs/`。

边界与退路：

- 预编译只用于本设备的 vendor 镜像，不改 AOSP 上游；
- 升级 Mesa 时必须重跑脚本并更新哈希，不允许手工替换 `.so`；
- 若 `readelf -d` 显示依赖了平台不存在的库，回到构建参数修正，不得在设备上补库绕过。

备选（不采用）：

- 在上游补生成 Soong 目标：技术上最干净，但违反修改范围约束；
- 在 vendor 复制 Mesa 源码：需要复制上千文件，升级同步成本最高；
- 继续 ANGLE + SwiftShader：零成本，但 CPU 占用不可接受，只作为回退。

### D3：gralloc 用 minigbm 的 rockchip 线性后端，但本期只依赖线性组合

- `BoardConfig.mk` 设置 `SOONG_CONFIG_minigbm_platform := rockchip`；
- 上游 `external/minigbm/Android.bp` 的 `soong_config_variable("minigbm", "platform")` 映射表只有 `generic`/`intel`/`meson`/`msm`/`mt8xxx`，没有 `rockchip` 分支；该值走 `default: []`，`-DDRV_ROCKCHIP` 不会被定义；
- `external/minigbm/rockchip.c` 整体位于 `#ifdef DRV_ROCKCHIP` 内，编译产物为空对象；实际注册的是 `dumb_driver.c` 里的 `INIT_DUMB_DRIVER(rockchip)`，即名字为 `rockchip` 的通用 dumb 后端，只提供 `DRM_FORMAT_MOD_LINEAR` 组合；
- 该后端的能力边界：RGBA 系列可 scanout，NV12/NV21/YV12 仅作为纹理（`BO_USE_TEXTURE_MASK`），没有 NV12 scanout、AFBC 与视频 motion vector 空间。这与本期“只保证线性缓冲能被 GPU 导入”的目标一致，代价是视频层需经 GPU 转换后显示；
- 真正的 `rockchip.c` 后端需要 `-DDRV_ROCKCHIP`，本变更不修改上游 `external/minigbm`，因此不启用；后续若需要视频直通或 AFBC，单独立项（vendor gralloc 或上游补丁）；
- AFBC 由 Rockchip 私有 GEM ioctl 创建，Panfrost 能否导入并正确采样这类缓冲尚未验证；本期只使用线性组合；
- Mesa 的 Android EGL 通过 `u_gralloc` 读取缓冲元数据，线性 RGBA/NV12 是最小验证面；
- 运行时还必须把 `ro.hardware.gralloc` 设为 `minigbm`：`u_gralloc` 先调用 `hw_get_module("gralloc")`，只有找到名为 `CrOS Gralloc` 的模块（即 `gralloc.minigbm.so`）才会用 `perform(GRALLOC_DRM_GET_BUFFER_INFO)` 读取 fourcc/stride/offset/modifier；找不到时退化为 fallback，仅支持 RGBA，日志为 `No gralloc hwmodule detected (video buffers won't be supported)`，NV12/YV12 无法导入 GPU；
- `gralloc.minigbm.so`、`mapper.minigbm.so` 与 `libminigbm_gralloc.so` 会在应用进程内被 dlopen，需要 `same_process_hal_file` 标签（permissive 下不明显，enforcing 会拒绝）；
- 走 `default` 分支时 `-DHAS_DMABUF_SYSTEM_HEAP` 同样未定义，`cros_gralloc` 的 reserved region 走 memfd 路径；如需 dma-buf system heap，可把平台值改为 `generic`（仍不会编译 `rockchip.c`）。

### D4：EGL 选择与构建期回退

- `ro.hardware.egl=mesa`，走 Panfrost 原生 GLES；
- ANGLE 保留在镜像中但不设为默认；SwiftShader 作为最终回退；
- `ro.hardware.egl` 是只读属性，回退必须重新构建并刷写 vendor，不能运行期切换；规格与文档必须如实写明；
- Vulkan 由 `ro.hardware.vulkan` 控制，构建期可选 `panfrost`（默认，Mesa PanVK 硬件实现）或 `pastel`（回退，SwiftShader 软件实现）；PanVK 已在目标 GPU 上通过 `/vendor/bin/panvk_smoke` 的 Vulkan 1.0 用例（`Mali-G52 r1 MC1`，`apiVersion` 1.0.346，`driverVersion` 26.0.99），因此设为默认，回退仍用 `pastel`。
- Mesa 26.1 对 Bifrost（arch 6/7）的 PanVK 设了“未充分测试”闸门：`panvk_physical_device_init()` 在 `arch == 6 || arch == 7` 时要求 `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER`，否则返回 `VK_ERROR_INCOMPATIBLE_DRIVER`，该设备被 `enumerate_drm_physical_devices_locked()` 当作不兼容设备跳过，结果是没有物理设备（`cmd gpu vkjson` 的 `devices` 为空），而 instance 与扩展枚举都正常，容易被误判成加载失败。G52 属于 arch 7，因此产品始终注入使能开关；两个 Vulkan 后端（`panfrost`/`pastel`）都随镜像交付，设备上改 `ro.hardware.vulkan` 重启即可切换，不必重新构建。Android 上 Mesa 的 `os_get_option()` 会把该变量映射为属性 `debug.mesa.pan.i.want.a.broken.vulkan.driver`（小写、`_`→`.`、`debug.` 前缀），用 `PRODUCT_VENDOR_PROPERTIES` 交付，不改动 `external/mesa3d`。
- PanVK 在 Bifrost 上只报 Vulkan 1.0：`get_api_version()` 对 `PAN_ARCH < 10` 返回 1.0。HWUI 的 `VulkanManager` 对物理设备 `apiVersion` 有 `>= 1.1` 的 `LOG_ALWAYS_FATAL_IF`，因此 `debug.hwui.renderer=skiavk` 在 G52 上会直接 abort 应用进程，不能作为验收手段；Vulkan 验收用例必须按 Vulkan 1.0 编写。

### D5：Panfrost 系统 suspend/resume 的提交竞态

- 首次 `echo mem` 恢复后，`panfrost_job_timedout()` 在 `readl()` 处触发 synchronous external abort，说明超时线程访问了已掉电的 GPU 寄存器；
- 根因有三层：
  1. DRM scheduler 的 timeout work 不在系统 suspend 时暂停；如果 suspend 前队列里还有未完成的 job，500 ms 超时会在 GPU 掉电后触发；
  2. `panfrost-reset` workqueue 不是 freezable，timeout work 可以在系统 suspend 期间继续运行并访问已掉电寄存器；
  3. 系统 suspend/resume 期间 runtime PM 被暂时禁用；若此时 scheduler 仍提交 job，`pm_runtime_get_sync()` 失败但仍保留 usage counter，job 留在队列中；
- 修复：
  - `panfrost_device_suspend()` 在 `pm_runtime_force_suspend()` 前暂停每个 job slot 的 scheduler timeout；`panfrost_device_resume()` 不再直接恢复，而是由 `panfrost_device_runtime_resume()` 在 GPU 真正上电后恢复；
  - 暂停 timeout 时同时把 `sched->timeout` 临时设为 `MAX_SCHEDULE_TIMEOUT`，避免 suspend 窗口内新提交重新武装 timeout；恢复时还原原始 timeout；
  - `panfrost-reset` workqueue 改为 `WQ_FREEZABLE`，由内核 freezer 在设备 suspend 前等待/冻结 timeout work；
  - `panfrost_job_hw_submit()` 改用 `pm_runtime_resume_and_get()`，失败时返回错误；`panfrost_job_run()` 将错误作为 `ERR_PTR` 返回给 DRM scheduler，让失败 job 走正常的 fence error 完成路径，而不是留在队列里等超时；
  - 同时修正 `JS_COMMAND_NEXT` 非空 WARN 分支的 PM 引用与 devfreq busy 计数泄漏；
- 这是防御性修复：suspend/resume 窗口内提交的帧会被丢弃，但不再 panic；
- 第二次完整 suspend 验证后不再 panic，但 runtime resume 返回 `-ETIMEDOUT`，`rockchip-pm-domain` 报 `failed to set domain 'gpu' on, val=0`；
- 该失败不在内核：RK3568 的 `PD_GPU` 上电握手由 PMU 与 BL31 协同完成，BL31 通过 `PMU_VOL_GATE_SFTCON` 声明哪些电源域带外部供电（电压域），并在 resume 时维护该配置；
- 本地 BL31 只声明了 `VD_NPU_ENA`，没有 `VD_GPU_ENA`，且 `pmu_reinit()` 会在 resume 时把 `PMU_VOL_GATE_SFTCON` 低 16 位写 0，导致 GPU 在系统 suspend 掉电后，PMU 无法完成上电握手；Linux 侧所有 `power_on` 尝试都超时，直到重启；
- 已定位为 TF-A 上游缺陷并修复：`ARM-software/arm-trusted-firmware` 提交 `a934036098b80b12934ee01fef142ab5673dc3d7`（`fix(rk3568): fix GPU domain enable errors`，2026-11-03 合入 master，`LTS-candidate: yes`）
  - 链接：<https://github.com/ARM-software/arm-trusted-firmware/commit/a934036098b80b12934ee01fef142ab5673dc3d7>
  - 该提交说明与本地现象逐字对应：`failed to set domain 'gpu' on, val=0`，且“GPU 恢复后失效直到重启”；
  - 本地 ATF `plat/rockchip/rk3568/drivers/pmu/pmu.c` 在修复前分别为 `WRITE_MASK_SET(BIT(VD_NPU_ENA))` 与 `PMU_VOL_GATE_SFTCON, 0xffff0000`，与补丁 before 状态逐行一致；本地仓库停在 `v2.15.0-1238-geb60949df`（2026-10-22），不含该提交；
  - 修复内容：
    - `pmu_pd_powerdown_config()`：`PMU_VOL_GATE_SFTCON` 同时置位 `VD_GPU_ENA | VD_NPU_ENA`；
    - `pmu_reinit()`：删除对 `PMU_VOL_GATE_SFTCON` 的 `0xffff0000` 清除；
- 修复位于引导固件层：需要重编 BL31，并由 U-Boot binman 重新打包进 `u-boot.itb`，刷 `uboot` 分区；
- 内核侧不保留定位过程中的实验改动（`rockchip,rk3568-mali` 的 `GPU_PM_RT`、`SRST_GPU`、GPU 电源域的 `domain-supply`/`need_regulator`），只保留上述与超时、提交竞态相关的防御性修复。

### D6：补齐 Launcher 依赖的设备特性声明

- `SystemServiceRegistry` 处理 `APPWIDGET_SERVICE` 时会先检查 `android.software.app_widgets` 特性，未声明时直接返回 null，`AppWidgetManager.getInstance()` 随之为 null（`frameworks/base/core/java/android/app/SystemServiceRegistry.java` 的 `hasSystemFeatureOpportunistic()` 分支）；
- Launcher3 的 `OseWidgetManager` 在 OSE 信息更新时通过 `WidgetManagerHelper.getAllProviders()` 直接解引用该对象，导致 `OSEManager` 线程反复 `NullPointerException`（`OseWidgetManager.kt` → `WidgetManagerHelper.java`）；
- 设备原先只在 vendor 侧复制了 opengles/ethernet 等特性文件，缺少 `frameworks/native/data/etc/android.software.app_widgets.xml`；
- 修复：在 `ProductConfig.mk` 复制该特性到 `vendor/etc/permissions/`（与 linaro hikey/dragonboard、amlogic yukawa 的做法一致）。这是设备配置缺失，与 GPU 驱动无关；
- 若后续维护希望把它归入其他变更（显示或系统配置），可以整体搬迁，不影响本变更的 GPU 结论。

### D7：Panfrost 不支持在持有 render node 的情况下热卸载

- `panfrost_remove()` 只调用 `drm_dev_unregister()`（`drivers/gpu/drm/panfrost/panfrost_drv.c`），没有 `drm_dev_unplug()`；随后 `panfrost_device_fini()` 会释放 `pfdev->js`、MMU 等资源（`drivers/gpu/drm/panfrost/panfrost_device.c`）；
- SurfaceFlinger / Mesa 持有的 render node fd 在 unbind 后仍然有效，旧 fd 上的 ioctl 会绕过 unplugged 检查，进入已释放的 `panfrost_device`；`panfrost_gem_create_object()` 读取 `dev->dev_private` 时触发 NULL 解引用，`panic_on_oops` 会把 oops 升级为 kernel panic；
- 这是 DRM 热卸载的边界：`rmmod panfrost` 会因模块在用返回 `-EBUSY`，只有显式写 sysfs `unbind` 才能绕过；正常产品运行不会卸载 GPU 驱动；
- 因此 2.13 不使用 unbind 作为验收手段，改用“GPU 任务失败”路径：suspend 窗口内的 job 超时（D5）与客户端退出时的 in-flight job 取消；若后续确实需要热卸载，需要把 `pfdev` 与 `panfrost_device_init()` 的资源改为 `drmm` 生命周期并延迟 `panfrost_device_fini()`，属于独立改造。

## Risks / Trade-offs

- [GKI 符号白名单不足] → GPU 侧至少需要补 `drm_gem_shmem_madvise_locked`、`drm_gem_shmem_purge_locked` 等当前无厂商清单覆盖的符号，并重建 GKI。
- [新增模块未在 `module_outs` 声明会导致构建失败] → 需要登记 `panfrost.ko` 与 `gpu-sched.ko`。
- [Mesa 26.1 的 Panfrost 需要 CLC/LLVM] → 构建环境安装匹配的 LLVM + libclc + LLVMSPIRVLib + SPIRV-Tools；`build.sh` 在配置前检查并给出安装提示，不满足时直接失败而不是编到一半。
- [预编译库的 C++ 运行时依赖] → 静态链接 libc++，避免交付 `libc++_shared.so`；用 `readelf -d` 检查 NEEDED 只包含 bionic、libdrm 与自身。
- [预编译产物与 Mesa 版本漂移] → 构建脚本固定版本并记录哈希；升级后重跑脚本，不允许手工替换 `.so`。
- [预编译产物不可调试] → 保留带调试信息的副本或 build-id，记录在构建记录中。
- [线性缓冲导致 GPU 性能偏低] → 明确这是本期取舍；AFBC 优化单独立项。
- [minigbm rockchip 后端的 AFBC 缓冲可能无法被 Panfrost 导入] → 本期只用线性组合；验证通过前不启用 AFBC。
- [PanVK 在 Bifrost 上质量不足] → Mesa 26.1 明确把 arch 6/7 的 PanVK 标为未充分测试（需 `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER` 才会枚举出设备），且非 conformant；PanVK 仍必须交付并验证基本渲染，若实测不达标，默认保持 SwiftShader `pastel`，并记录具体失败用例，不能把未验证的后端设为默认。
- [Panfrost 系统 suspend/resume 的提交竞态] → runtime PM 禁用窗口内的 job 现在会以 fence error 完成，不再触发掉电寄存器访问。
- [RK3568 的 GPU 电源域依赖 BL31 行为] → `PD_GPU` 能否在 resume 后重新上电取决于 BL31 的 `PMU_VOL_GATE_SFTCON` 配置；升级 U-Boot/BL31 时必须确认 TF-A 已包含 `a9340360`（`VD_GPU_ENA`），否则会重现 `failed to set domain 'gpu' on`。

## Migration Plan

1. 内核：开 GPU 模块与 `gpu-sched`，验证 render node 与 devfreq。
2. 用户态：先在 `vendor/6xyun/hardware/gpu/mesa/` 跑通出树构建（libdrm + Mesa），把五个库放进预编译目录并用 Soong 预编译模块交付；保留 ANGLE 回退；随后验证 SurfaceFlinger 合成。
3. Vulkan：`PRODUCT_VULKAN_TYPE` 默认 `panfrost`，构建时自动注入 Bifrost 使能属性；用 `/vendor/bin/panvk_smoke` 跑 Vulkan 1.0 离屏 clear/copy 回读作为验收，已验证通过。
4. 回退：重新构建 `ro.hardware.egl=angle` 并刷 vendor；Vulkan 用 `PRODUCT_VULKAN_TYPE=pastel`。

## Open Questions

- 树内 clang 随 `prebuilts` 更新，Mesa 升级时需要重新核对 `android_libc++` 与 bionic 头路径是否仍匹配。
- PanVK 是否足以承载 `debug.hwui.renderer=skiavk`：已确认不能。PanVK 对 Bifrost（`PAN_ARCH < 10`）只报 Vulkan 1.0（`panvk_vX_physical_device.c` 的 `get_api_version()`），而 HWUI 的 `VulkanManager.cpp` 要求物理设备 `apiVersion >= 1.1` 且用的是 `LOG_ALWAYS_FATAL_IF`，强行设置会让应用进程直接 abort。结论是 Vulkan 验收只覆盖 Vulkan 1.0 用例，HWUI 继续走 GLES。
