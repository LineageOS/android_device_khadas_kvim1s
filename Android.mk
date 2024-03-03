#
# Copyright (C) 2021-2024 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

ifneq ($(filter kvim1s kvim1s_car kvim1s_tab, $(TARGET_DEVICE)),)

LOCAL_PATH := $(call my-dir)
include $(call all-makefiles-under,$(LOCAL_PATH))

include $(LOCAL_PATH)/factory.mk

-include vendor/khadas/kvim1s/firmware.mk

endif
