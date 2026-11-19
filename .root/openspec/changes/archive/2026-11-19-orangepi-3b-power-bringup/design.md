# Design

## Context

当前状态（见 proposal.md - Why）：

- 内核为 GKI mixed build，板级只有模块，三态选项必须写成 `=m`；
- 电源服务是 `android.hardware.power-service.example`，所有 hint 都是空操作；
- 板级 fragment 没有 PHY 驱动，`dwmac-rk` 的 `phy_connect` 失败，`eth0` 不注册。
- RK809（`rk3566-orangepi-3b.dtsi:219`）已经提供 regulator、RTC、clkout、pwrkey、restart/poweroff；电源键的 `KEY_POWER` 事件链路（`rk8xx-core.c` → `rk805-pwrkey.c`）与相关模块都已在配置和 `_ORANGEPI3B_MODULE_OUTS` 中，但从未验收。
- `rk805-pwrkey.c:88` 只调用 `device_init_wakeup()`，没有 `enable_irq_wake()`；`rtc-rk808.c:339` 调用了 `enable_irq_wake()`，但 `regmap_irq_set_wake()`（`regmap-irq.c:278`）只维护 PMIC 自己的 `wake_buf`，不会递归到父 IRQ。两者共用挂在 `gpio0` 上的 PMIC 父中断。
- LED 设备树节点存在（`gpio-leds`、`heartbeat`、`gpio0_PC0`），但 `CONFIG_LEDS_GPIO` 与 `CONFIG_LEDS_TRIGGER_HEARTBEAT` 都未配置，灯实际不会注册。
- Android 侧只有 `android.hardware.lights-service.example`，是纯内存实现，不读 `/sys/class/leds`；产品也未包含它。
- Health HAL 使用 `android.hardware.health-service.example`，底层 `BatteryMonitor` 在无 `power_supply` 设备时报告 `batteryPresent=false`，但 `chargerAcOnline` 也为 `false`，无法表达"直接供电"。

约束：

- 不通过 init 常驻 wakelock、不修改框架 suspend 策略；
- 不引入第三方二进制或私有 HAL；
- 板级新增内核能力必须是模块，不能改 GKI 的内建驱动集合（KMI 白名单成本另计）。

## Goals / Non-Goals

**Goals:**

- 电源 HAL 真实参与 cpufreq 与 uclamp 调度，且只声明自己支持的能力。
- `eth0` 在启动后存在并可用，应用层能看到以太网特性。
- 电源键在挂起状态下能唤醒系统，按键事件以标准 `KEY_POWER` 到达 Android。
- RK809 的供电、关机/重启与 RTC 唤醒可验证，PMIC 中断链完整。
- 板载 LED 默认可用，Android 能通过 lights HAL 在通知场景接管，空闲时回到内核默认触发。
- Android 明确知道设备"直接供电、没有电池"，不产生虚假电量或低电关机。

**Non-Goals:**

- 不追求 suspend 期间的极致功耗；接受"深睡时 USB 控制器掉电、唤醒后由 Android 重新枚举"的现状。
- 不在本轮处理 USB 跨系统挂起：内核没有 `CONFIG_USB_OTG_WAKEUPSOURCE`，且实测会话保活方案会在 resume 后让控制器无法重新初始化（`DEPCFG` 超时），已整体回退。
- 不为 Power HAL 引入 GPU/内存总线调频；RK3566 当前没有可用的 GPU 驱动。
- 不处理显示分辨率/EDID。
- 不做电池/充电与关机闹钟；不把 RK817 音频 codec 纳入本轮。
- 不用软件定时器实现长按强制断电。

## Decisions

### D1：USB 跨系统挂起不在本轮范围（已回退）

先查了能不能做：本内核树没有 `CONFIG_USB_OTG_WAKEUPSOURCE`（Rockchip 下游内核的选项，主线/GKI 没有），也没有可靠的 USB 控制器唤醒源实现。

实测结论：

