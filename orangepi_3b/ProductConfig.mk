#
# OrangePi-3B (RK3566) 产品定义
#
# 本阶段提供构建骨架与最小可开机硬件服务集合（显示、音频、电源、健康、密钥）。
#

$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/aosp_arm64.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/generic_ramdisk.mk)

# Dalvik 堆参数：不声明时运行时兜底只有 -Xms 4m / -Xmx 16m，系统服务必崩。
# growth 取 2/4 GiB 通用档 192m；minfree/maxfree/利用率沿用 ART 默认量级，避免大块分配频繁 GC。
PRODUCT_VENDOR_PROPERTIES += \
    dalvik.vm.heapstartsize?=8m \
    dalvik.vm.heapgrowthlimit?=192m \
    dalvik.vm.heapsize?=512m \
    dalvik.vm.heaptargetutilization?=0.6 \
    dalvik.vm.heapminfree?=2m \
    dalvik.vm.heapmaxfree?=32m

# ---------------------------------------------------------------------------
# 产品标识
# ---------------------------------------------------------------------------
PRODUCT_NAME := orangepi_3b
PRODUCT_DEVICE := orangepi_3b
PRODUCT_BRAND := orangepi_3b
PRODUCT_MODEL := orangepi_3b
PRODUCT_MANUFACTURER := Xunlong
PRODUCT_CHARACTERISTICS := tablet

# ---------------------------------------------------------------------------
# 镜像产物开关
# ---------------------------------------------------------------------------
PRODUCT_BUILD_BOOT_IMAGE := true
PRODUCT_BUILD_DTBO_IMAGE := true
PRODUCT_BUILD_SYSTEM_IMAGE := true
PRODUCT_BUILD_VENDOR_IMAGE := true
PRODUCT_BUILD_PRODUCT_IMAGE := true
PRODUCT_BUILD_USERDATA_IMAGE := true

# 不启用镜像校验：不生成校验镜像（分区空置）
PRODUCT_BUILD_VBMETA_IMAGE := false

# ---------------------------------------------------------------------------
# 动态分区
# ---------------------------------------------------------------------------
PRODUCT_BUILD_SUPER_PARTITION := true
PRODUCT_USE_DYNAMIC_PARTITIONS := true
PRODUCT_USE_DYNAMIC_PARTITION_SIZE := true

# ---------------------------------------------------------------------------
# 恢复能力：资源打包进厂商启动镜像，另提供 fastbootd 用于动态分区更新
#
# 只放 fastbootd 不够：init 用 /system/bin/recovery 是否存在判定恢复模式
# （system/core/init/util.cpp:673），而 fastbootd 由恢复环境的 init.rc 在
# sys.usb.config=fastboot 时启动（bootable/recovery/etc/init.rc:138）。
# 本产品没有继承 base_vendor.mk，因此这里显式补齐恢复环境所需的包与属性。
# 恢复资源经 BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT 打进 vendor_boot。
# ---------------------------------------------------------------------------
PRODUCT_PACKAGES += \
    recovery \
    fastbootd \
    adbd.recovery \
    linker.recovery \
    cgroups.recovery.json \
    ld.config.recovery.txt \
    servicemanager.recovery \
    init_second_stage.recovery \
    shell_and_utilities_recovery

# 恢复环境的 USB 标识（取值同 base_vendor.mk 的 AOSP 默认值）。
# 缺失时 bootable/recovery/etc/init.rc 会向 configfs 写入空的 idVendor/idProduct，
# 主机无法枚举到 fastbootd。
PRODUCT_VENDOR_PROPERTIES += \
    ro.recovery.usb.vid=18D1 \
    ro.recovery.usb.adb.pid=D001 \
    ro.recovery.usb.fastboot.pid=4EE0

# ---------------------------------------------------------------------------
# 资源 overlay
# ---------------------------------------------------------------------------
# 设计规格：本机常供电，空闲时不进入系统挂起；同时启用 Doze 收敛后台活动。
PRODUCT_PACKAGE_OVERLAYS += device/6xyun/orangepi_3b/overlay

# ---------------------------------------------------------------------------
# SELinux 与硬件接口清单
# ---------------------------------------------------------------------------
PRODUCT_PACKAGES += \
    selinux_policy_nonsystem \
    precompiled_sepolicy \
    precompiled_sepolicy.plat_sepolicy_and_mapping.sha256 \
    precompiled_sepolicy.system_ext_sepolicy_and_mapping.sha256 \
    precompiled_sepolicy.product_sepolicy_and_mapping.sha256

PRODUCT_PACKAGES += \
    vendor_compatibility_matrix.xml

