# kernel/pmic Specification

## Purpose

定义 RK809 作为系统供电、关机/重启、PMIC 中断唤醒与 RTC 唤醒控制者的行为契约，保证电源域的关键能力可验证、可回退，且不声明不存在的硬件能力。

## Requirements


### Requirement: 供电轨必须按设备树注册并保持关键轨

RK809 的供电轨 MUST 按设备树定义注册，标记为 `always-on`/`boot-on` 的轨道 MUST 保持供电；挂起状态 MUST 与各轨的 `regulator-state-mem` 声明一致。

#### Scenario: 启动后的供电状态

- **WHEN** 系统启动完成并查询 regulator 状态
- **THEN** 设备树中声明的轨道全部注册，关键轨处于使能状态，电压在声明范围内

#### Scenario: 挂起时的供电状态

- **WHEN** 系统进入 suspend
- **THEN** 声明为 `on-in-suspend` 的轨道保持供电，声明为 `off-in-suspend` 的轨道关闭

### Requirement: 关机与重启必须落到 PMIC

系统关机与重启 MUST 通过 PMIC 的 `system-power-controller` 路径完成，不得停留在 PSCI 或依赖看门狗复位。

#### Scenario: 关机

- **WHEN** 上层请求关机
- **THEN** 系统完成停机流程后由 PMIC 切断供电

#### Scenario: 重启

- **WHEN** 上层请求重启
- **THEN** 系统通过 PMIC 复位，启动流程重新开始

### Requirement: PMIC 中断必须能作为系统唤醒源

PMIC 的父中断 MUST 在挂起时被武装为唤醒源，供电源键与 RTC 等子设备使用；武装失败 MUST NOT 阻塞挂起。

#### Scenario: 子设备共享唤醒链

- **WHEN** 电源键或 RTC 闹钟在挂起期间触发
- **THEN** PMIC 父中断被唤醒，子设备获得中断并处理事件

#### Scenario: 父中断武装失败

- **WHEN** PMIC 父中断无法配置为唤醒源
- **THEN** 系统仍可挂起，日志记录失败原因，运行态功能不受影响

### Requirement: RTC 必须支持闹钟唤醒

RTC MUST 支持设置闹钟并在系统挂起时于指定时间唤醒设备；未设置闹钟时 MUST NOT 产生误唤醒。

#### Scenario: 定时唤醒

- **WHEN** 设置未来的 RTC 闹钟后系统进入 suspend
- **THEN** 到达设定时间时系统自动恢复

#### Scenario: 未设置闹钟

- **WHEN** 没有设置 RTC 闹钟且系统进入 suspend
- **THEN** RTC 不触发唤醒

### Requirement: 不得声明不存在的电池或充电能力

PMIC 与上层 MUST NOT 声明本机不存在的电池、充电或电量检测能力；无电池时 MUST 由上层按"直接供电"语义上报。

#### Scenario: 无电池硬件

- **WHEN** 检查内核是否存在电池或充电 `power_supply` 设备
- **THEN** 不存在伪造的电池节点，PMIC 的 charger 子设备不对外声明可用

#### Scenario: 能力声明审查

- **WHEN** 审查产品的电源能力声明
- **THEN** 不包含电池容量、充电状态或充电电流等本机不具备的能力