- 本板 PMIC 在 suspend 时切断 `vdd_logic`（DCDC_REG1）与 `vcc_1v8`（DCDC_REG5），dwc3 又在 suspend 路径里执行 `dwc3_core_exit()`（关 PHY、关时钟、assert reset），所以每次深睡都会让 USB 控制器与 PHY 完全掉电；
- 掉电后 resume 的重新初始化在这块板子上不可靠：出现过 `failed to enable ep0out (init, -110)` / `(modify, -110)`（`DEPCFG` 命令超时），随后 `dwc3_gadget_suspend()` 的 `run_stop(false)` 也超时，返回 `-EAGAIN`，控制器彻底失效；
- 控制器失效后与用户态无关：`sys.usb.config=adb`、`sys.usb.state=adb`、`sys.usb.ffs.ready=1` 都正常，重设属性或重启 adbd 都不能恢复，只有重新 probe 或整机重启才行；
- 因此之前基于 `wakeup-source`、`pm_stay_awake`、`session_active` 守卫与 PD_PIPE `active-wakeup` 的方案整体回退，相关代码、设备树、绑定文档一并撤销。

后续如果在别的内核上要恢复这个能力，前提是：要么有 `USB_OTG_WAKEUPSOURCE` 这类硬件唤醒支持，要么先证明掉电后 resume 能稳定重建控制器。

### D2：电源 HAL 用本地 AIDL 实现，按能力边界落地

- `Mode`：`LOW_POWER`、`SUSTAINED_PERFORMANCE`、`FIXED_PERFORMANCE`、`INTERACTIVE`。前三个落到 `policy0` 的 governor / `scaling_max_freq`，`INTERACTIVE` 不改变持久配置。
- 上限不写死 kHz：内核只导出能力（`cpuinfo_max_freq` / `scaling_available_frequencies`），"低功耗上限"与"持续性能上限"是产品策略。HAL 按 50% / 80% 的比例算出目标值，再从 OPP 表向下对齐到真实档位；读不到 OPP 表时退回比例值，由内核 verify 阶段向下对齐。启动日志打印 `cpufreq max=... low_power=... sustained=... opp_count=...`，模式切换后读回 `scaling_max_freq` 记录实际生效值。
- 依赖（缺一即静默失效，`/sys/devices/system/cpu/cpufreq/` 为空）：
  1. `CONFIG_CPUFREQ_DT_PLATDEV`（bool）负责创建 `cpufreq-dt` 平台设备；mixed build 下板级 `=y` 会被丢弃，必须落在 `gki_defconfig`。
  2. `cpufreq-dt.ko` 提供驱动本体，随板级模块清单交付。
  3. CPU 时钟来自 SCMI（`rk356x-base.dtsi` 的 `clocks = <&scmi_clk 0>`），因此需要 `CONFIG_COMMON_CLK_SCMI=y` 注册时钟提供者；缺失时 `clk_get()` 永久返回 `-EPROBE_DEFER`，平台设备存在、驱动已注册但始终不绑定。
- `Boost`：`INTERACTION`、`DISPLAY_UPDATE_IMMINENT`，通过每 CPU 的 `uclamp.min` 施加有时限的提升，到期自动回落。
- `HintSession`：对会话线程使用 `sched_setattr(SCHED_FLAG_UTIL_CLAMP)`，`updateTargetWorkDuration` 与 `reportActualWorkDuration` 调整 util 下限；`setThreads`、`pause/resume/close` 完整实现。
- `getSupportInfo` 与 `isModeSupported` / `isBoostSupported` 必须一致，不声明未实现的项。

备选：

- 继续用 example：框架认为所有 hint 都支持但实际无效，属于"假能力"，拒绝。
- 引入 libperfmgr：需要额外配置模型与 root 权限，当前收益不足以抵消复杂度。

### D3：PHY 驱动按板级模块交付

- YT8531C 由 `motorcomm.c` 支持（`PHY_ID_YT8531 0x4f51e91b`），在板级 fragment 中声明 `CONFIG_MOTORCOMM_PHY=m`；
- 不改 DT：v1.1 的 `gmac1`、`mdio1`、PHY reset GPIO 已经存在；
- 不改 GKI 内建集合：符合 `kernel/config-layering` 的分层约束。

### D4：sysfs 权限与 SELinux 标签随服务一起交付

- Power HAL 以 `system` 身份运行，需要写 `policy0/scaling_*` 与每 CPU 的 `uclamp.min`；由 init 在 `on boot` 阶段 chown/chmod，避免为了省事让 HAL 以 root 运行。
- 服务二进制使用 `hal_power_default_exec` 标签，单独在设备 `file_contexts` 中声明。
- 开机日志暴露了两处 AOSP 策略缺口，已在设备 sepolicy 补齐：
  - `/sys/class/leds/*` 只是 symlink，真实 inode 在 `/sys/devices/platform/leds/` 下被标为通用 `sysfs`，`hal_light_default` 的 trigger/brightness 写会被拒；设备 `genfs_contexts` 增加 `genfscon sysfs /devices/platform/leds u:object_r:sysfs_leds:s0`。
  - `PowerHintSession` 对应用线程做 `sched_setattr`，AOSP 只给 `system_server`/`performanced` 开了跨域 `setsched`；设备策略增加 `allow hal_power_default appdomain:process setsched`，并补 `sysfs_devices_system_cpu` 的读写权限，覆盖 `scaling_*` 与 `uclamp.min`。
