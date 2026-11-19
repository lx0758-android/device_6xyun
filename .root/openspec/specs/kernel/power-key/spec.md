# kernel/power-key Specification

## Purpose

定义 RK809 电源键从 PMIC 中断到 Android 输入事件的契约，以及系统挂起状态下电源键作为唤醒源的行为，避免"按键能上报但唤不醒"的半可用状态。

## Requirements


### Requirement: 电源键事件必须由 PMIC 中断驱动

电源键 MUST 通过 PMIC 的中断路径上报标准 `KEY_POWER` 事件，不得使用 GPIO 轮询、用户态模拟或定时器伪造按键。

#### Scenario: 按下与抬起

- **WHEN** 用户按下并释放电源键
- **THEN** 输入子系统分别上报 `KEY_POWER` 按下与抬起事件，Android 能识别为一次完整按键

#### Scenario: 设备树与驱动链路审查

- **WHEN** 检查电源键的设备树与驱动
- **THEN** PMIC 节点声明中断，MFD 注册电源键子设备，驱动注册输入设备并上报 `KEY_POWER`

#### Scenario: 禁止用户态模拟

- **WHEN** 审查系统中是否存在模拟电源键的常驻进程、脚本或属性开关
- **THEN** 不存在此类实现

### Requirement: 电源键必须能作为系统唤醒源

电源键 MUST 在系统挂起状态下唤醒系统；唤醒能力不可用时 MUST 记录并使挂起流程继续，不得因唤醒配置失败而阻塞休眠。

#### Scenario: 挂起后按键唤醒

- **WHEN** 系统已进入 suspend，用户短按电源键
- **THEN** 系统退出 suspend 并恢复交互，挂起成功计数增加

#### Scenario: 唤醒能力不可用

- **WHEN** 电源键中断无法被配置为唤醒源
- **THEN** 系统仍可正常挂起与恢复，日志记录唤醒能力缺失，按键在运行态仍可上报

### Requirement: 软件不得实现定时强制断电

电源键的长按语义 MUST 由 Android 框架的关机流程与 PMIC 的硬件行为分别负责；软件不得以定时器实现"长按若干秒强制断电"。

#### Scenario: 长按关机

- **WHEN** 用户长按电源键
- **THEN** 由 Android 框架弹出关机/重启流程，不由电源键驱动计时

#### Scenario: 硬件强制断电

- **WHEN** 用户持续按住电源键超过 PMIC 设定的硬件阈值
- **THEN** 断电由 PMIC 完成，系统软件不参与
