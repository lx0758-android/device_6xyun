#
# OrangePi-3B (RK3566) 产品定义
#
# 本阶段只提供构建骨架：产品标识、分区/镜像产物、首阶段挂载与恢复资源，
# 不包含任何硬件服务（HAL）。开机验证在后续变更中进行。
#

$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/aosp_arm64.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/generic_ramdisk.mk)

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
# Soong 命名空间
# ---------------------------------------------------------------------------
PRODUCT_SOONG_NAMESPACES += \
    device/6xyun/orangepi_3b
