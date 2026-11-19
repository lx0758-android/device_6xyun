# Tasks

## 1. GPU 内核

- [x] 1.1 板级 fragment 增加 `CONFIG_DRM_PANFROST=m`；`CONFIG_DRM_SCHED` 由 panfrost 自动选为模块，不需要单独写；已确认 GKI 的 `IOMMU_IO_PGTABLE_LPAE`、`DRM_GEM_SHMEM_HELPER`、`DEVFREQ_GOV_SIMPLE_ONDEMAND`、`WANT_DEV_COREDUMP` 均为内建
- [x] 1.2 构建内核，确认产出 `panfrost.ko` 与 `gpu-sched.ko`（模块名不是 `drm_sched.ko`），modpost 无未解析符号；把 `drivers/gpu/drm/panfrost/panfrost.ko` 与 `drivers/gpu/drm/scheduler/gpu-sched.ko` 写入 `_ORANGEPI3B_MODULE_OUTS`
- [x] 1.3 按 modpost 结果向 `gki/aarch64/symbols/6xyun` 补 KMI 符号并重建 GKI；至少包含当前无任何厂商清单覆盖的 `drm_gem_shmem_madvise_locked`、`drm_gem_shmem_purge_locked`，以及 `alloc_io_pgtable_ops`、`free_io_pgtable_ops`、`devfreq_add_device` 等依赖
- [x] 1.4 确认 `modules.dep` 中 `panfrost.ko` 依赖 `gpu-sched.ko`，首阶段加载无失败；init 的模块加载是 strict 模式，任一模块失败会中止后续模块
- [x] 1.5 上机验证：`/dev/dri/renderD128` 存在（先 `ls /dev/dri` 确认编号），`dmesg | grep -i panfrost` 无供电/固件错误
- [x] 1.6 验证 GPU 调频：空闲与持续渲染下读取 devfreq 频率，确认随负载变化；若 probe 报 `Couldn't set recommended OPP`，先查 SCMI GPU 时钟是否支持 set_rate

## 2. GPU 用户态（出树构建 + 预编译交付）

