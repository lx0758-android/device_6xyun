# Platform
TARGET_BOARD_PLATFORM := rk3566

# Architecture
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := cortex-a55
TARGET_CPU_SMP := true
# 2nd Architecture
TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv8-2a
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := cortex-a55

# Parmeters.txt
BOARD_BUILD_PARMETERS_TXT := true

# Bootloader
UBOOT_DIR := device/6xyun/u-boot/build
PRODUCT_COPY_FILES += \
    $(UBOOT_DIR)/idbloader.img:idbloader.img \
    $(UBOOT_DIR)/u-boot.itb:u-boot.itb

# Boot image
KERNEL_DIR := device/6xyun/kernel/out/orangepi3b/dist
PRODUCT_COPY_FILES += \
    $(KERNEL_DIR)/Image:kernel
BOARD_BOOTIMAGE_PARTITION_SIZE := 67108864 # 64 MiB
BOARD_PREBUILT_KERNEL := $(KERNEL_DIR)/Image
BOARD_USES_GENERIC_KERNEL_IMAGE := true
BOARD_BOOT_HEADER_VERSION := 4
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOT_HEADER_VERSION)
# Modules
KERNEL_MODULES_DIR := $(KERNEL_DIR)
KERNEL_MODULES_KOS := $(wildcard $(KERNEL_MODULES_DIR)/*.ko)
KERNEL_MODULES_LOAD := $(strip $(shell cat $(firstword $(wildcard $(KERNEL_MODULES_DIR)/modules.load))))
KERNEL_MODULES_LOAD := $(filter-out %ptp_kvm.ko,$(KERNEL_MODULES_LOAD))
BOARD_VENDOR_RAMDISK_KERNEL_MODULES := $(KERNEL_MODULES_KOS)
BOARD_VENDOR_RAMDISK_KERNEL_MODULES_LOAD := $(KERNEL_MODULES_LOAD)
# DTB
DTB_DIR := $(KERNEL_DIR)
BOARD_PREBUILT_DTBIMAGE_DIR := $(DTB_DIR)
# Vendor boot image
BOARD_INCLUDE_DTB_IN_BOOTIMG := true
BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE := 67108864 # 64 MiB
BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT := true
# DTBO image
DTBO_DIR := $(KERNEL_DIR)
BOARD_PREBUILT_DTBO := \
    $(DTBO_DIR)/rk3566-orangepi-3b-v1.1.dtb \
    $(DTBO_DIR)/rk3566-orangepi-3b-v2.1.dtb
BOARD_DTBOIMG_PARTITION_SIZE := 4194304 # 4 MiB
BOARD_DTBO_UNSIGNED := dtbo-unsigned.img
BOARD_PREBUILT_DTBOIMAGE = $(PRODUCT_OUT)/$(BOARD_DTBO_UNSIGNED)
# Kernel cmdline (no androidboot.* here, they go via bootconfig)
BOARD_KERNEL_CMDLINE += \
    init=/init \
    printk.devkmsg=on \
    console=ttyS2,1500000n8 \
    firmware_class.path=/vendor/firmware \
    loglevel=7 \
    earlycon
# Bootconfig (androidboot.* params; U-Boot will also append serialno/bootloader/verifiedbootstate)
BOARD_BOOTCONFIG += \
    androidboot.boot_devices=fe310000.mmc \
    androidboot.hardware=orangepi_3b \
    androidboot.selinux=permissive \
    androidboot.slot_suffix=_a

# Misc image
BOARD_MISCIMAGE_PARTITION_SIZE := 4194304 # 4 MiB
# Vbmeta image
BOARD_VBMETAIMAGE_PARTITION_SIZE := 4194304 # 4 MiB
# Metadata image
BOARD_USES_METADATA_PARTITION := true
BOARD_METADATAIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_METADATAIMAGE_PARTITION_SIZE := 4194304 # 4 MiB

# System image
BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE := ext4
# Vendor image
TARGET_COPY_OUT_VENDOR := vendor
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
# Product image
TARGET_COPY_OUT_PRODUCT := product
BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE := ext4

# Super image
BOARD_BUILD_SUPER_IMAGE_BY_DEFAULT := true
BOARD_SUPER_PARTITION_SIZE := 4294967296 # 4096 MiB
BOARD_SUPER_PARTITION_GROUPS := default_dynamic_partitions
BOARD_DEFAULT_DYNAMIC_PARTITIONS_PARTITION_LIST := system vendor product
BOARD_DEFAULT_DYNAMIC_PARTITIONS_SIZE := 2143289344 # 4096 / 2 - 4 (1M metadata)= 2044 MiB

# Cache image
BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE := f2fs
BOARD_CACHEIMAGE_PARTITION_SIZE := 1073741824 # 1 GiB
# Userdata image
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := f2fs
BOARD_USERDATAIMAGE_PARTITION_SIZE := 21474836480 # 20 GiB

# SELinux
BOARD_SEPOLICY_DIRS += \
    device/6xyun/orangepi_3b/sepolicy

# VINTF
DEVICE_MANIFEST_FILE := device/6xyun/orangepi_3b/manifest.xml
DEVICE_MATRIX_FILE := device/6xyun/orangepi_3b/compatibility_matrix.xml

# Graphics
BOARD_USES_DRM_HWCOMPOSER := true
TARGET_USES_HWC2 := true
TARGET_DISABLE_TRIPLE_BUFFERING := false

# Minigbm gralloc
SOONG_CONFIG_NAMESPACES += minigbm
SOONG_CONFIG_minigbm += platform
SOONG_CONFIG_minigbm_platform := rockchip
