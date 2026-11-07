#!/usr/bin/env python3
#
# Generate a misc partition image with a valid A/B bootloader_control block.
#
# The factory packages write every partition to slot A, but they used to leave
# the A/B metadata in misc alone: the stock factory/bootfiles/misc.img was only
# 512 bytes, so it could never reach the bootloader_control at offset 2048, and
# image_upgrade.cfg did not flash misc at all. After an OTA has switched the
# board to slot B, U-Boot keeps reading active_slot=_b out of misc while the
# freshly flashed images all live in slot A - which bootloops.
#
# misc is the single source of truth for the slot: U-Boot's get_valid_slot
# (bootloader/uboot/cmd/amlogic/cmd_bootctl_vab.c:do_GetValidSlot) derives the
# active_slot / boot_part / slot-suffixes environment variables from it on every
# boot, so resetting misc is enough - the U-Boot environment needs no fixing up.
#
# Layout written here (see cmd_bootctl_vab.c and
# hardware/interfaces/boot/1.1/default/boot_control/include/private/
# boot_control_definition.h - both agree on a 32-byte packed struct):
#
#   0      bootloader_message.command  ("boot-recovery" or empty)
#   2048   bootloader_control          (magic BCAB, slot A active)
#   16384  wipe package area           (zeroed)
#   32768  misc_virtual_ab_message     (zeroed - kills any pending VABC merge)
#
# Everything outside the bootloader_control is deliberately zero: a factory
# flash has just replaced super, so a leftover snapshot-merge state or a stale
# recovery command would be describing partitions that no longer exist.

import argparse
import struct
import zlib

BOOT_CTRL_MAGIC = 0x42414342  # "BCAB"
BOOT_CTRL_VERSION = 1
AB_METADATA_MISC_PARTITION_OFFSET = 2048
# 64 KiB covers bootloader_message + vendor space + wipe package + system space.
# The misc partition itself is 2 MiB in gpt.bin; the rest is unused.
MISC_IMAGE_SIZE = 64 * 1024


def slot_metadata(priority, tries_remaining, successful_boot):
    """Pack struct slot_metadata (2 bytes, packed, little endian bitfields)."""
    return bytes([
        (priority & 0xF) | ((tries_remaining & 0x7) << 4) |
        ((successful_boot & 0x1) << 7),
        0,  # verity_corrupted:1, reserved:7
    ])


def bootloader_control(active_slot):
    suffix = b"_a" if active_slot == 0 else b"_b"

    slots = b""
    for i in range(4):
        if i >= 2:
            slots += slot_metadata(0, 0, 0)  # unused slot, unbootable
        elif i == active_slot:
            # Priority 15 so it wins outright. tries_remaining must be non-zero:
            # U-Boot's slot_is_bootable() looks at nothing else, so a slot with
            # successful_boot=1 but no tries left is treated as unbootable and
            # sends get_valid_slot down the roll-back-to-the-other-slot path.
            slots += slot_metadata(15, 7, 1)
        else:
            # Bootable but lower priority - same as U-Boot's boot_info_reset().
            slots += slot_metadata(7, 7, 0)

    ctrl = struct.pack(
        "<4sIBBBB8s8s",
        suffix,            # slot_suffix[4]
        BOOT_CTRL_MAGIC,   # magic
        BOOT_CTRL_VERSION, # version
        2,                 # nb_slot:3 | recovery_tries_remaining:3
        0,                 # merge_status:3 (None - no pending snapshot merge)
        0,                 # reserved0[1] (roll_flag in the Amlogic struct)
        slots,             # slot_info[4]
        b"\0" * 8,         # reserved1[8] (merge_flag et al in Amlogic's struct)
    )
    assert len(ctrl) == 28, len(ctrl)
    return ctrl + struct.pack("<I", zlib.crc32(ctrl) & 0xFFFFFFFF)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("output")
    ap.add_argument("--slot", choices=["a", "b"], default="a",
                    help="slot to mark active (default: a)")
    ap.add_argument("--command", default="",
                    help='bootloader_message.command, e.g. "boot-recovery"')
    args = ap.parse_args()

    command = args.command.encode()
    if len(command) > 31:
        ap.error("command must be at most 31 bytes")

    img = bytearray(MISC_IMAGE_SIZE)
    img[0:len(command)] = command

    ctrl = bootloader_control(0 if args.slot == "a" else 1)
    off = AB_METADATA_MISC_PARTITION_OFFSET
    img[off:off + len(ctrl)] = ctrl

    with open(args.output, "wb") as f:
        f.write(img)


if __name__ == "__main__":
    main()