# ---------------------------------------------------------------------------
# 挂载表：恢复、首阶段 ramdisk 与厂商分区三处
# ---------------------------------------------------------------------------
PRODUCT_COPY_FILES += \
    device/6xyun/orangepi_3b/etc/fstab.orangepi_3b:$(TARGET_COPY_OUT_RECOVERY)/root/first_stage_ramdisk/fstab.orangepi_3b \
    device/6xyun/orangepi_3b/etc/fstab.orangepi_3b:$(TARGET_COPY_OUT_VENDOR_RAMDISK)/first_stage_ramdisk/fstab.orangepi_3b \
    device/6xyun/orangepi_3b/etc/fstab.orangepi_3b:$(TARGET_COPY_OUT_VENDOR)/etc/fstab.orangepi_3b

# ---------------------------------------------------------------------------
# 初始化脚本
# ---------------------------------------------------------------------------
PRODUCT_COPY_FILES += \
    device/6xyun/orangepi_3b/init/init.orangepi_3b.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/init.orangepi_3b.rc

# ---------------------------------------------------------------------------
# 图形栈：DRM/KMS 合成器 + minigbm + Mesa Panfrost；ANGLE/SwiftShader 保留为回退
# ---------------------------------------------------------------------------
PRODUCT_PACKAGES += \
    com.android.hardware.graphics.composer.drm_hwcomposer \
    gralloc.minigbm \
    android.hardware.graphics.allocator-service.minigbm \
    mapper.minigbm

# Mesa Panfrost 预编译库（vendor/6xyun/prebuilts/gpu/mesa）
PRODUCT_PACKAGES += \
    libEGL_mesa \
    libGLESv1_CM_mesa \
    libGLESv2_mesa \
    libgallium_dri

# 两个 Vulkan 后端都进镜像：默认后端由 PRODUCT_VULKAN_TYPE 决定，
# 但 vulkan.pastel.so 也保留，便于在设备上 remount 改 ro.hardware.vulkan 后直接切换，
# 不必为了回退重新构建。
PRODUCT_PACKAGES += \
    vulkan.panfrost \
    vulkan.pastel

# Vulkan 冒烟测试（/vendor/bin/panvk_smoke）：Vulkan 1.0 离屏 clear + copy + 回读校验。
# 用于 task 2.12 验收，也可以对 pastel 跑同样的用例做对照。
PRODUCT_PACKAGES += \
    panvk_smoke

# 软件渲染需要可执行内存映射（回退路径仍使用 SwiftShader）
PRODUCT_REQUIRES_INSECURE_EXECMEM_FOR_SWIFTSHADER := true

# Mesa 26.1 把 Bifrost（arch 6/7）上的 PanVK 标为“未充分测试”：
# panvk_physical_device_init() 在 arch 6/7 时检查 PAN_I_WANT_A_BROKEN_VULKAN_DRIVER，
# 未设置就直接返回 VK_ERROR_INCOMPATIBLE_DRIVER，物理设备被当成不兼容设备跳过，
# 表现为 cmd gpu vkjson 的 devices 为空（instance 创建正常，也没有 dlopen 报错）。
# G52 是 arch 7，所以使用 panfrost 时必须带上该开关。
# Android 上 Mesa 的 os_get_option() 在环境变量缺失时回落到属性：变量名转小写、
# '_' 换成 '.'、再加 "debug." 前缀，即
#   PAN_I_WANT_A_BROKEN_VULKAN_DRIVER -> debug.mesa.pan.i.want.a.broken.vulkan.driver
# 用属性交付而不是改 external/mesa3d。该开关与当前选的后端无关、始终注入，
# 这样 remount 切到 panfrost 时不需要再补属性；选 pastel 时它只是一个不生效的选项。
PRODUCT_VENDOR_PROPERTIES += debug.mesa.pan.i.want.a.broken.vulkan.driver=1

# 图形后端类型（构建期选择）。ro.hardware.egl / ro.hardware.vulkan 都是只读属性，
# 回退必须重新构建并刷写 vendor，不能在运行期 setprop 切换。
#   EGL 类型:    mesa（默认，Mesa Panfrost GLES）
#                angle（回退，ANGLE + SwiftShader Vulkan）
#   Vulkan 类型: panfrost（默认，Mesa PanVK 硬件实现，已通过 panvk_smoke）
#                pastel（回退，SwiftShader 软件实现）
# 用法示例：
#   m vendorimage PRODUCT_EGL_TYPE=angle
#   m vendorimage PRODUCT_VULKAN_TYPE=pastel
PRODUCT_EGL_TYPE ?= mesa
PRODUCT_VULKAN_TYPE ?= panfrost
# ro.hardware.gralloc 是 gralloc0 的查找入口。Mesa 的 u_gralloc 通过
# hw_get_module("gralloc") 读取 DRM fourcc/stride/offset/modifier；找不到模块时
# 退化为 fallback（只支持 RGBA），日志为
# "No gralloc hwmodule detected (video buffers won't be supported)"，NV12/YV12
# 缓冲无法交给 GPU。minigbm 的 gralloc0 模块文件是 gralloc.minigbm.so，
# 必须由该属性指向它，Mesa 才会使用其中的 "CrOS Gralloc" 实现。
PRODUCT_VENDOR_PROPERTIES += \
    ro.hardware.gralloc=minigbm \
    ro.hardware.egl=$(PRODUCT_EGL_TYPE) \
    ro.hardware.vulkan=$(PRODUCT_VULKAN_TYPE)

