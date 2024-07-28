METADATA_IMG := $(PRODUCT_OUT)/metadata.img
MKUSERIMG := $(HOST_OUT_EXECUTABLES)/mkuserimg_mke2fs
METADATA_SRC := $(call intermediates-dir-for,PACKAGING,metadata)/empty

$(METADATA_SRC):
	$(hide) mkdir -p $@

$(METADATA_IMG): $(MKUSERIMG) $(METADATA_SRC)
	@echo "Target metadata fs image: $@"
	$(hide) $(MKUSERIMG) $(METADATA_SRC) $@ ext4 metadata $(BOARD_METADATAIMAGE_PARTITION_SIZE)

INSTALLED_METADATAIMAGE_TARGET := $(METADATA_IMG)

$(call declare-1p-target,$(METADATA_IMG),)

droidcore: $(INSTALLED_METADATAIMAGE_TARGET)
