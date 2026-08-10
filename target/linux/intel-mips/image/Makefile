# SPDX-License-Identifier: GPL-2.0-only
#
# Image build infrastructure for the intel-mips target.
# Minimal-by-design — only the macros the FB7560 device (seale.mk) needs.

include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/image.mk

# AVM EVA bootloader expects an additional sentinel squashfs trailer
# (a dummy 64k squashfs root) at the end of the kernel partition to
# accept the image as valid. Same eva.dummy.squashfs as lantiq's.
define Build/append-avm-fakeroot
	cat ./eva.dummy.squashfs >> $@
endef

# AVM urlader's DTB-table scanner needs a lookup table at the kernel
# entry address. inject_avm_preamble.py finds embedded FDTs in the
# kernel binary, reads each one's /avm-hw-revision/subrevision, and
# writes the table into the kernel's first 0x400 zero-padding bytes
# (with a MIPS BEQ branch at +0x00 that skips the table to land at
# +0x10 = the real kernel entry). Without this, the urlader rejects
# the boot with "Device Tree Blob for SubRevision N not found". The script
# reads only the FDT layout, so it is independent of the kernel version.
define Build/avm-preamble
	$(TOPDIR)/target/linux/intel-mips/image/inject_avm_preamble.py \
		$@ $@.preamble $(KERNEL_LOADADDR) && \
		mv $@.preamble $@
endef

# The AVM urladers on this target accept only the dual-kernel EVA TI-record
# format; the single-kernel image produced by the generic Build/eva-image
# (lzma2eva) in include/image-commands.mk is refused. The second kernel of
# the pair is not padding: it is AVM's bootcore, which runs on the 4Kec boot
# core and programs the NGI fabric before handing control to the interAptiv
# kernel. It has no free
# replacement and may not be redistributed, so it is carved out of an AVM
# firmware image at build time and staged into STAGING_DIR_IMAGE by a
# per-device package (see package/boot/avm-fritz7560-bootcore). This tree
# holds the packing recipe, not the payload.
#
# A device names the staged file in EVA_BOOTCORE and supplies the bootcore
# record's addresses in EVA_BOOTCORE_LOADADDR and EVA_BOOTCORE_ENTRY;
# `eva-image info` on the source firmware image prints both.
DEVICE_VARS += EVA_BOOTCORE EVA_BOOTCORE_LOADADDR EVA_BOOTCORE_ENTRY

# eva-image (built as a host tool from tools/eva-kernel-image) takes raw kernel
# binaries and does the LZMA compression itself, so the KERNEL chain must not
# pre-compress with `| lzma`.
define Build/eva-dual-kernel
	$(STAGING_DIR_HOST)/bin/eva-image pack \
		--output $@.eva \
		--kernel1 $@ \
		--load1 $(KERNEL_LOADADDR) \
		--entry1 $(KERNEL_ENTRY) \
		--kernel2 $(STAGING_DIR_IMAGE)/$(EVA_BOOTCORE) \
		--load2 $(EVA_BOOTCORE_LOADADDR) \
		--entry2 $(EVA_BOOTCORE_ENTRY) \
	&& mv $@.eva $@
endef

# Per-device defaults. The xrx500 NAND geometry (2 KB page, 128 KB block)
# matches the FB7560's Macronix MX30LF1GE8AB observed in the boot log.
define Device/Default
  PROFILES = Default
  KERNEL_DEPENDS = $$(wildcard $(DTS_DIR)/$$(DEVICE_DTS).dts)
  KERNEL_INITRAMFS_NAME = $$(KERNEL_NAME)-initramfs
  KERNEL := kernel-bin | append-dtb | lzma | uImage lzma
  KERNEL_INITRAMFS := kernel-bin | append-dtb | lzma | uImage lzma
  FILESYSTEMS := squashfs
  SOC := $(DEFAULT_SOC)
  DEVICE_DTS = $$(SOC)_$(1)
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  SUBPAGESIZE := 512
  IMAGES := sysupgrade.bin
  IMAGE/sysupgrade.bin := append-kernel | append-rootfs | pad-rootfs | check-size | append-metadata
endef

# AVM device family template — wraps the EVA build pipeline plus the
# post-rootfs append-avm-fakeroot sentinel. Same shape as lantiq's
# Device/AVM (target/linux/lantiq/image/Makefile:132). The per-device
# block (see seale.mk) overrides KERNEL with eva-dual-kernel.
define Device/AVM
  DEVICE_VENDOR := AVM
  KERNEL := kernel-bin | append-dtb | avm-preamble | eva-dual-kernel
  KERNEL_INITRAMFS := $$(KERNEL)
  IMAGE/sysupgrade.bin := append-kernel | pad-to 64k | append-avm-fakeroot | \
	append-rootfs | pad-rootfs | check-size | append-metadata
endef

# NAND-rooted device family template. Per-device blocks that include
# `$(Device/NAND)` AFTER `$(Device/AVM)` inherit a sysupgrade.bin rule
# that flashes the kernel partition (avm-fakeroot trailer preserved
# so EVA can validate the kernel slot at first-boot) and then appends
# the ubinize-image.sh-produced UBI image for the rootfs partition.
# Order is load-bearing: makefile late-binding means Device/NAND's
# IMAGE/sysupgrade.bin rule overrides Device/AVM's append-rootfs rule.
# Adds ubifs to FILESYSTEMS so mkfs.ubifs runs and produces the
# rootfs image consumed by append-ubi.
define Device/NAND
  FILESYSTEMS += ubifs
  IMAGE/sysupgrade.bin := append-kernel | pad-to 64k | append-avm-fakeroot | \
	pad-to $$$$(KERNEL_SIZE) | append-ubi | check-size | append-metadata
endef

ifeq ($(SUBTARGET),xrx500)
DEFAULT_SOC := xrx500
# Subtarget-level UBIFS geometry for the MX30LF1GE8AB NAND on FB7560
# (and any future xrx500 NAND device): 2 KiB min-I/O, 126 KiB logical
# erase block (128 KiB physical EB minus the 2-page UBI header), and
# max-LEBs rounded up to 4096 for headroom (the 107 MiB ubi partition
# needs ~864 LEBs at 126 KiB). Same shape as the lantiq xrx200 UBIFS
# geometry; lives at subtarget scope (not per-device) because the
# whole xrx500 subtarget shares one NAND geometry.
UBIFS_OPTS := -m 2048 -e 126KiB -c 4096
include seale.mk
endif

$(eval $(call BuildImage))
