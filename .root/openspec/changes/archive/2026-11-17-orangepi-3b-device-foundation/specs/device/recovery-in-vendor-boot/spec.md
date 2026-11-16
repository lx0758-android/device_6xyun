# Spec Delta

## Purpose

定义恢复能力的打包形态与进入条件：在没有独立恢复分区的设备上，恢复组件如何随厂商启动镜像交付、如何被触发，以及 fastbootd 如何获得动态分区操作能力。

## ADDED Requirements

### Requirement: 恢复资源随厂商启动镜像交付

恢复组件MUST打包进厂商启动镜像的厂商 Ramdisk，不生成独立的恢复镜像，也不在分区表中划分恢复分区。

#### Scenario: 产物中没有恢复镜像

- **WHEN** 检查构建产物
- **THEN** 不存在独立恢复镜像文件，分区表中也没有恢复分区

#### Scenario: 恢复组件位于厂商 Ramdisk

- **WHEN** 检查厂商启动镜像内容
- **THEN** 其中包含恢复可执行文件

### Requirement: 恢复模式由引导控制块触发

恢复模式MUST由引导程序依据引导控制块决定，并抑制"强制正常启动"参数；正常启动则MUST显式声明强制正常启动。

#### Scenario: 正常启动不进入恢复

- **WHEN** 引导控制块无命令字且正常启动
- **THEN** 系统进入正常模式，不进入恢复界面

#### Scenario: 请求恢复模式

- **WHEN** 引导控制块命令字为恢复请求
- **THEN** 系统进入恢复模式

### Requirement: 恢复环境支持动态分区操作

恢复环境MUST包含 fastbootd 能力，使其能够对动态分区容器进行更新与刷写。

#### Scenario: fastbootd 可用

- **WHEN** 设备进入恢复环境并启动 fastbootd
- **THEN** 主机可通过 fastboot 执行动态分区更新

#### Scenario: 刷写物理分区回退

- **WHEN** 主机使用引导程序自带的 fastboot 刷写物理分区
- **THEN** 操作不依赖恢复环境

### Requirement: 恢复环境不依赖硬件服务

恢复环境的可用性MUST NOT依赖本阶段未包含的硬件服务；显示与输入由恢复自身的渲染与内核驱动提供。

#### Scenario: 无硬件服务时仍可进入恢复

- **WHEN** 系统镜像中没有任何硬件服务
- **THEN** 仍可进入恢复环境并显示界面
