# device/power-supply Specification

## Purpose

定义无电池、直流直接供电设备的电源状态上报契约，使 Android 明确知道"外部供电在线、电池不存在"，不产生虚假电量、温度或低电关机行为。

## Requirements


### Requirement: 必须报告电池不存在

Health HAL MUST 报告 `batteryPresent = false`，且 MUST NOT 声明任何电池容量、循环次数或健康度读数。

#### Scenario: 状态查询

- **WHEN** 上层查询电池状态
- **THEN** 返回电池不存在，容量、电压、电流、温度等字段不包含编造值

#### Scenario: 电池属性广播

- **WHEN** 系统发送电池状态广播
- **THEN** `EXTRA_PRESENT` 为 false，依赖电池存在的字段不产生误导性数值

### Requirement: 必须报告外部供电在线

设备由直流输入直接供电，Health HAL MUST 以外部供电在线表达该事实，使系统与界面不显示"未插电"。

#### Scenario: 供电状态

- **WHEN** 上层查询充电器状态
- **THEN** 至少一种外部供电路径报告在线，USB 与无线供电路径按实际硬件报告

#### Scenario: 界面显示

- **WHEN** 系统界面展示电源状态
- **THEN** 不出现"未插电"的错误表述

### Requirement: 不得编造电池读数

Health HAL MUST NOT 返回虚假的电量百分比、电压、电流、温度、健康度或充电时间；不支持的字段 MUST 使用未知或未支持值。

#### Scenario: 不支持的字段

- **WHEN** 上层查询本机不具备的电池字段
- **THEN** 返回未知或未支持，而不是固定数值

#### Scenario: 容量等级

- **WHEN** 上层查询电池容量等级
- **THEN** 返回未支持，不返回正常、低电或严重低电

### Requirement: 不得触发低电关机

系统 MUST NOT 因"电量为 0"或"未充电"触发低电关机；无电池设备 MUST 保持运行直到用户主动关机或外部供电断开。

#### Scenario: 长时间待机

- **WHEN** 设备在直接供电下长时间待机
- **THEN** 系统不产生低电关机请求

#### Scenario: 重启循环

- **WHEN** 设备多次重启
- **THEN** 每次都能正常完成启动，不因电池状态被中途关机

### Requirement: 必须使用真实的 Health HAL 实现

产品 MUST 提供读取本机实际状态并如实上报的 Health HAL；仅满足接口但返回固定示例值的实现不视为满足本要求。

#### Scenario: 服务注册

- **WHEN** 系统启动完成
- **THEN** `android.hardware.health.IHealth/default` 可用，且实现与产品硬件形态一致

#### Scenario: 使用示例实现

- **WHEN** 产品只包含示例 Health 服务
- **THEN** 即使电池字段碰巧正确，也不满足"如实上报供电形态"的要求

### Requirement: 供电形态变化时必须更新契约

当硬件改为电池供电、USB-PD 或增加充电检测时，本契约 MUST 同步更新；不得沿用"直接供电、无电池"的固定上报。

#### Scenario: 硬件变更审查

- **WHEN** 设备的供电硬件发生变化
- **THEN** Health HAL 的上报逻辑与规格一并更新，并重新验证电池与充电状态
