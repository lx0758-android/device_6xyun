# Proposal

## Why

OrangePi-3B（RK3566）要跑 Android 17，先需要一个能通过编译、能产出完整可刷写镜像集合的设备配置骨架。当前树里只有产品入口与公共构建规则，缺少产品/单板配置、分区定义与镜像规则，`lunch` 无法完成。把这一步单独成阶段，先验证"分区 + 镜像 + 挂载"这条地基，再叠加硬件服务，能把失败面收敛。

## What Changes

- 新增 `orangepi_3b` 产品定义与单板构建配置，使 `lunch orangepi_3b-*` 可用。
- **BREAKING**：设备形态从"虚拟 A/B"改为**非 A/B + 恢复资源置于 vendor_boot**，分区表、fstab、镜像集合随之改变。
- 新增 Rockchip 风格的 GPT 参数文件生成、动态分区（super）与非 A/B 镜像产物规则。
- 新增首阶段挂载与基础 init 行为、基础 SELinux 类型与块设备上下文。
- **本阶段不包含任何硬件服务（HAL）包**：显示、音频、电源、健康、密钥等全部留到下一阶段；本阶段验收标准是"编译通过 + 镜像齐全"，不要求开机。

## Capabilities

### New Capabilities

- `device/product-definition`：产品标识、架构、基础产品继承、空壳设备清单与本阶段的服务边界。
- `device/partition-layout`：GPT 分区表、非 A/B 分区命名、动态分区组与元数据分区。
- `device/boot-artifacts`：启动镜像、厂商启动镜像、设备树镜像、内核与模块集成、引导程序产物导出。
- `device/first-stage-mount`：首阶段挂载、逻辑分区解析、用户数据加密与基础 init 动作。
- `device/recovery-in-vendor-boot`：恢复资源打包形态、进入条件与 fastbootd 能力。
- `device/selinux-baseline`：阶段性宽容模式、基础类型与设备节点上下文、预编译策略。

### Modified Capabilities

无。

## Impact

- 设备配置目录：`device/6xyun/{AndroidProducts.mk,common/**,orangepi_3b/**}`（含新增 `orangepi_3b/` 目录）。
- 构建输入：内核发布目录（`Image`、两个 dtb、`*.ko`、`modules.load`）与引导程序构建目录（`idbloader.img`、`u-boot.itb`）。
- 构建产物：`parameter.txt`、`boot.img`、`vendor_boot.img`、`dtbo.img`、`metadata.img`、`cache.img`、`super.img`、`userdata.img`、空置的 `vbmeta` 分区镜像。
- 不产生：独立 `recovery.img`、`vbmeta.img`。
- 与后续阶段的关系：`orangepi-3b-boot-bringup` 在本阶段骨架上叠加最小 HAL 集并验证开机。
