# Tasks

## 1. 电源 HAL

- [x] 1.1 在 `vendor/6xyun/hardware/power/` 实现 AIDL Power HAL：模式落到 cpufreq、boost 落到 uclamp、hint session 落到线程 uclamp；rc 与 VINTF fragment 命名为 `android.hardware.power-service.6xyun.rc` / `.xml`，服务名 `vendor.power-default`
- [x] 1.2 在 `device/6xyun/orangepi_3b/ProductConfig.mk` 用真实实现替换 `android.hardware.power-service.example`，并确认厂商实现目录在产品 Soong 命名空间中可见
- [x] 1.3 init 为 `policy0/scaling_*` 与每 CPU `uclamp.min` 设置 system 可写权限
- [x] 1.4 为新服务二进制补 SELinux 执行文件标签
- [x] 1.5 验证服务与 VINTF 注册：`dumpsys power` 无 HAL 缺失告警，`service check android.hardware.power.IPower/default` 返回 found（本树 `lshal` 只枚举 HIDL，AIDL 服务不能用它验证）
- [x] 1.6 验证模式生效：`service call power 7 i32 1 i32 1`（LOW_POWER）后 `scaling_max_freq=816000`，`i32 2 i32 1`（SUSTAINED_PERFORMANCE）后 `1416000`，关闭后回到 `1800000`；`cmd power set-fixed-performance-mode-enabled true` 使 `scaling_governor=performance`，关闭恢复 `schedutil`；全程 `hal_power_default` 无 avc
- [x] 1.7 补 `hal_power_default` 的 SELinux 权限：跨域 `setsched`（ADPF hint session，需同时满足 MLS 约束，故标记 `mlstrustedsubject`）与 `sysfs_devices_system_cpu` 读写（cpufreq / uclamp.min）
- [x] 1.8 在 `gki_defconfig` 打开 `CONFIG_CPUFREQ_DT_PLATDEV`：该 bool 在板级 mixed build 会被丢弃，缺失时 `cpufreq-dt.ko` 虽加载但没有平台设备，`/sys/devices/system/cpu/cpufreq` 为空
- [x] 1.9 在 `gki_defconfig` 打开 `CONFIG_COMMON_CLK_SCMI`：CPU 时钟来自 `scmi_clk`，缺少时钟提供者时 `cpufreq-dt` 平台设备存在、驱动已注册但永久 `-EPROBE_DEFER`，不产生 policy

## 2. 挂起策略

- [x] 2.1 新增 framework-res 资源 overlay：`config_useAutoSuspend=false`（设备不休眠）与 `config_enableAutoPowerModes=true`（启用 Doze），通过 `PRODUCT_PACKAGE_OVERLAYS` 注入产品
- [x] 2.2 构建 system 并确认覆盖生效：`dumpsys power` 中 `mUseAutoSuspend=false`、`mHalAutoSuspendModeEnabled=false`
- [x] 2.3 验证空闲不挂起：熄屏静置后 `dmesg | grep -c "PM: suspend entry"` 不再增长且 adb 保持；手动 `echo mem > /sys/power/state` 仍可进入挂起
- [x] 2.4 验证 Doze 生效：`dumpsys deviceidle` 中 light/deep idle 均为 enabled，`get charging` 为 false；熄屏后按阈值进入 light idle → deep idle，点亮屏幕后退出

## 3. 有线网络

- [x] 3.1 板级 fragment 以模块形式补充 Motorcomm YT8531C PHY 驱动
- [x] 3.2 产品拷贝 `android.hardware.ethernet.xml`，向应用声明以太网特性（`ProductConfig.mk` 已拷贝到 `$(TARGET_COPY_OUT_VENDOR)/etc/permissions/`）
- [x] 3.3 验证接口与链路：`ifconfig` 出现 `eth0`，插网线后获得地址并可访问外部网络

## 4. 电源键与 PMIC

- [x] 4.1 记录现有链路基线：RK809 的 `rk817s[]` cells、`rk805-pwrkey` 驱动、fragment 与模块清单，确认不重复实现
- [x] 4.2 确认 PMIC 父中断的武装路径：PMIC 节点自带 `wakeup-source`，I2C 核心在 `i2c-core-base.c:552-567` 已调用 `device_init_wakeup()` 与 `dev_pm_set_wake_irq()`；`rk8xx-i2c` 不重复设置（否则 `dev_pm_attach_wake_irq()` 报 `wake irq already initialized` 并返回 `-EEXIST`）
- [x] 4.3 `rk805-pwrkey` 增加 suspend/resume，按 `device_may_wakeup()` 启停 IRQ 唤醒，不修改 `regmap-irq` 核心
- [x] 4.4 构建内核，确认 `rk805-pwrkey.ko`、`rk8xx-core.ko`、`rk8xx-i2c.ko`、`rtc-rk808.ko` 均在模块清单且无未解析符号：四个模块均随 `vendor_ramdisk` 交付，启动日志显示依次加载成功（无符号报错），PMIC/按键/RTC 链路已建立
- [x] 4.5 验证按键事件：`/dev/input` 出现 `rk805 pwrkey`，`getevent -l` 能看到 `KEY_POWER` 按下与抬起，`dumpsys input` 正常识别设备
- [x] 4.6 验证休眠唤醒：`echo mem > /sys/power/state` 后短按电源键恢复，`/sys/power/suspend_stats/success` 计数增加
- [x] 4.7 验证 PMIC 供电：`regulator_summary` 电压与 always-on/boot-on 符合设备树，挂起前后 `dmesg` 无 regulator 报错
- [x] 4.8 验证关机/重启：`reboot -p` 完全断电，`reboot` 经 PMIC 复位，不依赖看门狗
- [x] 4.9 验证 RTC 唤醒：写 `/sys/class/rtc/rtc0/wakealarm` 后挂起，到点自动恢复

