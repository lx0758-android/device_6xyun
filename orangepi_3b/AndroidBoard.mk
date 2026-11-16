#
# OrangePi-3B (RK3566) 单板构建钩子
#
# 平台需要的额外镜像：分区参数表、设备树叠加、元数据分区。
#

-include device/6xyun/common/build/BuildParameterTxt.mk
-include device/6xyun/common/build/BuildDtboImage.mk
-include device/6xyun/common/build/BuildMetadataImage.mk