- 跨域 `setsched` 还有一道 MLS 约束，仅补 allow 不够：plat 策略中
  `(mlsconstrain (process (… setsched …)) (or (eq l1 l2) (eq t1 mlstrustedsubject)))`，
  HAL 域在 `s0`，应用线程在 `s0:c512,c768`，`eq l1 l2` 不成立，因此必须把
  `hal_power_default` 标为 `mlstrustedsubject`。AOSP 的 `performanced` 采用同一口径
  （`system/sepolicy/public/performanced.te:2`）。

厂商实现的目录约定：

- 源码统一放 `vendor/6xyun/hardware/<component>/`，不按设备名分组；
- 产品配置在 `device/6xyun/orangepi_3b/`，与厂商实现分离。

HAL 配置文件的命名规范：

- init rc 与 VINTF fragment 的文件名 MUST 与模块名一致，例如 `android.hardware.power-service.6xyun.rc` 与 `android.hardware.power-service.6xyun.xml`；
- 服务名使用 `vendor.<hal>-default`，例如 `vendor.power-default`；
- 不使用 `power-orangepi_3b.rc` 这类与模块名脱节的缩写，后续 lights、health 与 Codec2 同样遵循。

### D5：电源键与 PMIC 唤醒链统一在 PMIC 父中断武装

事实：

- 电源键已由 `rk8xx-core.c` 的 `rk817s[]` 注册为 `rk805-pwrkey` 平台设备，驱动上报 `KEY_POWER`；
- `rk805-pwrkey.c` 只有 `device_init_wakeup(dev, true)`，没有 `enable_irq_wake()`，也没有 PM ops；
- `rtc-rk808.c` 在 suspend 中调用 `enable_irq_wake()`，但 `regmap_irq_set_wake()` 只改 PMIC 的 `wake_buf`，不会把唤醒传递到父 IRQ；
- PMIC 的父中断是 `gpio0` 上的电平中断，`gpio-rockchip.c:553` 已实现 `irq_set_wake`；
- PMIC 节点原本就带 `wakeup-source`（`rk3566-orangepi-3b.dtsi:235`），而 I2C 核心在 `i2c-core-base.c:552-567` 已经对带 `wakeup-source` 的 client 执行 `device_init_wakeup()` 与 `dev_pm_set_wake_irq(client->irq)`，父中断的武装不需要驱动重复实现。

方案：

- `rk8xx-i2c` 不做修改：I2C 核心已完成 `device_init_wakeup()` + `dev_pm_set_wake_irq()`，驱动里再调一次会触发 `dev_pm_attach_wake_irq()` 的 `wake irq already initialized` 告警并返回 `-EEXIST`（实测见启动日志），属于重复配置；
- 在 `rk805-pwrkey` 增加 suspend/resume，按 `device_may_wakeup()` 调用 `enable_irq_wake()` / `disable_irq_wake()`，由 `regmap-irq` 负责子中断的 mask；
- 不修改 `regmap-irq` 核心，也不在用户态加 wakelock。

备选：

- 改 `regmap-irq` 让 `irq_set_wake` 递归父 IRQ：影响所有使用 regmap-irq 的设备，拒绝；
- 只改电源键驱动：父 IRQ 仍未武装，按键在 suspend 后仍然无效；
- 用户态轮询 GPIO：需要常驻进程与额外权限，且无法在 suspend 中运行，拒绝。

### D6：LED 以内核 `gpio-leds` 为默认，Android 用本地 lights HAL 接管

内核：

- fragment 增加 `CONFIG_LEDS_GPIO=m` 与 `CONFIG_LEDS_TRIGGER_HEARTBEAT=m`，并把 `drivers/leds/leds-gpio.ko`、`drivers/leds/trigger/ledtrig-heartbeat.ko` 登记到 `_ORANGEPI3B_MODULE_OUTS`；
- 设备树给 `led-0` 增加稳定 `label`（取 `android-status`，不绑定产品名），保留 `default-state = "on"` 与 `linux,default-trigger = "heartbeat"`，避免 sysfs 名字随节点名变化；
- `BoardConfig.mk` 已按内核输出目录打包并加载 `modules.load`，新增模块无需额外 init 脚本。

