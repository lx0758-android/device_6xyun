# Proposal

## Why

OrangePi-3B（RK3566）的引导程序基于主线 U-Boot 快照并叠加少量本地补丁，负责把 Android 17 的 `boot`/`vendor_boot` 拉起来、注入启动参数、选择板型设备树并提供刷机通道。这些行为目前只体现在代码里，没有任何规格记录；而其中两处补丁修复的是主线 U-Boot 自身的缺陷，一旦换基线就会静默回归，必须被显式记录。

## What Changes

- 新增引导程序的能力规格，覆盖 Android 启动链、镜像解析、设备树选择、刷机通道与启动完整性语义。
- **BREAKING**：明确当前实现基于主线 U-Boot 快照（而非某次正式发布版），本地补丁必须随基线迁移。
- 固化两处主线缺陷修复的契约：arm64 未压缩内核的 2 MB 对齐回退、`vendor_boot` 中 dtb 区域偏移必须按头部对齐后的大小计算。
- 固化内存布局约定：`boot` 分区装载地址、`vendor_boot` 压缩装载地址、内核装载地址的对齐要求。
- **BREAKING**：设备形态从 A/B 切换为**非 A/B**——使用无槽位分区、正常启动模式下始终声明非恢复模式（恢复/fastbootd/引导程序模式不受影响），使恢复资源放入厂商启动镜像后仍能正常进系统。
- 固化 NO AVB 的适配契约：不启用校验库与校验命令、不读取校验分区、启动状态恒为未验证；并在板级配置中显式关闭校验能力。
- 补齐 fastboot 写入存储的后端能力声明，使其从"本机配置生效"变为"干净树可复现"。

## Capabilities

### New Capabilities

- `bootloader/android-boot-chain`：从分区扫描、启动模式判定到启动参数注入的完整 Android 启动链。
- `bootloader/android-image-handling`：Android 启动镜像与 `vendor_boot` 镜像的解析契约，含两处对齐规则。
- `bootloader/dtb-selection`：按板型选择设备树的索引契约与三方一致性要求。
- `bootloader/flash-channel`：USB 外设模式、fastboot 能力与回退到芯片下载模式的通道。
- `bootloader/boot-integrity`：未启用验证启动时的状态语义与安全执行环境固件的装载方式。

### Modified Capabilities

无。

## Impact

- U-Boot 仓库：`configs/orangepi-3b-rk3566_defconfig`、`board/xunlong/orangepi-3b-rk3566/{.c,.env}`、`arch/arm/dts/rk3566-orangepi-3b-u-boot.dtsi`、`boot/image-android.c`、`boot/image-fdt.c`、`cmd/rbrom.c`。
- 构建输入：BL31/BL32（OP-TEE）固件由构建参数注入，二进制不入库。
- 下游依赖：AOSP 设备配置编译出的 `boot.img`/`vendor_boot.img` 头部版本、页大小与 `parameter.txt` 分区布局必须与本规格一致。
- 不在本次范围内：U-Boot 侧设备树与内核侧设备树的一致性同步（`dr_mode`、安全内存保留）。
