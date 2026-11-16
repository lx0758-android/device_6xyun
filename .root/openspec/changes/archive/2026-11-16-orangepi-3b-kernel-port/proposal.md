# Proposal

## Why

OrangePi-3B（RK3566）适配 AOSP 17 的内核侧采用与手机厂商一致的标准移植路径：**共享 GKI 内核 + 板级模块（mixed build）**，而不是维护一份板级独立内核。该移植目前只以代码和零散笔记的形式存在，缺少可追溯、可演进的行为规格；后续 GPU、视频编解码、WiFi/BT 等硬件适配会持续改动内核，需要一份与实现对齐、能约束未来改动的规格基线。

## What Changes

- 新增内核移植的能力规格：构建模型、配置分层、KMI 契约、设备树契约、启动可观测性。
- **BREAKING**：明确 GKI 侧只允许"平台使能"级别的改动（SoC 架构、PCIe 主机控制器、IOMMU、串口 UART 计数修复），其余板级功能一律通过板级 fragment 以 `=m` 提供，禁止把外设驱动塞进 GKI。
- 固化产物契约：一次构建产出「GKI 内核镜像 + 板级模块集 + 板级 dtb」，并规定 dist 目录的可引用内容。
- 固化 KMI 符号白名单的命名与维护方式：使用厂商标识 `6xyun`（未来可能扩展多款设备），并提供官方工具更新流程。
- 记录三类**有意保留**的现状：板级设备树中尚未移植驱动的节点（`sprd,mtty` / `unisoc,uwe_bsp`）、eMMC 控制器降到 150 MHz、启动时明文打印 bootconfig。

## Capabilities

### New Capabilities

- `kernel/mixed-build`：GKI 共享内核与板级模块的构建模型、目标命名、产物与 dist 布局契约。
- `kernel/config-layering`：GKI defconfig 与板级 fragment 的分层规则，包含 tristate 约束与串口控制台可用性。
- `kernel/kmi-contract`：板级 KMI 符号白名单、GKI ABI 基线与符号更新工具链的契约。
- `kernel/board-devicetree`：板级设备树必须提供的节点与属性（TEE、重启模式、USB OTG、I2C、eMMC 频率）。
- `kernel/boot-observability`：串口控制台与 bootconfig 打印构成的启动期可观测性。

### Modified Capabilities

无。

## Impact

- 内核仓库 `kernel/common`：`BUILD.bazel`、`arch/arm64/configs/{gki_defconfig,orangepi3b_gki.fragment}`、`arch/arm64/boot/dts/rockchip/*`、`gki/aarch64/{abi.stg,symbols/6xyun}`、`init/main.c`。
- 构建工具链：kleaf/bazel（`kernel/build` 无需改动），产物落地 `out/orangepi3b/dist`。
- 下游依赖：AOSP 设备配置以 `KERNEL_DIR := <kernel 仓库>/out/orangepi3b/dist` 引用 `Image`、`*.dtb`、`*.ko` 与 `modules.load`；该目录结构属于本规格的对外契约。
- 不在本次范围内：BL31/OP-TEE 固件构建、U-Boot 移植（另行立项）、硬件编解码与 GPU 驱动适配。
