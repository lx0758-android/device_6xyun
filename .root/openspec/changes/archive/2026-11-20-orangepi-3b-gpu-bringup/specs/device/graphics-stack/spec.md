# Spec Delta

## Purpose

定义设备图形后端的选择与回退：在具备 GPU 时使用硬件图形，缺失或初始化失败时回退软件，且切换是构建期可回退的。显示输出的模式与多显示行为由 `orangepi-3b-display-bringup` 的 `device/display-outputs` 负责。

## REMOVED Requirements

### Requirement: 无硬件 GPU 时使用软件图形回退

**Reason**: 本变更落地后设备将具备 GPU 驱动，把软件回退当作默认行为无法表达"硬件优先、失败回退"的契约。

**Migration**: 由新增的「图形后端按硬件能力选择，缺失时回退软件」要求取代，保留原有软件回退场景，并补充硬件可用与初始化失败两种场景。

## ADDED Requirements

### Requirement: 图形后端按硬件能力选择，缺失时回退软件

设备 MUST 在存在可用 GPU 驱动时使用硬件图形实现完成渲染与合成；在 GPU 驱动缺失或初始化失败时 MUST 使用软件实现，并将图形后端配置指向该实现，保证界面仍可显示。

#### Scenario: 硬件 GL 可用

- **WHEN** 系统初始化图形接口且 GPU 驱动可用
- **THEN** 图形接口解析到硬件实现，合成器成功创建硬件上下文

#### Scenario: 无 GPU 驱动不阻塞开机

- **WHEN** 系统中不存在 GPU 渲染节点
- **THEN** 系统仍能完成开机并显示界面，图形接口回退到软件实现

#### Scenario: 硬件实现初始化失败

- **WHEN** GPU 驱动存在但上下文创建失败
- **THEN** 系统记录明确错误，可通过构建配置回退到软件实现完成显示
