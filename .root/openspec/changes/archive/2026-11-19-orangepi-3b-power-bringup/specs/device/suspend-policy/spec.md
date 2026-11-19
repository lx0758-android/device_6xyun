# Spec Delta

## Purpose

定义本机空闲时的系统挂起与后台活动策略：作为常供电设备，默认不进入自动挂起；同时启用 Doze（device idle），让熄屏后的后台活动逐级收敛。手动挂起保留，用于内核低功耗验证。

## ADDED Requirements

### Requirement: 默认不启用框架自动挂起

产品 MUST 通过 framework 资源 overlay 将 `config_useAutoSuspend` 置为 `false`，使 `PowerManagerService` 不调用 `nativeSetAutoSuspend(true)`，系统在空闲时不发起自动挂起。这是本机作为常供电设备的设计规格，不是临时规避。

#### Scenario: 空闲且无唤醒锁

- **WHEN** 屏幕关闭且没有活跃的 wakelock
- **THEN** 系统保持运行，`dmesg` 不出现新的 `PM: suspend entry`

#### Scenario: 屏幕点亮

- **WHEN** 用户点亮屏幕
- **THEN** 系统不需要从 deep suspend 恢复，显示与输入立即可用

### Requirement: 必须启用 Doze

产品 MUST 通过 framework 资源 overlay 将 `config_enableAutoPowerModes` 置为 `true`，使 `DeviceIdleController` 启用 light idle 与 deep idle。

#### Scenario: 熄屏后逐级进入 idle

- **WHEN** 屏幕关闭且设备未处于充电状态
- **THEN** 先进入 light idle，超过空闲阈值后进入 deep idle

#### Scenario: 无电池不阻止 idle

- **WHEN** Health HAL 报告电池不存在、仅外部供电
- **THEN** `DeviceIdleController` 的充电判据为 false，Doze 仍可正常进入

#### Scenario: 屏幕点亮退出 idle

- **WHEN** 屏幕点亮或用户产生交互
- **THEN** 设备立即退出 idle，恢复前台活动

### Requirement: 手动挂起必须保留

关闭自动挂起 MUST NOT 影响内核侧的挂起能力；具备 root 权限的调试入口仍可主动触发挂起。

#### Scenario: 手动挂起

- **WHEN** 在 root shell 执行 `echo mem > /sys/power/state`
- **THEN** 内核按当前的设备树与驱动配置进入挂起，电源键可唤醒

#### Scenario: 恢复自动挂起

- **WHEN** 产品需要重新启用自动挂起
- **THEN** 移除或调整该资源 overlay 并重新构建 system 镜像即可，不需要修改内核

### Requirement: 策略必须可审查

overlay MUST 位于设备目录并被产品显式引用，构建产物中框架资源的实际取值必须可通过运行时状态确认。

#### Scenario: 运行时确认

- **WHEN** 执行 `dumpsys power`
- **THEN** `mUseAutoSuspend` 为 `false`，`mHalAutoSuspendModeEnabled` 为 `false`

- **WHEN** 执行 `dumpsys deviceidle`
- **THEN** light idle 与 deep idle 均处于启用状态，且充电判据为 false
