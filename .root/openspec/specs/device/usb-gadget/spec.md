# device/usb-gadget Specification

## Purpose

定义设备在引导与运行阶段提供的 USB 外设能力：调试、文件传输、网络共享，以及它们之间的组合切换方式。

## Requirements

### Requirement: USB 控制器以配置子系统方式初始化

设备 MUST 在启动阶段通过配置子系统建立 USB gadget 设备，并指定 USB 控制器实例。

#### Scenario: gadget 建立成功

- **WHEN** 系统启动
- **THEN** USB gadget 设备被创建并绑定到指定控制器

#### Scenario: 控制器实例缺失

- **WHEN** 未指定控制器实例
- **THEN** gadget 无法绑定，USB 功能不可用

### Requirement: 提供调试与文件传输功能

设备 MUST 提供调试（adb）、媒体传输（MTP）与图片传输（PTP）三种 USB 功能，并支持在它们与调试功能的组合之间切换。

#### Scenario: 主机识别调试设备

- **WHEN** 设备以调试功能连接主机
- **THEN** 主机可执行调试命令

#### Scenario: 切换到文件传输

- **WHEN** 系统切换 USB 配置为媒体传输
- **THEN** 主机识别为媒体设备，可浏览文件

### Requirement: 提供设备身份信息

USB gadget MUST 向主机报告设备序列号、厂商字符串与产品字符串，并使用稳定的厂商与产品标识。

#### Scenario: 主机读取设备信息

- **WHEN** 设备连接到主机
- **THEN** 主机可读取到序列号、厂商与产品名称

### Requirement: 支持网络共享与音频类功能的组合

设备 MUST 支持网络共享、音频源等 USB 功能，并允许与调试功能组合。

#### Scenario: 网络共享与调试并存

- **WHEN** 系统切换为网络共享加调试
- **THEN** 主机同时看到网络接口与调试设备

#### Scenario: 仅插入单个功能时不影响已建立连接

- **WHEN** 系统在功能组合之间切换
- **THEN** 连接按新组合重新枚举，不需要重启设备