用户态：

- 在 `vendor/6xyun/hardware/lights/` 实现本地 AIDL lights HAL，复用 `android.hardware.light-V3-ndk` 与 `libbinder_ndk`；
- 只声明一颗灯，类型为 `NOTIFICATIONS`，`minUpdatePeriodMillis = 0`（不支持动画），`getLights()` 与 `setLightState()` 的能力保持一致；
- 写 brightness 前把 `/sys/class/leds/<label>/trigger` 切到 `none`，通知清除（颜色为 0 且无闪烁）后切回 `heartbeat`；
- 颜色按亮度取最大值映射到 `brightness`（单色灯不支持真实颜色），闪烁请求在本期不支持，返回未支持而不是假装成功；
- `hal_light` 域已允许读写 `sysfs_leds`，`hal_light_default_exec` 标签已存在，只需在设备 `file_contexts` 增加本地二进制路径。

备选：

- 只做内核 trigger：改动最小，但 Android 无法控制，不满足"设备能被系统感知"的目标；
- 直接复用 `lights-service.example`：它是纯内存实现，不读写 sysfs，等于假能力，拒绝；
- 把灯注册为电池灯：本机无电池，语义不成立，拒绝。

### D7：RTC 唤醒只做设备级验证，不接 Android 闹钟

- Android 的 `AlarmManager` 使用 timerfd，不依赖硬件 RTC；RTC 唤醒是设备级能力，用于验证 PMIC 中断链与低层电源管理；
- 验证方式：写 `/sys/class/rtc/rtc0/wakealarm`，`echo mem > /sys/power/state`，到点自动恢复；
- 不做关机闹钟：需要 bootloader/PMIC 在关机态维持 RTC 与上电时序，超出本轮范围。

### D8：直接供电、无电池由本地 Health HAL 如实上报

事实：

- 本板没有电池，RK817 charger 未启用（`CONFIG_CHARGER_RK817` 不存在）；
- Health HAL 的 `BatteryMonitor` 在找不到 `power_supply` 电池设备时，`mBatteryDevicePresent` 保持 `false`，因此 `batteryPresent=false`；
- 但没有 AC/USB 供电节点时，`chargerAcOnline` 也为 `false`，`dumpsys battery` 会显示"未插电"；
- `BatteryService.shouldShutdownLocked()` 在 `batteryPresent=false` 时直接返回 false，不会低电关机。

方案：

- 不新增伪造的 `power_supply` 内核节点；
- 在 `vendor/6xyun/hardware/health/` 实现本地 Health HAL，复用 `libhealth_aidl_impl`（`vendor: true`）与 `Health` 基类，覆盖 `UpdateHealthInfo()`：
  - `chargerAcOnline = true`，其余 charger 类型为 false；
  - `batteryPresent = false`；
  - `batteryStatus = NOT_CHARGING`；
  - `batteryLevel = 0`，`batteryCapacityLevel = UNSUPPORTED`；
  - 电压、电流、温度、健康度等保持未知/0，不编造读数；
- 模块名 `android.hardware.health-service.6xyun`，VINTF 声明 `android.hardware.health` 版本 5 的 `IHealth/default`；
- 替换产品中的 `android.hardware.health-service.example`，沿用 `hal_health_default_exec` 标签并在 `file_contexts` 增加路径。

备选：

- 继续用 example：`batteryPresent=false` 是正确的，但"未插电"是错误表述，且示例实现不是产品契约；
- 内核加固定 `ac` power_supply 驱动：能表达在线，但为一块没有检测电路的板子新增假设备，维护成本与误导性都更高；
- 关闭 Health HAL：会导致 `BatteryService` 初始化失败，不可行。

### D9：常供电设备采用"不休眠 + Doze"策略

设计规格：本机为常供电设备，空闲时不进入系统挂起；同时启用 Doze，让熄屏后的后台活动逐级收敛。两项都由 framework 资源 overlay 固定，不依赖上层设置，也不引入常驻 wakelock。

事实链：

