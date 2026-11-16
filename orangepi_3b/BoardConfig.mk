# OrangePi-3B (RK3566) 单板构建配置
#
# 设备形态：非 A/B、恢复资源置于 vendor_boot、不启用镜像校验。
# 本阶段不包含任何硬件服务（HAL），只负责分区、镜像与首阶段挂载。

# ---------------------------------------------------------------------------
# 平台与架构
# ---------------------------------------------------------------------------
TARGET_BOARD_PLATFORM := rk3566

TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := cortex-a55
TARGET_CPU_SMP := true

TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv8-2a
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := cortex-a55

# ---------------------------------------------------------------------------
# 分区参数表（芯片平台 GPT 描述）
# ---------------------------------------------------------------------------
BOARD_BUILD_PARMETERS_TXT := true

# ---------------------------------------------------------------------------
# 引导程序产物
# ---------------------------------------------------------------------------
UBOOT_DIR := u-boot/build
PRODUCT_COPY_FILES += \
    $(UBOOT_DIR)/idbloader.img:idbloader.img \
    $(UBOOT_DIR)/u-boot.itb:u-boot.itb

# ---------------------------------------------------------------------------
# 非 A/B 形态
# ---------------------------------------------------------------------------
AB_OTA_UPDATER := false
# aosp_arm64 会以 ?= 设置 AB_OTA_PARTITIONS，非 A/B 下必须显式清空，
# 否则与 AB_OTA_UPDATER=false 冲突（core/Makefile:6403）。
AB_OTA_PARTITIONS :=

# ---------------------------------------------------------------------------
# 启动镜像（版本 4 头部）
# ---------------------------------------------------------------------------
KERNEL_DIR := kernel-6.18/out/orangepi3b/dist

BOARD_BOOTIMAGE_PARTITION_SIZE := 67108864 # 64 MiB
BOARD_PREBUILT_KERNEL := $(KERNEL_DIR)/Image
BOARD_USES_GENERIC_KERNEL_IMAGE := true
BOARD_BOOT_HEADER_VERSION := 4
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOT_HEADER_VERSION)

PRODUCT_COPY_FILES += \
    $(KERNEL_DIR)/Image:kernel

