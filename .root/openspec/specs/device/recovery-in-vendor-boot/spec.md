# device/recovery-in-vendor-boot Specification

## Purpose

定义恢复能力的打包形态与进入条件：在没有独立恢复分区的设备上，恢复组件如何随厂商启动镜像交付、如何被触发，以及 fastbootd 如何获得动态分区操作能力。

## Requirements

### Requirement: 恢复资源随厂商启动镜像交付

恢复组件 MUST 打包进厂商启动镜像的厂商 Ramdisk，且 MUST 同时包含恢复可执行文件 `/system/bin/recovery`、恢复环境的 `/system/etc/init/hw/init.rc`，以及二者运行所需的 init、linker 与链接配置；MUST NOT 只放入 `fastbootd` 而缺少恢复可执行文件。不生成独立的恢复镜像，也不在分区表中划分恢复分区。

#### Scenario: 产物中没有恢复镜像

- **WHEN** 检查构建产物
- **THEN** 不存在独立恢复镜像文件，分区表中也没有恢复分区

#### Scenario: 恢复组件完整地位于厂商 Ramdisk

- **WHEN** 检查厂商启动镜像内容
- **THEN** 其中同时存在 `system/bin/recovery` 与 `system/etc/init/hw/init.rc`

#### Scenario: 缺少恢复可执行文件时不具备恢复能力

- **WHEN** 厂商 Ramdisk 只有 `fastbootd` 而没有 `system/bin/recovery`
- **THEN** init 不进入恢复模式，引导控制块中的恢复或 fastbootd 请求按正常启动处理

### Requirement: 恢复环境携带可用的分区表

恢复环境 MUST 在 `/etc/recovery.fstab` 提供与正常启动一致的分区表，其中 MUST 包含带 `logical` 标记的 system、vendor、product 条目；分区表缺失或为空时，恢复进程 MUST NOT 以断言崩溃的方式继续。

#### Scenario: 恢复进程能读取分区表

- **WHEN** 恢复进程启动
- **THEN** 能从 `/etc/recovery.fstab` 读到非空分区表，不因 `fstab.empty()` 中止

#### Scenario: 动态分区条目可用

- **WHEN** fastbootd 需要更新逻辑分区
- **THEN** 分区表包含 `logical` 标记的 system、vendor、product 条目

### Requirement: 恢复模式由引导控制块触发

恢复模式MUST由引导程序依据引导控制块决定，并抑制"强制正常启动"参数；正常启动则MUST显式声明强制正常启动。

#### Scenario: 正常启动不进入恢复

- **WHEN** 引导控制块无命令字且正常启动
- **THEN** 系统进入正常模式，不进入恢复界面

#### Scenario: 请求恢复模式

- **WHEN** 引导控制块命令字为恢复请求
- **THEN** 系统进入恢复模式

### Requirement: 恢复环境支持动态分区操作

恢复环境 MUST 包含 fastbootd 能力，使其能够对动态分区容器进行更新与刷写；并 MUST 通过产品属性提供恢复环境的 USB 标识（`ro.recovery.usb.vid`、`ro.recovery.usb.fastboot.pid`），使主机能够枚举设备。

#### Scenario: fastbootd 可用

- **WHEN** 设备进入恢复环境并启动 fastbootd
- **THEN** 主机可通过 fastboot 执行动态分区更新

#### Scenario: 主机识别 fastbootd

- **WHEN** 设备处于 fastbootd 并连接到主机
- **THEN** `fastboot getvar is-userspace` 返回 `yes`，且主机可对逻辑分区执行刷写

#### Scenario: USB 标识缺失

- **WHEN** 产品没有提供恢复环境的 USB 标识属性
- **THEN** USB gadget 无法枚举，主机不能执行 fastbootd 操作

#### Scenario: 刷写物理分区回退

- **WHEN** 主机使用引导程序自带的 fastboot 刷写物理分区
- **THEN** 操作不依赖恢复环境

### Requirement: 恢复环境不依赖硬件服务

恢复环境的可用性MUST NOT依赖本阶段未包含的硬件服务；显示与输入由恢复自身的渲染与内核驱动提供。

#### Scenario: 无硬件服务时仍可进入恢复

- **WHEN** 系统镜像中没有任何硬件服务
- **THEN** 仍可进入恢复环境并显示界面
