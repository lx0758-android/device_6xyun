# device/led-indicator Specification

## Purpose

定义板载绿色 LED 的内核设备、默认触发与 Android lights HAL 的行为契约，保证灯在启动后可见、可被系统控制，且不会与内核触发互相覆盖。

## Requirements


### Requirement: LED 必须以 gpio-leds 注册且名字稳定

板载 LED MUST 通过 `gpio-leds` 注册为 LED class 设备，并在设备树中声明稳定的 `label`，使 sysfs 路径不随节点名变化。

#### Scenario: 启动后注册

- **WHEN** 系统启动完成
- **THEN** `/sys/class/leds/<label>/` 存在，包含 `brightness`、`max_brightness` 与 `trigger`

#### Scenario: 名字稳定性

- **WHEN** 设备树节点顺序或命名调整
- **THEN** LED 的 sysfs 名字仍由 `label` 决定，不发生变化

### Requirement: 默认触发必须在启动后生效

LED MUST 在启动后应用设备树声明的默认触发；触发所需模块 MUST 被构建并加载，不得出现"设备树写了触发但灯不亮"的情况。

#### Scenario: 默认触发绑定

- **WHEN** 系统启动完成并查询 LED 的 `trigger`
- **THEN** 默认触发出现在可用列表中且处于选中状态

#### Scenario: 触发模块缺失

- **WHEN** 默认触发的内核模块未构建或未加载
- **THEN** LED 仍按 `default-state` 保持基础亮度，不因触发缺失而不可用

### Requirement: Android 必须通过本地 lights HAL 暴露 LED

Android MUST 通过本地 AIDL `android.hardware.light.ILights/default` 服务控制该 LED；MUST NOT 使用不读写 sysfs 的示例实现冒充能力。

#### Scenario: 服务注册

- **WHEN** 系统启动完成
- **THEN** `service check android.hardware.light.ILights/default` 返回 found，实例名为 `default`

#### Scenario: 使用示例实现

- **WHEN** 产品只包含示例 lights 服务
- **THEN** 服务可以注册但灯不受控，不满足本要求

### Requirement: 能力声明必须与实现一致

lights HAL MUST 只声明实际存在的灯与能力；单色灯 MUST 声明为不支持动画与真实颜色，闪烁请求 MUST 返回未支持而不是假装成功。

#### Scenario: 能力查询

- **WHEN** 上层查询可用灯列表
- **THEN** 只返回一颗灯，类型为通知灯，最小更新周期为 0

#### Scenario: 不支持的请求

- **WHEN** 上层请求动画或多颗灯
- **THEN** 服务返回未支持，不产生部分生效的副作用

### Requirement: 通知灯语义与空闲恢复

收到通知时 HAL MUST 点亮 LED；通知清除后 MUST 恢复内核默认触发，不得让灯停留在通知状态。

#### Scenario: 通知到达

- **WHEN** 上层设置通知灯状态为非零亮度
- **THEN** LED 被点亮，亮度与请求一致

#### Scenario: 通知清除

- **WHEN** 上层将通知灯状态清零
- **THEN** LED 恢复设备树声明的默认触发

### Requirement: 不得与内核触发争用

HAL 在写亮度前 MUST 将 `trigger` 切换为 `none`，在恢复时 MUST 切回默认触发；HAL 异常退出时内核触发 MUST 保持有效。

#### Scenario: HAL 接管

- **WHEN** HAL 首次设置灯状态
- **THEN** `trigger` 切换为 `none`，随后亮度写入生效

#### Scenario: HAL 退出

- **WHEN** lights 服务停止或崩溃
- **THEN** LED 不处于失控状态，内核默认触发可继续工作
