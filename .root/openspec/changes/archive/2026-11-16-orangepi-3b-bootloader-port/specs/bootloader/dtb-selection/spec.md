# Spec Delta

## Purpose

定义引导程序为不同硬件板型选择设备树的契约，保证板型探测结果、设备树文件名与 `vendor_boot` 内设备树索引三者一致。

## ADDED Requirements

### Requirement: 板型探测结果驱动设备树选择

引导程序 MUST 通过硬件板型探测确定当前板型，并据此设置引导用设备树文件名与 Android 设备树索引。

#### Scenario: 识别为 v1.1 板型

- **WHEN** 板型探测结果为 v1.1
- **THEN** 引导程序设置对应的设备树文件名，并将 Android 设备树索引设为 0

#### Scenario: 识别为 v2.1 板型

- **WHEN** 板型探测结果为 v2.1
- **THEN** 引导程序设置对应的设备树文件名，并将 Android 设备树索引设为 1

### Requirement: 设备树索引与 vendor_boot 交付顺序严格对应

`vendor_boot` 内设备树的排列顺序 MUST 与索引定义一致：索引 0 为 v1.1，索引 1 为 v2.1。内核侧交付顺序变更时必须同步更新引导程序。

#### Scenario: 索引与顺序一致

- **WHEN** 系统按索引取用设备树
- **THEN** 取到的设备树与当前板型匹配

#### Scenario: 顺序被改动

- **WHEN** 内核侧调换了设备树交付顺序而未同步引导程序
- **THEN** 板型与设备树不匹配，必须在联调阶段被发现并修正

### Requirement: 无 Android 设备树时退回引导程序自带设备树

当 `vendor_boot` 中不存在可用的 Android 设备树时，引导程序 MUST 使用自身携带的设备树继续启动。

#### Scenario: vendor_boot 无设备树

- **WHEN** `vendor_boot` 未提供设备树
- **THEN** 引导程序使用自带设备树启动系统，并在日志中体现回退
