$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/aosp_arm64.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/generic_ramdisk.mk)

# Device info
PRODUCT_NAME := orangepi_3b
PRODUCT_DEVICE := orangepi_3b
PRODUCT_BRAND := orangepi_3b
PRODUCT_MODEL := orangepi_3b
PRODUCT_MANUFACTURER := Xunlong

# Partitions
PRODUCT_BUILD_BOOT_IMAGE := true
PRODUCT_BUILD_DTBO_IMAGE := true
PRODUCT_BUILD_VBMETA_IMAGE := false
PRODUCT_BUILD_SYSTEM_IMAGE := true
PRODUCT_BUILD_VENDOR_IMAGE := true
PRODUCT_BUILD_PRODUCT_IMAGE := true
PRODUCT_BUILD_CACHE_IMAGE := true
PRODUCT_BUILD_USERDATA_IMAGE := true

# Dynamic partitions
PRODUCT_BUILD_SUPER_PARTITION := true
PRODUCT_USE_DYNAMIC_PARTITIONS := true
PRODUCT_USE_DYNAMIC_PARTITION_SIZE := true

# Recovery (for fastbootd/recovery mode without dedicated partition)
PRODUCT_PACKAGES += recovery

# Graphics HAL
PRODUCT_PACKAGES += \
    com.android.hardware.graphics.composer.drm_hwcomposer \
    gralloc.minigbm \
    android.hardware.graphics.allocator-service.minigbm

# Health HAL
PRODUCT_PACKAGES += \
    android.hardware.health-service.example

# Thermal HAL
PRODUCT_PACKAGES += \
    android.hardware.thermal-service.example

# Gatekeeper HAL (software)
PRODUCT_PACKAGES += \
    android.hardware.gatekeeper-service.nonsecure

# KeyMint HAL (software, nonsecure)
PRODUCT_PACKAGES += \
    android.hardware.security.keymint-service.nonsecure

# Boot control HAL
PRODUCT_PACKAGES += \
    com.android.hardware.boot

# DRM HAL
PRODUCT_PACKAGES += \
    android.hardware.drm-service.clearkey

# SELinux
PRODUCT_PACKAGES += \
    selinux_policy_nonsystem \
    precompiled_sepolicy \
    precompiled_sepolicy.plat_sepolicy_and_mapping.sha256 \
    precompiled_sepolicy.system_ext_sepolicy_and_mapping.sha256 \
    precompiled_sepolicy.product_sepolicy_and_mapping.sha256

# VINTF
PRODUCT_PACKAGES += \
    vendor_compatibility_matrix.xml

# File systems table
PRODUCT_COPY_FILES += \
    device/6xyun/orangepi_3b/etc/fstab.orangepi_3b:$(TARGET_COPY_OUT_RECOVERY)/root/first_stage_ramdisk/fstab.orangepi_3b \
    device/6xyun/orangepi_3b/etc/fstab.orangepi_3b:$(TARGET_COPY_OUT_VENDOR_RAMDISK)/first_stage_ramdisk/fstab.orangepi_3b \
    device/6xyun/orangepi_3b/etc/fstab.orangepi_3b:$(TARGET_COPY_OUT_VENDOR)/etc/fstab.orangepi_3b

# Init scripts
PRODUCT_COPY_FILES += \
    device/6xyun/orangepi_3b/init/init.orangepi_3b.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/init.orangepi_3b.rc \
    device/6xyun/orangepi_3b/init/init.orangepi_3b.usb.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/init.orangepi_3b.usb.rc \
    device/6xyun/orangepi_3b/init/android.hardware.boot-service.default.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/android.hardware.boot-service.default.rc

# Soong namespaces
PRODUCT_SOONG_NAMESPACES += \
    device/6xyun/orangepi_3b \
    external/minigbm \
    external/drm_hwcomposer
