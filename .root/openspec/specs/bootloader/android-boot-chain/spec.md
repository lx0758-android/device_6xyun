# bootloader/android-boot-chain Specification

## Purpose

定义引导程序从分区扫描、启动模式判定到启动参数注入的完整 Android 启动链行为，使 AOSP 侧镜像与引导程序之间的接口保持稳定。

## Requirements

### Requirement: 上电后自动进入 Android 启动流程

引导程序 MUST 在无人工干预时自动执行启动流程，延迟为零，并按启动顺序扫描存储设备。

#### Scenario: 上电自动启动

- **WHEN** 设备上电且无按键干预
- **THEN** 引导程序不等待人工输入，直接开始扫描可启动介质并进入 Android 启动流程

#### Scenario: 多介质启动顺序

- **WHEN** 设备同时存在 eMMC、SD 与 SPI 存储
- **THEN** 引导程序按预设顺序依次尝试，首个可启动介质生效

### Requirement: 启动模式由 misc 分区引导控制块决定

引导程序 MUST 读取 `misc` 分区的引导控制块命令字，据此决定本次启动模式：正常启动、恢复模式、fastbootd 或引导程序模式。无法识别或无命令字时按正常启动处理。

#### Scenario: 正常启动

- **WHEN** `misc` 分区中没有命令字
- **THEN** 引导程序按正常启动流程加载系统

#### Scenario: 进入恢复模式

- **WHEN** `misc` 分区命令字为 `boot-recovery`
- **THEN** 引导程序进入恢复模式启动流程

#### Scenario: 进入 fastbootd

- **WHEN** `misc` 分区命令字为 `boot-fastboot`
- **THEN** 引导程序按恢复模式流程启动，由系统侧进入 fastbootd

#### Scenario: 进入引导程序模式

- **WHEN** `misc` 分区命令字为 `bootonce-bootloader`
- **THEN** 引导程序清空该命令字后进入 fastboot 模式，且该模式只生效一次

### Requirement: 非 A/B 形态下使用无槽位的启动分区

设备 MUST 以非 A/B 形态启动：直接使用不带槽位后缀的 `boot` 与 `vendor_boot` 分区，不读取槽位信息，也不向系统注入槽位后缀参数。

#### Scenario: 加载无槽位启动镜像

- **WHEN** 引导程序定位启动分区
- **THEN** 使用 `boot` 与 `vendor_boot` 两个无槽位后缀的分区

#### Scenario: 不注入槽位后缀

- **WHEN** 引导程序构造启动参数
- **THEN** 参数中不包含槽位后缀，系统侧按无槽位设备处理

#### Scenario: 引导控制块中的槽位字段被忽略

- **WHEN** 引导控制块中残留槽位信息
- **THEN** 引导程序忽略该信息，不改变分区选择

### Requirement: 正常启动时显式声明非恢复模式

引导程序 MUST 仅在正常启动模式下注入"强制正常启动"参数（取值 1），且该注入不得以槽位信息为前提；恢复、fastbootd 与引导程序模式 MUST NOT 注入该参数。

#### Scenario: 正常启动注入标记

- **WHEN** 设备以正常模式启动
- **THEN** 启动参数中包含取值 1 的强制正常启动标记，系统进入正常模式

#### Scenario: 恢复模式不注入标记

- **WHEN** 设备以恢复模式启动
- **THEN** 启动参数中不包含强制正常启动标记，系统进入恢复模式

#### Scenario: 其它模式不受影响

- **WHEN** 设备以 fastbootd 或引导程序模式启动
- **THEN** 启动参数中不包含强制正常启动标记，且原有模式行为不变

#### Scenario: 恢复组件存在不影响正常启动

- **WHEN** 厂商启动镜像中包含恢复可执行文件
- **THEN** 正常启动仍然进入系统，不会误判为恢复模式

### Requirement: 启动镜像装载地址由环境约定提供

引导程序 MUST 通过环境变量获得 `vendor_boot` 的装载地址和内核的装载地址；缺失时不得退化为地址零。

#### Scenario: 装载 vendor_boot

- **WHEN** 引导程序读取 `vendor_boot` 分区
- **THEN** 镜像被装载到环境变量约定的地址，且该地址非零

#### Scenario: 缺少地址约定

- **WHEN** 环境变量未提供装载地址
- **THEN** 引导程序记录错误并放弃本次启动，而不是向地址零写入数据

### Requirement: 启动参数由引导程序与镜像共同构成

引导程序 MUST 向系统注入设备序列号、引导程序版本与验证启动状态；不得注入通用 Linux 启动参数，内核命令行由镜像自身提供。

#### Scenario: 注入设备标识

- **WHEN** 引导程序启动 Android
- **THEN** 系统可读取到设备序列号与引导程序版本

#### Scenario: 不污染内核命令行

- **WHEN** 引导程序配置为空命令行
- **THEN** 启动参数中不包含通用 Linux 启动参数，仅包含 Android 语义参数
