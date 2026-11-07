#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

ifneq ($(filter kvim1s kvim1s_car kvim1s_tab,$(TARGET_DEVICE)),)

FACTORY_PATH := device/khadas/kvim1s/factory
VENDOR_PATH := vendor/khadas/kvim1s

PRODUCT_INSTALL_OUT := $(PRODUCT_OUT)/aml_install
PRODUCT_UPGRADE_OUT := $(PRODUCT_OUT)/aml_upgrade
AML_IMAGE_TOOL := $(HOST_OUT_EXECUTABLES)/aml_image_packer$(HOST_EXECUTABLE_SUFFIX)
KVIM1S_GEN_MISC := $(HOST_OUT_EXECUTABLES)/kvim1s_gen_misc$(HOST_EXECUTABLE_SUFFIX)

INSTALLED_AML_INSTALL_PACKAGE_TARGET := $(PRODUCT_OUT)/aml_install_package.img
INSTALLED_AML_UPGRADE_PACKAGE_TARGET := $(PRODUCT_OUT)/aml_upgrade_package.img

# $(1): source file, $(2): staging directory, $(3): destination name if it differs
define aml-copy-file
$(hide) $(ACP) $(1) $(2)/$(strip $(if $(3),$(3),$(notdir $(1))))
endef

# Generate slot A metadata for both factory paths. Installation boots recovery;
# an upgrade contains a populated super image and boots Android directly.
$(PRODUCT_OUT)/misc.img: $(KVIM1S_GEN_MISC)
	@mkdir -p $(dir $@)
	$(hide) $(KVIM1S_GEN_MISC) $@ --slot a --command boot-recovery

$(PRODUCT_OUT)/misc_upgrade.img: $(KVIM1S_GEN_MISC)
	@mkdir -p $(dir $@)
	$(hide) $(KVIM1S_GEN_MISC) $@ --slot a

# /oem must be mountable even though VIM1S has no OEM property overrides.
KHADAS_OEM_IMAGE := $(PRODUCT_OUT)/oem.img
INTERNAL_OEMIMAGE_FILES := $(filter $(TARGET_OUT_OEM)/%,$(ALL_DEFAULT_INSTALLED_MODULES))
oemimage_intermediates := $(call intermediates-dir-for,PACKAGING,oem)

$(KHADAS_OEM_IMAGE): $(INTERNAL_USERIMAGES_DEPS) $(INTERNAL_OEMIMAGE_FILES)
	$(call pretty,"Target oem fs image: $@")
	@mkdir -p $(TARGET_OUT_OEM) $(oemimage_intermediates)
	$(call generate-image-prop-dictionary,$(oemimage_intermediates)/oem_image_info.txt,oem,skip_fsck=true)
	PATH=$(INTERNAL_USERIMAGES_BINARY_PATHS):$$PATH \
	    $(BUILD_IMAGE) $(TARGET_OUT_OEM) $(oemimage_intermediates)/oem_image_info.txt $@ $(TARGET_OUT)
	$(call assert-max-image-size,$@,$(BOARD_OEMIMAGE_PARTITION_SIZE))

