# Proposal

## Why

设备能开机、能显示，但图形能力为空：

- 没有任何 GPU 驱动。界面通过 ANGLE + SwiftShader 纯 CPU 渲染，`ro.hardware.egl=angle`，桌面滑动、动画、视频窗口合成全部由 4 个 A55 硬扛。

GPU 决定设备能否作为"能跑图形界面"的终端使用，必须把能力边界与实施路径定清楚。

## What Changes

- **GPU 内核**：以板级模块引入 Panfrost 与 `gpu-sched`；设备树 GPU 节点已就绪，按需补 OPP/供电校验。
- **GPU 用户态**：用 Mesa Panfrost 提供 GLES，同时交付 Mesa PanVK 硬件 Vulkan 实现（必交付项），通过 `ro.hardware.egl` / `ro.hardware.vulkan` 选择；gralloc 先走线性缓冲，AFBC 留作优化。图形库以出树 meson 交叉编译的预编译产物交付，构建脚本、版本与哈希记录放在 `vendor/6xyun/hardware/gpu/mesa/`，源码只读引用 `external/mesa3d`，不修改、不复制上游；产物必须同时覆盖 arm64 与 arm，保证 `zygote64_32` 下的 32 位进程也能加载 EGL/GLES 与 Vulkan。
- **配套**：KMI 符号白名单、GPU 预编译模块与安装路径、产品包清单与属性。

明确不做：

- 不负责 HDMI/DSI 显示输出、面板与触摸（由 `orangepi-3b-display-bringup` 负责）；
- 不修改 `external/mesa3d` 的任何文件，也不把 Mesa 源码复制进 vendor；构建脚本与预编译产物只放在 `vendor/6xyun`；
- 不引入厂商闭源 `libmali` 与 kbase 内核驱动（与 6.18 主线/GKI 不兼容，详见 design）；
- 不使用 init 脚本或属性开关伪装能力；
- 不承诺 AFBC 优化；Vulkan 作为必交付能力，PanVK 已通过 Vulkan 1.0 冒烟用例并设为默认，`pastel` 保留为回退。

## Capabilities

### New Capabilities

- `device/gpu-stack`：GPU 内核驱动、用户态图形库选择、gralloc 协同与失败回退。

### Modified Capabilities

- `device/graphics-stack`：图形后端选择从“软件默认”收紧为“硬件优先、构建期可回退”，并覆盖 GPU 客户端合成。

## Impact

- 内核：板级 fragment、GPU 模块登记、KMI 白名单。
- 用户态：`vendor/6xyun/hardware/gpu/mesa/` 新增出树构建脚本与来源记录，`vendor/6xyun/prebuilts/gpu/mesa/` 存放预编译库（含 `vulkan.panfrost.so`）；`device/6xyun/orangepi_3b` 增加预编译包、`ro.hardware.egl` / `ro.hardware.vulkan` 与 SELinux 标签。
- 验证面：`/dev/dri/renderD*`、GLES 信息、`dumpsys SurfaceFlinger` 合成模式。
