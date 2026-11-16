# device/product-definition Specification

## Purpose

定义 OrangePi-3B 作为 Android 产品的身份与形态边界，使构建系统能够识别该产品，并明确规定本阶段不引入任何硬件服务。

## Requirements

### Requirement: 可被构建系统识别的产品目标

设备MUST提供唯一的产品标识、设备代号、品牌、型号与制造商，并提供 eng/userdebug/user 三种构建变体入口。

#### Scenario: 选择产品变体

- **WHEN** 构建者执行午餐选择并指定该产品
- **THEN** 构建系统识别出产品、设备代号与变体，不出现未定义产品错误

#### Scenario: 产品标识出现在系统属性中

- **WHEN** 构建完成后检查产品属性
- **THEN** 品牌、型号、制造商与产品标识与定义一致

### Requirement: 基于 64 位通用产品与通用 Ramdisk 继承

产品MUST继承 AOSP 的 64 位基础产品与通用 Ramdisk 配置，并以 arm64 为主架构、arm 为辅助架构。

#### Scenario: 双架构构建

- **WHEN** 构建系统属性镜像
- **THEN** 主架构为 arm64、辅助架构为 arm，且均能产出可用的二进制

### Requirement: 本阶段不引入任何硬件服务

本阶段的产品包列表MUST不包含任何硬件服务（HAL）实现；显示、音频、电源、健康、密钥、温控等能力全部留到后续阶段。

#### Scenario: 检查产品包列表

- **WHEN** 审查本阶段的产品包声明
- **THEN** 不存在任何硬件服务实现包，只有构建骨架所需的系统包

#### Scenario: 后续阶段叠加

- **WHEN** 进入硬件服务阶段
- **THEN** 通过独立变更向产品包列表追加服务，而不修改本阶段已定义的产品标识

### Requirement: 设备清单与兼容矩阵以空壳起步

设备的硬件接口清单与兼容矩阵MUST存在但为空壳，具体接口由后续阶段的各服务自带片段提供。

#### Scenario: 空壳清单不阻断构建

- **WHEN** 构建包含空壳设备清单的镜像
- **THEN** 构建通过，且系统不因清单缺少接口而拒绝启动
