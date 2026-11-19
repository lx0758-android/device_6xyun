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
# 显示栈：DRM/KMS 合成器 + minigbm + 软件图形回退（无 GPU 驱动）
# ---------------------------------------------------------------------------
PRODUCT_PACKAGES += \
    com.android.hardware.graphics.composer.drm_hwcomposer \
    gralloc.minigbm \
    android.hardware.graphics.allocator-service.minigbm \
    mapper.minigbm \
    vulkan.pastel

# 软件渲染需要可执行内存映射
PRODUCT_REQUIRES_INSECURE_EXECMEM_FOR_SWIFTSHADER := true

PRODUCT_VENDOR_PROPERTIES += \
    ro.hardware.egl=angle \
    ro.hardware.vulkan=pastel

PRODUCT_PROPERTY_OVERRIDES += \
    ro.opengles.version=196608 \
    ro.sf.lcd_density=160

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