- [x] 2.1 在 `vendor/6xyun/hardware/gpu/mesa/` 建立出树构建工程：交叉文件、`build.sh`、版本与哈希记录；源码只读引用 `external/mesa3d` 与 `external/libdrm`，不修改、不复制
- [x] 2.2 工具链 spike：验证树内 AOSP clang（`clang-r*` + bionic NDK 库 + 树内 libc++）能完成 Meson 配置与编译；本机无 meson 时先安装，结论写入构建记录
- [x] 2.3 用每个架构各自的交叉文件把 libdrm 构建到临时 sysroot，再按 `-Dplatforms=android -Dandroid-stub=true -Dgallium-drivers=panfrost -Dvulkan-drivers= -Dglx=disabled -Dgbm=disabled -Dopengl=false -Dgles1=enabled -Dgles2=enabled -Degl-lib-suffix=_mesa -Dgles-lib-suffix=_mesa` 构建 Mesa；arm64 与 arm 都要产出
- [x] 2.4 确认每个架构的产物只有四个：`libEGL_mesa.so`、`libGLESv1_CM_mesa.so`、`libGLESv2_mesa.so`、`libgallium_dri.so`；Mesa 26.1 不再交付 `libglapi.so`，也不需要 `libGLES_mesa.so`；`readelf -d` 只允许依赖 bionic、libdrm 与自身
- [x] 2.5 把 arm64 与 arm 产物放到 `vendor/6xyun/prebuilts/gpu/mesa/<arch>/`，记录 SHA256 与来源；用 `cc_prebuilt_library_shared` + `compile_multilib: "both"` 定义模块：前三个 `relative_install_path: "egl"`，`libgallium_dri` 装 `/vendor/lib64/` 与 `/vendor/lib/`，`strip: { none: true }`、`check_elf_files: false`
- [x] 2.6 在 `device/6xyun/orangepi_3b/ProductConfig.mk` 增加预编译包与 `ro.hardware.egl=mesa`；为 `libgallium_dri.so` 补 `same_process_hal_file` 标签；确认 `/vendor/lib/egl` 与 `/vendor/lib64/egl` 均有对应库，且加载无 avc
- [x] 2.7 上机验证 GLES：确认 32 位与 64 位 zygote 都能启动，渲染器报告为 Panfrost，`dumpsys SurfaceFlinger` 显示 RenderEngine 使用 GPU；设备合成（HWC）与客户端合成分别记录，不把 HWC 合成误判为 GPU 合成
- [x] 2.8 实测 GLES 3.1 后把 `ro.opengles.version` 从 196608 改为 196609，并补 `android.hardware.opengles.aep.xml`
- [x] 2.9 验证缓冲互操作：确认 minigbm 选中 rockchip 后端，其线性 NV12/RGBA 缓冲能被 Panfrost 导入并渲染
- [x] 2.10 验证挂起/恢复：`echo mem` 前后 render node 与 devfreq 均正常，无 oops；前置条件是 BL31 含 TF-A 修复 `a9340360`（RK3568 `PMU_VOL_GATE_SFTCON` 置位 `VD_GPU_ENA`、`pmu_reinit()` 不再清除该配置，见 design.md D5）；回归 Panfrost suspend/resume 修复（timeout 随 runtime PM 暂停/恢复、`panfrost-reset` 改为 `WQ_FREEZABLE`、`pm_runtime_resume_and_get()` + `ERR_PTR` 失败路径）
- [x] 2.11 验证回退：重新构建为 `ro.hardware.egl=angle` 并刷 vendor，系统正常启动与显示；回退是构建期行为，不是运行期属性开关
- [x] 2.12 交付并验证 PanVK（必交付项）：Mesa 以 `-Dvulkan-drivers=panfrost` 构建，预编译模块 `vulkan.panfrost` 按模块名把 `libvulkan_panfrost.so` 装成 `vulkan.panfrost.so`（`/vendor/lib64/hw/` 与 `/vendor/lib/hw/`），并进 `PRODUCT_PACKAGES`；Bifrost（arch 7）需要 `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER`，由产品始终注入属性 `debug.mesa.pan.i.want.a.broken.vulkan.driver=1`（`panfrost`/`pastel` 两个后端都随镜像交付）；`cmd gpu vkjson` 枚举到 `Mali-G52 r1 MC1`，`/vendor/bin/panvk_smoke` 输出 `RESULT: PASS`，默认已切到 `panfrost`，回退路径为 `pastel`（记录见 `verification.md`）
- [x] 2.13 验证异常隔离：卸载或停止 GPU 驱动、或人为触发一次 GPU 任务失败，确认系统不 panic、`dmesg` 有明确错误；软件回退按 2.11 的构建期路径验证

## 3. 整体验证

- [x] 3.1 `openspec validate orangepi-3b-gpu-bringup --strict` 通过
- [x] 3.2 GPU 侧验收：界面 GPU 渲染（2.7）、挂起恢复（2.10）、Vulkan 后端（2.12）与异常隔离（2.13）分别记录，不把 HWC 设备合成算作 GPU 渲染（记录见 `verification.md`）
- [x] 3.3 记录回退矩阵：GPU → `m vendorimage PRODUCT_EGL_TYPE=angle` 并刷 vendor；Vulkan → `m vendorimage PRODUCT_VULKAN_TYPE=pastel` 并刷 vendor（矩阵与状态见 `verification.md`）

## Workflow follow-up

- 内核改动与 Mesa/libdrm 的来源、版本、commit、构建参数与产物 SHA256 写入 `~/temp/docs/` 的移植记录，便于升级时复核。
- 本变更通过后归档；显示输出由 `orangepi-3b-display-bringup` 负责，视频编解码与音频不在此变更内。
