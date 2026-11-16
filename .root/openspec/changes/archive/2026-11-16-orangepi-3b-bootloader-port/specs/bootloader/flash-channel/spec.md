# Spec Delta

## Purpose

定义设备在引导阶段可用的刷机与恢复通道：USB 外设模式下的 fastboot 能力、退回芯片下载模式的手段，以及引导环境的持久化方式。

## ADDED Requirements

### Requirement: 承载外设功能的 USB 控制器进入设备模式

引导程序 MUST 将承载外设功能的 USB 控制器配置为双角色并工作在设备模式，同时关闭与之冲突的同端口主机控制器。

#### Scenario: 主机识别到 fastboot 设备

- **WHEN** 设备以 fastboot 模式启动并连接到主机
- **THEN** 主机枚举到该设备并可执行 fastboot 命令

#### Scenario: 同端口主机控制器不干扰

- **WHEN** 设备工作在设备模式
- **THEN** 同端口的低速主机控制器处于关闭状态

### Requirement: fastboot 具备写入存储分区的能力

fastboot 实现 MUST 支持向 eMMC 分区写入镜像，并支持分区表创建与 OEM 格式化操作。

#### Scenario: 刷写启动分区

- **WHEN** 主机执行对启动分区的刷写命令
- **THEN** 镜像被写入对应 eMMC 分区

#### Scenario: 按分区名定位 GPT 分区

- **WHEN** 主机请求刷写名为 `boot` 的分区
- **THEN** 引导程序解析 GPT 分区表并按名称定位到对应分区，不使用固定偏移

#### Scenario: 重建分区表

- **WHEN** 主机执行分区表创建命令
- **THEN** 设备按给定分区表重建 eMMC 分区

### Requirement: 支持 eMMC 引导分区与整盘设备作为刷写目标

fastboot 实现 MUST 支持以特殊目标名操作 eMMC 引导分区（boot0/boot1）与整盘 user 区域，而不局限按分区表分区名刷写。

#### Scenario: 刷写 eMMC 引导分区

- **WHEN** 主机以 `mmc0boot0` 或 `mmc0boot1` 作为目标刷写
- **THEN** 引导程序切换到对应硬件分区并写入数据

#### Scenario: 擦除整盘 user 区域

- **WHEN** 主机以 `mmc0` 作为目标执行擦除
- **THEN** 引导程序擦除整盘 user 区域

#### Scenario: 更新分区表镜像

- **WHEN** 主机以 `gpt` 或 `mbr` 作为目标刷写分区表
- **THEN** 引导程序按对应分区表格式重建分区信息

### Requirement: 可退回芯片下载模式

引导程序 MUST 提供一条命令，用于把平台记录设为下载模式并复位，使设备重新进入芯片内置的下载模式。

#### Scenario: 主动进入下载模式

- **WHEN** 在引导程序控制台执行该命令
- **THEN** 设备复位后进入芯片下载模式，可被主机端的下载工具识别

#### Scenario: 从异常状态恢复

- **WHEN** 系统分区损坏无法启动
- **THEN** 可通过该通道重新写入引导程序与系统镜像

### Requirement: 引导环境持久化在本地存储

引导程序 MUST 将环境变量持久化到 eMMC，并以板级环境文件作为默认值来源。

#### Scenario: 保存环境变量

- **WHEN** 执行保存环境变量操作
- **THEN** 变量被写入本地存储，下次上电仍然生效

#### Scenario: 首次上电使用默认值

- **WHEN** 本地存储中尚无环境变量
- **THEN** 使用板级环境文件提供的默认值
