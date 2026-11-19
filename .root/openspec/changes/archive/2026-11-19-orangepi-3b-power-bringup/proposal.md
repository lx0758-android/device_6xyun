# Proposal

## Why

设备已经能开机，但电源域相关的能力大多没有落地：电源服务仍是 AOSP 示例实现，模式、boost、调度提示全部空转；有线网络的 PHY 驱动没有作为板级模块交付，`eth0` 根本不存在。这两项决定了 UI 能不能获得性能支撑、网络能不能用。

板级的电源域同样没有被收口：电源键驱动虽然在配置与模块清单里，但休眠后能否唤醒系统没有任何证据；RK809 的供电、关机/重启与 RTC 唤醒没有契约；板载 LED 的内核配置缺失，设备树里的指示灯节点实际上不生效。三者共同决定设备是否像一个正常的电源域设备，而不是"能开机但按键和灯都不受控"的开发板。

还有一项事实没有进入系统视野：本机是直流直接供电、没有电池。当前 Health HAL 是示例实现，没有供电节点时不会报告外部供电在线，电池状态也没有明确契约，容易出现"未插电"的假象或对电量/温度的误报。

## What Changes

- **电源 HAL**：用本地 AIDL 实现替换 `power-service.example`，把模式落到 cpufreq，把 boost 与 ADPF hint 落到 uclamp，并如实声明支持能力。
- **挂起策略**：作为常供电设备，空闲时不进入系统挂起；同时启用 Doze 收敛熄屏后的后台活动。两项都由 framework 资源 overlay 固定，手动 `echo mem` 仍可用于内核验证。
- **有线网络**：板级内核以模块形式补充 Motorcomm YT8531C PHY 驱动，启动后注册 `eth0`；补 `android.hardware.ethernet.xml` 特性声明。
- **配套**：为 Power HAL 增加服务入口、init 权限与执行文件标签；产品包清单同步替换。
- **电源键**：沿用 RK809 的 `rk805-pwrkey` 链路，把 PMIC 父中断武装为唤醒源，使挂起状态下按键可以恢复系统；按键事件保持标准 `KEY_POWER`，不引入用户态轮询或模拟。
- **电源管理芯片**：以 RK809 作为供电、关机/重启与 RTC 唤醒的控制者，补齐 PMIC 中断唤醒链，并把供电轨与挂起状态纳入验收；不涉电池/充电与音频 codec。
- **指示灯**：补 `gpio-leds` 与 heartbeat 触发所需的内核配置，给设备树加稳定 label；同时提供本地 AIDL lights HAL，让 Android 在通知场景接管同一颗灯，空闲时恢复内核默认触发。
- **供电形态**：明确设备为直流直接供电、无电池；用本地 Health HAL 如实报告"外部供电在线、电池不存在"，不伪造电量、温度与健康度，也不触发低电关机。

明确不做：

- 不使用 init 常驻 wakelock 伪装"禁止休眠"；挂起策略通过可审查的资源 overlay 关闭框架自动挂起。
- 不在内核侧阻止 USB 会话期间的系统挂起：实测该方案会让控制器在 resume 后无法重新初始化（`DEPCFG` 超时），已回退。
- 不改动显示分辨率/EDID（归入 P1 显示变更）；
- 不引入 USB HAL、Wi-Fi/BT、音频或 GPU 能力；
- 不实现电池/充电（本板无电池，RK817 charger 未启用），不把 RK817 音频 codec 纳入本轮；
- 不在内核里伪造 `power_supply` 的电池或充电节点；
- 不实现软件定时强制断电，长按关机由 Android 框架与 PMIC 硬件行为分别负责。

## Capabilities

### New Capabilities

- `device/power-hal`：真实电源 HAL 的模式、boost 与 ADPF hint 行为。
- `device/suspend-policy`：空闲时默认不自动挂起、手动挂起保留的策略契约。
- `device/power-supply`：无电池、直接供电形态下的电源状态上报契约。
- `device/wired-ethernet`：板载 PHY 驱动、网络接口与特性声明。
- `device/led-indicator`：板载 LED 的内核设备与 Android lights HAL 行为。
- `kernel/power-key`：PMIC 电源键从硬件中断到 Android 输入事件、再到休眠唤醒的契约。
- `kernel/pmic`：RK809 的供电、关机/重启、PMIC 中断唤醒与 RTC 唤醒契约。

### Modified Capabilities

- `device/system-hal-set`：电源服务从"提供实现"收紧为"必须是真实实现，不得使用示例桩"。

## Impact

- 内核：板级 fragment、板级设备树、`rk805-pwrkey` 的唤醒路径、LED 模块与 label。
- 厂商实现：`vendor/6xyun/hardware/power/`、`vendor/6xyun/hardware/lights/`、`vendor/6xyun/hardware/health/`。
- 设备配置：`device/6xyun/orangepi_3b/ProductConfig.mk`、`device/6xyun/orangepi_3b/overlay/`、`device/6xyun/orangepi_3b/init/init.orangepi_3b.rc`、`device/6xyun/orangepi_3b/sepolicy/file_contexts`。
- 验证面：自动挂起已关闭（`dumpsys power`）、电源键唤醒、`eth0` 链路、Power HAL 注册与 hint、regulator 状态、关机/重启、RTC 闹钟、LED sysfs 与通知灯、`dumpsys battery` 的供电与电池状态。
