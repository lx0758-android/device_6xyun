# device/power-hal Specification

## Purpose

定义设备电源 HAL 对上层暴露的行为契约：模式、短时 boost 与 ADPF 调度提示必须真实作用到 CPU 频率与调度参数，且声明能力与实现一致。

## Requirements


### Requirement: 电源服务必须提供真实的模式控制

电源服务 MUST 实现低功耗、持续性能与固定性能三种模式，并将模式作用到 CPU 频率策略；模式关闭后 MUST 恢复到未施加模式限制时的状态。

#### Scenario: 进入低功耗模式

- **WHEN** 上层启用低功耗模式
- **THEN** CPU 最大频率被限制到不高于预设的低功耗上限

#### Scenario: 进入持续性能模式

- **WHEN** 上层启用持续性能模式
- **THEN** CPU 最大频率被限制到预设的持续性能上限，且不低于该上限对应的可用频率

#### Scenario: 退出模式

- **WHEN** 上层关闭已启用的模式
- **THEN** CPU 频率策略恢复到未施加该模式限制时的状态

#### Scenario: 模式互斥顺序变化

- **WHEN** 上层在多个模式之间切换
- **THEN** 最终生效的限制与当前启用的模式集合一致，不残留上一个模式的限制

### Requirement: 短时 boost 必须有时限且可回退

电源服务 MUST 支持交互与显示更新两类 boost，MUST 在指定时长后自动撤销 boost，且后一次 boost MUST 覆盖前一次未到期的 boost。

#### Scenario: 交互 boost

- **WHEN** 上层请求一次有时长的交互 boost
- **THEN** CPU 调度参数在时长内获得提升，时长结束后恢复

#### Scenario: boost 续期

- **WHEN** 前一次 boost 未到期时上层再次请求 boost
- **THEN** 以最后一次请求的时长为准，到期后只撤销一次

### Requirement: 调度提示会话按目标线程生效

电源服务 MUST 提供 ADPF hint session，将目标时长与实际工作时长映射为会话线程的调度提示；会话关闭或暂停后 MUST 撤销提示。

#### Scenario: 创建会话并更新目标时长

- **WHEN** 上层创建会话并更新目标工作时长
- **THEN** 会话线程获得与目标时长对应的调度下限

#### Scenario: 关闭会话

- **WHEN** 上层关闭会话
- **THEN** 会话线程的调度提示被撤销，不再影响其调度

#### Scenario: 线程列表变化

- **WHEN** 上层更新会话线程列表
- **THEN** 新线程获得提示，旧线程不再被本会话影响

### Requirement: 能力声明与实现保持一致

电源服务 MUST 只声明实际支持的 mode、boost 与 session hint；单点查询与整体能力查询的结果 MUST 一致。

#### Scenario: 查询能力

- **WHEN** 上层查询某个 mode 或 boost 是否支持
- **THEN** 返回值与整体能力查询中对应的位一致

#### Scenario: 未实现的提示

- **WHEN** 上层请求未实现的 mode 或 boost
- **THEN** 服务不产生副作用，也不影响已生效的其他提示
