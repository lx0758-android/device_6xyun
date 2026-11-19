# AGENTS.md — 原生 Android 项目

## 1. 项目概览

这是一个硬件适配 AOSP（版本请自行确认：`cat build/make/core/build_id.mk | grep BUILD_ID=`）原生系统的项目，项目目录是原生 AOSP 的代码结构。

采用 `Repo` + `local_manifests` 的形式进行版本管理。本地设备相关的配置、代码以 `local_manifests` 形式注入；

U-Boot 和 Kernel 也以软连接的形似连接到 u-boot 和 kernel-x.xx 目录，但是请注意 U-Boot 是主线 U-Boot, 而 Kernel 是 AOSP 官方的 Kernel，是一个 Repo 仓库。

## 2. 硬性约束 (必须遵守)

- **Agent 禁止执行编译**：不得运行 `m`、`make`、`soong_build`、`ninja` 等构建命令。涉及编译时，只能输出“可以编译了”，并给出具体命令，由用户验证。
- **Agent 禁止操作设备**：不得执行 `adb`、`scrcpy`、`fastboot`、`ssh`、`rsync` 等任何连接设备的命令。只有在用户明确说明“设备已就绪，可以 adb 操作”时，才可给出 adb 验证步骤，但仍不得自行执行。
- **搜索必须限定范围**：AOSP 项目庞大，搜索前必须先划定目录范围，例如 `frameworks/base/`、`system/`、`device/`、`vendor/`。**严禁整仓无差别搜索**。
- **禁止无端臆想**：可以联想，但必须有代码、日志、文档或构建规则作为证据支撑。
- **不修改构建产物**：不要编辑 `out/` 目录下的任何内容。
- **不触碰敏感资产**：不得提交或修改密钥、证书、vendor 私有二进制、生产环境 IP 和账号。
- **不轻易改动上游**：**不得轻易改动 AOSP 上游代码，所有修改只能集中在 `device/6xyun/`、`vendor/6xyun/`，且子目录与文件结构需要遵循AOSP标准或行业标准。**
- **不绑定具体硬件**: 实现过程中不能出现和产品具体绑定的硬参数、硬编码的常量，应该做到灵活适配，实在无法“自动获取”的信息，可以考虑通过产品配置注入。

## 3. 目录结构

- `frameworks/base/`：Android Framework，重点关注 AMS、WMS、SystemServer、权限与资源管理。
- `frameworks/native/`：Native 层 Framework，包括 SurfaceFlinger、InputFlinger、Binder 等。
- `system/`：系统核心组件，如 init、vold、netd、hwservicemanager、libbase 等。
- `hardware/interfaces/`：HIDL/AIDL 硬件接口，关注虚拟化、显示、输入、存储等 HAL。
- `device/`：设备配置、BoardConfig、内核配置、分区布局、init rc 和 fstab。
- `device/6xyun/`：设备配置目录、BoardConfig、内核配置、分区布局、init rc 和 fstab。
- `vendor/`：厂商私有实现、HAL 二进制和 vendor 分区内容。
- `vendor/6xyun/`：**设备厂商目录，适配设备的代码、库以及配套的配置文件等。**
- `external/`：第三方开源库。
- `prebuilts/`：预编译工具链和二进制，不要手动修改。
- `build/`：Soong/Make 构建系统配置。
- `out/`：构建输出目录，由构建系统生成，不要提交或编辑。

## 4. 常用命令 (仅作为参考，由用户执行)

- 初始化环境：`source build/envsetup.sh`
- 选择目标：`lunch <cloud_product>-<variant>`
- 模块构建：`m <module>`
- 构建 system 镜像：`m systemimage`
- 构建 vendor 镜像：`m vendorimage`
- 构建 boot 镜像：`m bootimage`
- 清理模块产物：优先清理对应模块的 `out/` 子目录，而非整仓清理
- 推送修改：`adb sync`、`adb push <local> <remote>`
- 查看日志：`adb logcat`、`dmesg`、`logcat -b events`

## 5. Agent 工作模式

每次任务应按以下流程输出：

1. **划定范围**：说明本次任务涉及的目录和模块，例如 `frameworks/base/services`。
2. **定位证据**：给出相关类、接口、配置或构建规则的路径，不得凭记忆编造。
3. **修改方案**：列出需要新增、删除或修改的文件，并说明变更原因。
4. **给出命令**：输出建议的编译命令和验证命令，例如：

   ```bash
   m frameworks-base
   adb sync
   adb shell stop && adb shell start
   adb logcat -s XXXXX:* ActivityManager:*
   ```

## 6. 问题定位指南

### 6.1 范围与证据

- **精准划定范围**：严禁整仓搜索。Framework层搜 `frameworks/`，系统服务搜 `system/`。
- **寻找代码证据**：在限定范围内查找类名、接口（AIDL/HIDL）、配置（`.rc`, `.xml`）或构建规则（`Android.bp`）。

### 6.2 追查原则

- **拒绝盲目扩大**：严格围绕初始模块追查，逻辑不通则重新评估分类，不无限制扩散。
- **避免死磕**：同一逻辑链反复查看无果，立即停止静态分析，转为日志驱动。

### 6.3 日志驱动

- **多加少次**：在函数出入口、关键分支、异常处全面打点，一次性覆盖所有可疑点，避免反复编译复现。
- **统一Tag**：使用统一 Tag（如 `TAG_XXXX`）方便过滤，临时日志应采用容易区分的 Tag。

### 6.4 命令规范

- 主机端命令正常输出；设备端命令**不带** `adb shell` / `adb logcat` 前缀，直接给裸命令。
- 示例：
  ```bash
  # 主机端
  m frameworks-base
  adb push xxxx xxxx
  adb shell sync

  # 设备端 (adb shell 内)
  stop && start
  logcat -s TAG_XXXX:* ActivityManager:*
  ```

### 6.5 知识收割

- **存档位置**：当完成某个任务之后，用户可能会要求整理过程、总结之类的文档、博客，这里统一要求，**存放路径为 `~/temp/docs/*`，不要在当前目录存放。**
- **引用规范**：当展示代码片段时，代码是有据可查的, 必须要加代码路径；如果是伪代码，也必须明确说明。
- **文档格式**：必须使用 Markdown 格式表达。- **知识沉淀**：现在做的是“容器化Android”，属于非常规业务。我需要你识别出涉及的修改中有别于正常 Android 终端的核心业务，这种改动往往在正常 Android 设备上不需要，但容器化的场景一定得有，要把整体方案整理呈现出来，然后再去介绍是如何处理问题和需求的。
- **公开匿名**：与本地环境有关的内容，比如 `commit id`、路径、密钥等内容，要判断是否是公开网络环境能获取的信息，如果不能获取则需要匿名化或舍去。