- `config_useAutoSuspend` 默认为 `true`（`frameworks/base/core/res/res/values/config.xml:7805`）；
- `PowerManagerService` 在构造时读取该值（`PowerManagerService.java:1305`），`setHalAutoSuspendModeLocked()` 在 `mUseAutoSuspend == false` 时直接返回（`PowerManagerService.java:4346-4349`），因此不会调用 `nativeSetAutoSuspend(true)`；
- `libsuspend` 的挂起线程通过 `/sys/power/wakeup_count` + `/sys/power/state` 进入 deep suspend（`system/core/libsuspend/autosuspend_wakeup_count.cpp`），这是 `PM: suspend entry` 的来源；
- Doze（device idle）由 `config_enableAutoPowerModes` 控制，默认 `false`（`config.xml:262`）；`DeviceIdleController` 用它初始化 `mLightEnabled` / `mDeepEnabled`（`DeviceIdleController.java:2674`）；
- 进入 idle 的充电判据是 `BatteryManager.EXTRA_PRESENT && EXTRA_PLUGGED != 0`（`DeviceIdleController.java:690-693`），本机 Health HAL 报告电池不存在，因此该判据为 false，Doze 不会被充电状态挡住。

方案：

- 在 `device/6xyun/orangepi_3b/overlay/frameworks/base/core/res/res/values/config.xml` 设置：
  - `config_useAutoSuspend=false`
  - `config_enableAutoPowerModes=true`
- 在 `ProductConfig.mk` 用 `PRODUCT_PACKAGE_OVERLAYS` 把 overlay 注入 framework-res 的编译；
- 结果：框架不启动自动挂起，熄屏后仍保持运行；Doze 在熄屏 4 分钟后进入 light idle，随后按 light idle 窗口进入 deep idle（默认阈值见 `config_device_idle.xml`）。手动 `echo mem > /sys/power/state` 仍然有效。

备选与否决：

- 内核侧会话守卫：已实测会在 resume 后把控制器卡死（`DEPCFG` 超时），已回退；
- init/服务常驻 wakelock：不可审查，也无法解决控制器掉电；
- 保留 `vdd_logic`/`vcc_1v8` 常供：静态抬高所有场景功耗，且还要处理 TF-A 与 PHY 的恢复顺序，成本更高。

取舍：关闭自动挂起后，熄屏功耗仍接近运行态；Doze 只能收敛后台活动，不能把 AP 断电。若后续有可靠的 USB 唤醒方案，删除 `config_useAutoSuspend` 一行即可恢复自动挂起，Doze 可继续保留。

## 验证工具与口径

- 本树（Android 17）的 `lshal` 是 HIDL 专用工具：`frameworks/native/cmds/lshal/Lshal.cpp:61-63` 的 usage 明确写着 "List and debug HIDL HALs. (for AIDL HALs, see `dumpsys`)"。因此 AIDL HAL 的注册验证用 `service check <instance>` 或 `service list`，`lshal | grep` 在本树必然为空，不能作为失败判据。
- 判断设备上的策略是否已更新，优先看实际标签而不是镜像时间戳：`ls -Z /sys/devices/platform/leds/leds/<label>/` 若显示 `sysfs_leds` 说明新 `genfs_contexts` 已生效。
- `dumpsys deviceidle get charging` 在无电池设备上恒为 `false`：Health HAL 上报 `batteryPresent=false`，Doze 的充电判据是"有电池且插电"，因此 AC 在线不会阻止 idle。
- `/sys/devices/system/cpu/cpufreq/` 为空表示 cpufreq 没有注册（平台设备缺失，或 OPP/时钟不可用），不要误判成 sysfs 权限问题；此时 `cmd power set-mode` 不会产生任何效果。
- 区分「平台设备缺失」和「驱动未绑定」：`/sys/bus/platform/devices/cpufreq-dt` 存在、`/sys/bus/platform/drivers/cpufreq-dt/` 下没有同名符号链接，说明设备已创建但 probe 未成功；再看 `/sys/kernel/debug/devices_deferred` 是否列出 `cpufreq-dt`，若列出通常是时钟或 regulator 提供者尚未就绪。
- `cmd power set-mode N` 在本树只等价于省电模式开关（`N == 1` 开启，其余关闭，见 `PowerManagerShellCommand.java:119-130`），不会直接调用 HAL 的 `setMode(LOW_POWER)`；且省电模式在 `mIsPowered == true` 时禁止手动开启（`BatterySaverStateMachine.java:643-664`），本机 Health HAL 恒报 AC 在线，因此该命令始终是空操作。验证 HAL 模式应直接调用 `IPowerManager.setPowerModeChecked`：
  - `service call power 7 i32 1 i32 1` → `LOW_POWER`
  - `service call power 7 i32 2 i32 1` → `SUSTAINED_PERFORMANCE`
  - `service call power 7 i32 3 i32 1` → `FIXED_PERFORMANCE`（或 `cmd power set-fixed-performance-mode-enabled true`）
  - 第 7 号事务对应 `IPowerManager.aidl` 中第 7 个方法 `setPowerModeChecked`；模式值与 `Mode.aidl` 一致：LOW_POWER=1、SUSTAINED_PERFORMANCE=2、FIXED_PERFORMANCE=3。