# Stages a package directory and hands it to the image packer.
# $(1): staging directory
# $(2): image.cfg to use
# $(3): super image to ship as super.img
# $(4): misc image to ship as misc.img
define aml-build-package
$(hide) mkdir -p $(1)
	$(call aml-copy-file,$(VENDOR_PATH)/radio/bootloader.img,$(1))
	$(call aml-copy-file,$(VENDOR_PATH)/factory/u-boot.bin.sd.bin.signed,$(1))
	$(call aml-copy-file,$(VENDOR_PATH)/factory/u-boot.bin.usb.signed,$(1))
	$(call aml-copy-file,$(VENDOR_PATH)/factory/gpt.bin,$(1))
	$(call aml-copy-file,$(VENDOR_PATH)/factory/usb_flow.aml,$(1))
	$(call aml-copy-file,$(VENDOR_PATH)/factory/odm_ext_a.PARTITION,$(1))
	$(call aml-copy-file,$(FACTORY_PATH)/aml_sdc_burn.ini,$(1))
	$(call aml-copy-file,$(FACTORY_PATH)/$(2),$(1),image.cfg)
	$(call aml-copy-file,$(FACTORY_PATH)/platform.conf,$(1))
	$(call aml-copy-file,$(PRODUCT_OUT)/logo.img,$(1))
	$(call aml-copy-file,$(PRODUCT_OUT)/boot.img,$(1))
	$(call aml-copy-file,$(PRODUCT_OUT)/dtb.img,$(1))
	$(call aml-copy-file,$(PRODUCT_OUT)/dtbo.img,$(1))
	$(call aml-copy-file,$(PRODUCT_OUT)/oem.img,$(1))
	$(call aml-copy-file,$(PRODUCT_OUT)/$(3),$(1),super.img)
	$(call aml-copy-file,$(PRODUCT_OUT)/vbmeta.img,$(1))
	$(call aml-copy-file,$(PRODUCT_OUT)/vbmeta_system.img,$(1))
	$(call aml-copy-file,$(PRODUCT_OUT)/vendor_boot.img,$(1))
	$(call aml-copy-file,$(PRODUCT_OUT)/$(4),$(1),misc.img)
	$(hide) $(AML_IMAGE_TOOL) -r2 $(1)/image.cfg $(1)/ $@
	$(hide) rm -rf $(1)
	$(hide) echo " $@ created"
endef

NEEDED_IMAGES := \
    boot.img \
    dtb.img \
    dtbo.img \
    logo.img \
    oem.img \
    vbmeta.img \
    vbmeta_system.img \
    vendor_boot.img

FACTORY_FILES := \
    $(FACTORY_PATH)/aml_sdc_burn.ini \
    $(FACTORY_PATH)/platform.conf \
    $(VENDOR_PATH)/radio/bootloader.img \
    $(VENDOR_PATH)/factory/gpt.bin \
    $(VENDOR_PATH)/factory/odm_ext_a.PARTITION \
    $(VENDOR_PATH)/factory/u-boot.bin.sd.bin.signed \
    $(VENDOR_PATH)/factory/u-boot.bin.usb.signed \
    $(VENDOR_PATH)/factory/usb_flow.aml

$(INSTALLED_AML_INSTALL_PACKAGE_TARGET): $(addprefix $(PRODUCT_OUT)/,$(NEEDED_IMAGES) super_empty.img misc.img) $(FACTORY_FILES) $(FACTORY_PATH)/image_install.cfg $(ACP) $(AML_IMAGE_TOOL)
	$(call aml-build-package,$(PRODUCT_INSTALL_OUT),image_install.cfg,super_empty.img,misc.img)

.PHONY: aml_install
aml_install: $(INSTALLED_AML_INSTALL_PACKAGE_TARGET)

$(INSTALLED_AML_UPGRADE_PACKAGE_TARGET): $(addprefix $(PRODUCT_OUT)/,$(NEEDED_IMAGES) super.img misc_upgrade.img) $(FACTORY_FILES) $(FACTORY_PATH)/image_upgrade.cfg $(ACP) $(AML_IMAGE_TOOL)
	$(call aml-build-package,$(PRODUCT_UPGRADE_OUT),image_upgrade.cfg,super.img,misc_upgrade.img)

.PHONY: aml_upgrade
aml_upgrade: $(INSTALLED_AML_UPGRADE_PACKAGE_TARGET)

BUILT_TARGET_FILES_ZIPROOT := $(call intermediates-dir-for,PACKAGING,target_files)/$(TARGET_PRODUCT)-target_files
$(BUILT_TARGET_FILES_ZIPROOT).zip: $(BUILT_TARGET_FILES_ZIPROOT)/IMAGES/aml_install_package.img

$(BUILT_TARGET_FILES_ZIPROOT)/IMAGES/aml_install_package.img: $(BUILT_TARGET_FILES_ZIPROOT).zip.list $(PRODUCT_OUT)/aml_install_package.img
	@mkdir -p $(dir $@)
	@cp $(PRODUCT_OUT)/aml_install_package.img $@
	@echo $@ >> $(BUILT_TARGET_FILES_ZIPROOT).zip.list

INSTALLED_RADIOIMAGE_TARGET += $(INSTALLED_AML_INSTALL_PACKAGE_TARGET)

$(BUILT_TARGET_FILES_DIR): $(INSTALLED_RADIOIMAGE_TARGET)

endif
