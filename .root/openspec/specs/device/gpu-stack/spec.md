# device/gpu-stack Specification

## Purpose

定义 GPU 从内核驱动到用户态图形接口的完整契约：硬件渲染必须真实生效、缓冲必须能被 GPU 使用、能力声明必须与实测一致，预编译交付必须可追溯，并且任一环节失败都能回到可用的软件路径。

## Requirements

### Requirement: GPU 内核驱动随板级模块交付

板级内核 MUST 以模块形式提供 GPU 驱动，并在启动后暴露渲染节点；驱动缺失时系统 MUST 仍可完成开机。

#### Scenario: 渲染节点存在

- **WHEN** 系统启动完成
- **THEN** 存在 GPU 渲染节点，内核日志显示驱动探测成功，无固件或供电错误

#### Scenario: 驱动缺失

- **WHEN** 板级模块清单不包含 GPU 驱动
- **THEN** 系统仍完成开机并进入软件图形路径，不出现启动挂起

### Requirement: 图形接口由硬件渲染并支持构建期切换

设备 MUST 通过 GPU 完成客户端合成与窗口渲染；图形接口实现 MUST 能通过构建配置切换到其他实现，切换后系统 MUST 仍可启动并显示界面。

#### Scenario: 界面硬件渲染

- **WHEN** 系统启动到界面阶段
- **THEN** 图形接口解析到 GPU 实现，客户端合成与窗口渲染不再由 CPU 图形库承担；设备合成仍由硬件合成器决定

#### Scenario: 切换到软件实现

- **WHEN** 将构建配置指向软件实现，重新构建并刷写后重启
- **THEN** 系统正常启动并显示界面，可用于故障回退

### Requirement: 图形缓冲区可被 GPU 使用

图形缓冲分配结果 MUST 能被 GPU 导入并渲染；当前允许线性布局，但 MUST NOT 依赖分配器提供压缩或私有布局才能工作。

#### Scenario: 分配并导入

- **WHEN** 合成器分配图形缓冲并交给 GPU 使用
- **THEN** GPU 成功导入该缓冲并完成渲染，画面无错位或花屏

#### Scenario: 分配器不支持目标格式

- **WHEN** 请求的缓冲格式无法由当前分配路径提供
- **THEN** 合成器回退到可用格式或软件合成，不出现合成器崩溃

### Requirement: 图形能力声明与实测一致

设备 MUST 只声明实际可用的图形接口版本与后端；未经实测的接口 MUST NOT 设为默认。

#### Scenario: GLES 版本声明

- **WHEN** 应用查询图形接口版本
- **THEN** 返回值不高于 GPU 实现实际支持的版本

#### Scenario: 未验证的 Vulkan 后端

- **WHEN** 硬件 Vulkan 后端尚未通过验证
- **THEN** 默认 Vulkan 后端仍为已验证实现，硬件后端仅能通过显式配置启用

### Requirement: 硬件 Vulkan 后端随预编译图形库交付

设备 MUST 交付基于同一 GPU 驱动的硬件 Vulkan 实现，并 MUST 能通过构建配置切换回软件实现；硬件后端未通过实测前 MUST NOT 设为默认。

#### Scenario: PanVK 实测通过

- **WHEN** 以 `ro.hardware.vulkan=panfrost` 构建并刷写后启动
- **THEN** `cmd gpu vkjson` 能枚举到 PanVK 物理设备，Vulkan 应用解析到硬件实现，基础渲染用例通过，系统正常启动

#### Scenario: 回退软件 Vulkan

- **WHEN** 将构建配置切回 `pastel` 并重新构建、刷写
- **THEN** Vulkan 应用仍可运行，系统正常启动

### Requirement: GPU 频率随负载调节

GPU MUST 在空闲时降频、负载上升时升频；MUST NOT 固定在最高频率导致常驻高功耗。

#### Scenario: 空闲与负载

- **WHEN** 分别处于无渲染负载与持续渲染负载
- **THEN** GPU 工作频率随之变化，且变化过程无渲染错误

### Requirement: 预编译图形库可追溯与可重建

以预编译形式交付的图形库 MUST 记录上游版本、构建参数、工具链版本与产物哈希，并 MUST 能按记录重建；来源不明的二进制 MUST NOT 交付。

#### Scenario: 交付前记录

- **WHEN** 交付一组预编译图形库
- **THEN** 上游版本、构建参数、工具链版本与每个产物的哈希均可查，且按记录能重建出等价产物

#### Scenario: 来源不明

- **WHEN** 无法说明某个图形库的上游版本或构建参数
- **THEN** 该产物不得进入系统镜像

### Requirement: GPU 在系统挂起与恢复后仍可用

系统挂起并恢复后，GPU MUST 继续可用；MUST NOT 因电源域、时钟或运行时电源管理未恢复导致渲染失败。

#### Scenario: 挂起后恢复

- **WHEN** 系统完成一次挂起与恢复
- **THEN** GPU 渲染节点与调频仍正常，内核日志无 GPU 相关错误

### Requirement: GPU 异常不影响系统可用性

单个 GPU 任务出错或驱动探测失败时，系统 MUST 保持可用；MUST NOT 因 GPU 故障导致内核崩溃或无法回退软件渲染。

#### Scenario: 任务执行出错

- **WHEN** 单个 GPU 任务触发硬件错误
- **THEN** 设备不出现内核崩溃，任务失败并可回退软件渲染，后续任务仍可执行

#### Scenario: 驱动探测失败

- **WHEN** GPU 驱动因资源或固件问题探测失败
- **THEN** 系统正常开机，图形接口回退到软件实现