## Risks / Trade-offs

- [关闭自动挂起后待机功耗等于运行态] → 这是常供电设备的设计取舍：Doze 只收敛后台活动，不切断 AP。若后续出现可靠的 USB 唤醒方案，删除对应 overlay 项即可恢复自动挂起。
- [Doze 会影响后台实时性] → 需要常驻长连接或定时任务的应用要加入 power whitelist，或按需调整 `device_idle_constants`；本轮只启用默认阈值。
- [Power HAL 的 cpufreq 上限可能与热节流叠加] → 只设置 `scaling_max_freq`，不覆盖 thermal 的 cooling 策略；温度相关行为仍由 thermal 驱动决定。
- [uclamp 对老调度器行为有限] → 当前 GKI 已启用 `CONFIG_UCLAMP_TASK`，若实测无效果，退回只做 boost 的保守实现。
- [PHY 型号判断错误] → v1.1 原理图为 YT8531C；若实测 PHY ID 不符，按 `dmesg` 中的 PHY ID 调整驱动模块。
- [PMIC 父中断武装失败] → 电源键与 RTC 仍能上报事件与设置闹钟，但 suspend 后无法唤醒；父中断武装由 I2C 核心负责，`rk805-pwrkey` 的 suspend/resume 可单独回退。
- [电源键驱动没有长按语义] → 长按关机由 Android 框架计时，硬件强制断电由 PMIC 决定；规格明确不由软件实现 8 秒断电。
- [LED 与通知灯争用同一颗灯] → HAL 在接管前切 trigger 到 `none`，空闲时切回 `heartbeat`；HAL 异常退出时内核 trigger 保持，灯不会失控。
- [单色灯无法表达通知颜色] → 只声明 `NOTIFICATIONS` 与亮度，不声明动画与真实颜色；闪烁请求按未支持返回。
- [休眠时 LED 供电不确定] → 供电来自 `vcc3v3_sys` 与 GPIO0 状态，不承诺休眠期间常亮，验收只看运行态。
- [Health HAL 固定 AC 在线与未来硬件变化不符] → 当前硬件确为直流直接供电；若后续引入电池或 USB-PD，需要重新评估并更新本契约。
- [依赖 AOSP health 内部库] → 只复用 `libhealth_aidl_impl` 的 `Health` 基类并覆盖 `UpdateHealthInfo()`，不复制 `BatteryMonitor` 逻辑，降低升级耦合。
- [`hal_power_default` 标记为 `mlstrustedsubject`] → 该域不再受 MLS 约束，换来跨域给应用线程设 uclamp 的能力；这是 AOSP `performanced` 的同一口径。若后续不接受该面，应改为只做整机 `uclamp.min` boost，放弃 per-thread hint session。

## Migration Plan

1. 内核侧：fragment + DT（LED/PMIC）+ PMIC 唤醒链 + LED 模块，先单独构建验证模块与启动。
2. 设备侧：Power HAL、lights HAL、health HAL 的替换与权限/标签，以及 framework 资源 overlay（关闭自动挂起），验证服务注册、能力声明与 `dumpsys power` 的 `mUseAutoSuspend`。
3. 联调：熄屏静置确认不再出现 `PM: suspend entry`；`echo mem > /sys/power/state` 触发挂起，分别用电源键与 RTC 闹钟验证唤醒；`ifconfig` 验证 `eth0`；`dumpsys battery` 验证供电与无电池状态。
4. 任一步失败可单独回退：内核改动集中在 fragment、DT 与三处驱动分支；Power/lights/health HAL 回退只需把产品包换回对应示例实现。

## Open Questions

- 默认 trigger 保留 `heartbeat` 还是改为 `default-on`，取决于产品对"运行指示"的偏好。
- 单色灯是否需要在通知之外承担"系统异常"提示；若需要，应新增独立语义而不是复用通知灯。