PRODUCT_PROPERTY_OVERRIDES += \
    ro.opengles.version=196609 \
    ro.sf.lcd_density=240

# Panfrost 提供 GLES 3.1；同时声明 Android Extension Pack 特性
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.opengles.aep.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.opengles.aep.xml

# ---------------------------------------------------------------------------
# 音频栈：AIDL 服务 + 新版策略配置（无声卡驱动，仅占位）
# ---------------------------------------------------------------------------
PRODUCT_PACKAGES += \
    com.android.hardware.audio

# 编解码器只注册 AIDL 服务，默认发现方式会导致编码器列表为空
PRODUCT_VENDOR_PROPERTIES += media.c2.hal.selection=aidl

# 软件编解码器跑在 APEX 里，不提供 HAL 输入面；不切到 AIDL 图形缓冲源时，
# 创建编码输入面会因取不到输入面而空指针崩溃（投屏/录屏必现）。
PRODUCT_VENDOR_PROPERTIES += debug.stagefright.c2inputsurface=-1

PRODUCT_COPY_FILES += \
    device/6xyun/orangepi_3b/etc/audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_policy_configuration.xml \
    hardware/interfaces/audio/aidl/default/audio_effects_config.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_effects_config.xml \
    frameworks/av/services/audiopolicy/config/bluetooth_audio_policy_configuration_7_0.xml:$(TARGET_COPY_OUT_VENDOR)/etc/bluetooth_audio_policy_configuration_7_0.xml \
    frameworks/av/services/audiopolicy/config/r_submix_audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/r_submix_audio_policy_configuration.xml \
    frameworks/av/services/audiopolicy/config/usb_audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/usb_audio_policy_configuration.xml \
    frameworks/av/services/audiopolicy/config/default_volume_tables.xml:$(TARGET_COPY_OUT_VENDOR)/etc/default_volume_tables.xml \
    frameworks/av/services/audiopolicy/config/audio_policy_volumes.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_policy_volumes.xml

# ---------------------------------------------------------------------------
# 最小系统服务集：密钥、电源、健康
# 不提供启动槽位控制服务：单槽位且无 OTA，默认实现在无槽位后缀时启动即崩，
# 其 VINTF 声明会让 vold 的检查点探测无限等待，故整体不引入。
# ---------------------------------------------------------------------------
PRODUCT_PACKAGES += \
    com.android.hardware.keymint.rust_nonsecure \
    android.hardware.power-service.6xyun \
    android.hardware.health-service.6xyun \
    android.hardware.lights-service.6xyun

# ---------------------------------------------------------------------------
# USB gadget
# ---------------------------------------------------------------------------
PRODUCT_COPY_FILES += \
    device/6xyun/orangepi_3b/init/init.orangepi_3b.usb.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/init.orangepi_3b.usb.rc

# ---------------------------------------------------------------------------
# 有线网络特性声明
# ---------------------------------------------------------------------------
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.ethernet.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.ethernet.xml

# Launcher3 的 OseWidgetManager 在 OSE 信息更新时直接使用 AppWidgetManager；
# 未声明 android.software.app_widgets 时，SystemServiceRegistry 对
# APPWIDGET_SERVICE 返回 null，Launcher 会反复 NullPointerException 崩溃。
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.software.app_widgets.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.app_widgets.xml

# ---------------------------------------------------------------------------
# Soong 命名空间
#
# Soong 不跟随软链接目录，厂商实现的命名空间必须使用实际路径；
# Make 层（PRODUCT_COPY_FILES、BOARD_SEPOLICY_DIRS 等）仍使用 vendor/6xyun。
# ---------------------------------------------------------------------------
PRODUCT_SOONG_NAMESPACES += \
    device/6xyun/.root/vendor_6xyun \
    external/minigbm \
    external/drm_hwcomposer \
    external/swiftshader