# ---------------------------------------------------------------------------
# 内核模块（随厂商启动镜像交付）
# ---------------------------------------------------------------------------
KERNEL_MODULES_DIR := $(KERNEL_DIR)
# 测试类模块引用白名单外的符号，Android 17 会拒绝加载并导致首阶段启动失败，
# 因此从模块清单与加载清单中一并剔除（load 条目带路径前缀，按整行匹配）。
KERNEL_MODULES_KOS := $(strip $(shell printf '%s\n' $(wildcard $(KERNEL_MODULES_DIR)/*.ko) | grep -vE 'test|kunit'))
KERNEL_MODULES_LOAD := $(strip $(shell grep -vE 'test|kunit' $(firstword $(wildcard $(KERNEL_MODULES_DIR)/modules.load) /dev/null)))
BOARD_VENDOR_RAMDISK_KERNEL_MODULES := $(KERNEL_MODULES_KOS)
BOARD_VENDOR_RAMDISK_KERNEL_MODULES_LOAD := $(KERNEL_MODULES_LOAD)
# 不得对厂商 ramdisk 中的模块做裁剪：裁剪会破坏模块签名，
# Android 17 对使用白名单外符号的模块强制要求签名校验。
BOARD_DO_NOT_STRIP_VENDOR_RAMDISK_MODULES := true

# ---------------------------------------------------------------------------
# 厂商启动镜像与恢复资源
# ---------------------------------------------------------------------------
BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE := 67108864 # 64 MiB
BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT := true
BOARD_INCLUDE_DTB_IN_BOOTIMG := true
# 恢复环境与正常启动共用同一份分区表，构建时安装为 /etc/recovery.fstab。
# 缺失时 recovery 会因 fstab.empty() 断言中止，fastbootd 也就起不来。
TARGET_RECOVERY_FSTAB := device/6xyun/orangepi_3b/etc/fstab.orangepi_3b

# ---------------------------------------------------------------------------
# 设备树与设备树叠加
# ---------------------------------------------------------------------------
DTB_DIR := $(KERNEL_DIR)
BOARD_PREBUILT_DTBIMAGE_DIR := $(DTB_DIR)

DTBO_DIR := $(KERNEL_DIR)
BOARD_PREBUILT_DTBO := \
    $(DTBO_DIR)/rk3566-orangepi-3b-v1.1.dtb \
    $(DTBO_DIR)/rk3566-orangepi-3b-v2.1.dtb
BOARD_DTBOIMG_PARTITION_SIZE := 4194304 # 4 MiB
BOARD_DTBO_UNSIGNED := dtbo-unsigned.img
BOARD_PREBUILT_DTBOIMAGE = $(PRODUCT_OUT)/$(BOARD_DTBO_UNSIGNED)

# ---------------------------------------------------------------------------
# 内核命令行与引导配置
# ---------------------------------------------------------------------------
# 内核命令行不携带 androidboot.*，这类参数统一通过引导配置传入。
BOARD_KERNEL_CMDLINE += \
    init=/init \
    printk.devkmsg=on \
    console=ttyS2,1500000n8 \
    firmware_class.path=/vendor/firmware \
    loglevel=7 \
    earlycon

BOARD_BOOTCONFIG += \
    androidboot.boot_devices=fe310000.mmc \
    androidboot.hardware=orangepi_3b \
    androidboot.selinux=permissive

# ---------------------------------------------------------------------------
# 杂项、校验与元数据分区
# ---------------------------------------------------------------------------
BOARD_MISCIMAGE_PARTITION_SIZE := 4194304 # 4 MiB

# 不启用镜像校验：不生成校验镜像，分区保留空置占位。
BOARD_AVB_ENABLE := false
BOARD_VBMETAIMAGE_PARTITION_SIZE := 4194304 # 4 MiB

BOARD_USES_METADATA_PARTITION := true
BOARD_METADATAIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_METADATAIMAGE_PARTITION_SIZE := 4194304 # 4 MiB

# 缓存分区：恢复日志持久化、非 A/B OTA 的包暂存与 uncrypt block map
BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_CACHEIMAGE_PARTITION_SIZE := 1073741824 # 1 GiB

# ---------------------------------------------------------------------------
# 系统镜像与动态分区
# ---------------------------------------------------------------------------
BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE := ext4

TARGET_COPY_OUT_VENDOR := vendor
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4

TARGET_COPY_OUT_PRODUCT := product
BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE := ext4

BOARD_BUILD_SUPER_IMAGE_BY_DEFAULT := true
# 4 GiB / 组约 2 GiB 沿用自 A/B（单 super 装两套镜像），非 A/B 只用到一半，余量刻意保留。
# 要回收空间：组尺寸提到 ~4094 MiB 则只需刷 super.img；缩 super 尺寸则需连 GPT 一起重刷。
BOARD_SUPER_PARTITION_SIZE := 4294967296 # 4096 MiB
BOARD_SUPER_PARTITION_GROUPS := default_dynamic_partitions
BOARD_DEFAULT_DYNAMIC_PARTITIONS_PARTITION_LIST := system vendor product
BOARD_DEFAULT_DYNAMIC_PARTITIONS_SIZE := 2143289344 # 约 2044 MiB，非 A/B 下可提升

# ---------------------------------------------------------------------------
# 用户数据分区
# ---------------------------------------------------------------------------
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := f2fs
BOARD_USERDATAIMAGE_PARTITION_SIZE := 21474836480 # 20 GiB

# ---------------------------------------------------------------------------
# SELinux 与硬件接口清单
# ---------------------------------------------------------------------------
BOARD_SEPOLICY_DIRS += \
    device/6xyun/orangepi_3b/sepolicy

DEVICE_MANIFEST_FILE := device/6xyun/orangepi_3b/manifest.xml
DEVICE_MATRIX_FILE := device/6xyun/orangepi_3b/compatibility_matrix.xml
