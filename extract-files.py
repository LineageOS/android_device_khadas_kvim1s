#!/usr/bin/env -S PYTHONPATH=../../../tools/extract-utils python3
#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

from extract_utils.main import (
    ExtractUtils,
    ExtractUtilsModule,
)

module = ExtractUtilsModule(
    'kvim1s',
    'khadas',
    add_firmware_proprietary_file=True,
    add_factory_proprietary_file=True,
)

if __name__ == '__main__':
    utils = ExtractUtils.device_with_common(module, '../amlogic/ne-common', module.vendor)
    utils.run()