## 5. LED 与 lights HAL

- [x] 5.1 板级 fragment 增加 `CONFIG_LEDS_GPIO=m` 与 `CONFIG_LEDS_TRIGGER_HEARTBEAT=m`
- [x] 5.2 将 `drivers/leds/leds-gpio.ko` 登记到 `_ORANGEPI3B_MODULE_OUTS`；`ledtrig-heartbeat` 依赖的 KMI 符号不可用，改为内建到 `gki_defconfig`
- [x] 5.3 设备树为 `led-0` 增加稳定 `label`，保留 `default-state` 与 `linux,default-trigger`
- [x] 5.4 验证内核 LED：`/sys/class/leds/<label>/` 存在，`trigger` 中 heartbeat 已绑定，亮度可控
- [x] 5.5 在 `vendor/6xyun/hardware/lights/` 实现 AIDL lights HAL：单灯、`NOTIFICATIONS`、无动画，写 brightness 前切 trigger 到 `none`，空闲恢复 heartbeat
- [x] 5.6 在 `device/6xyun/orangepi_3b/ProductConfig.mk` 加入 HAL 包，补服务 rc（`android.hardware.lights-service.6xyun.rc`）、VINTF 声明（`android.hardware.lights-service.6xyun.xml`），并在 `device/6xyun/orangepi_3b/sepolicy/file_contexts` 增加本地二进制的 `hal_light_default_exec` 标签
- [x] 5.7 验证 HAL：`service check android.hardware.light.ILights/default` 返回 found；通知触发时灯被点亮，通知清除后回到 heartbeat
- [x] 5.8 把 LED 真实 sysfs 路径标为 `sysfs_leds`：`genfscon sysfs /devices/platform/leds u:object_r:sysfs_leds:s0`

## 6. 直接供电与无电池

- [x] 6.1 在 `vendor/6xyun/hardware/health/` 实现本地 Health HAL：复用 `libhealth_aidl_impl`，覆盖 `UpdateHealthInfo()` 报告 AC 在线、电池不存在、容量等级 `UNSUPPORTED`
- [x] 6.2 在 `device/6xyun/orangepi_3b/ProductConfig.mk` 用本地实现替换 `android.hardware.health-service.example`，补服务 rc（`android.hardware.health-service.6xyun.rc`）、VINTF（`android.hardware.health-service.6xyun.xml`，`android.hardware.health` 版本 5），并在 `device/6xyun/orangepi_3b/sepolicy/file_contexts` 增加 `hal_health_default_exec` 标签
- [x] 6.3 验证状态：`dumpsys battery` 显示 `AC powered: true`、`USB powered: false`、`present: false`、`level: 0`、容量等级为 `UNSUPPORTED`
- [x] 6.4 验证无虚假读数：电压、电流、温度、健康度不出现编造值，`BatteryManager` 查询不返回错误容量
- [x] 6.5 验证不会低电关机：长时间待机与多次重启后系统保持运行，`logcat` 无低电关机请求

## 7. 构建与整体验证

- [x] 7.1 内核与镜像构建通过，`vendor_ramdisk` 模块清单包含 `motorcomm.ko`、`leds-gpio.ko`、`cpufreq-dt.ko`、`fan53555.ko` 与 PMIC 相关模块（`rk805-pwrkey`/`rk8xx-core`/`rk8xx-i2c`/`rtc-rk808`），启动日志全部加载成功；`ledtrig-heartbeat` 按 5.2 内建进 GKI，不再以模块形式交付
- [x] 7.2 电源键与 RTC 两种唤醒均实测通过，且互不干扰
- [x] 7.3 LED 默认指示与通知接管均验证通过，HAL 退出后内核 trigger 仍生效
- [x] 7.4 `dumpsys battery` 与 SystemUI 对"直接供电、无电池"的表述一致
- [x] 7.5 `openspec validate orangepi-3b-power-bringup --strict` 通过

## Workflow follow-up

- GKI 模块的 KMI 符号与 `module_outs` 漏项用 `device/6xyun/common/tools/update_kmi_symbols.py` 从构建日志提取：脚本自动把缺失符号追加到 `gki/aarch64/symbols/6xyun`，并打印需要加入 `_ORANGEPI3B_MODULE_OUTS` 的模块路径。
- 本变更通过后归档；`specs/kernel/power-key`、`specs/kernel/pmic`、`specs/device/power-hal`、`specs/device/power-supply`、`specs/device/led-indicator`、`specs/device/wired-ethernet` 成为对应能力基线。
- 后续独立变更（按 2026-11-18 调整后的优先级）：
  - **P1 GPU 与显示**：Panfrost 内核驱动 + 用户态图形栈，HDMI 模式/EDID 与硬件渲染一并收口（原"显示体验"独立变更取消，直接并入本项）。
  - **P2 音频**：RK817 模拟音频 + HDMI 音频 + 真实音频 HAL，替换当前占位实现。
  - **P3 视频硬解**（可选，视需要再定）。
  - **延后**：Wi-Fi / 蓝牙（UWE 驱动移植 + Android 无线栈），暂不排期。
