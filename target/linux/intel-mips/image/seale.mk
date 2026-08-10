# SPDX-License-Identifier: GPL-2.0-only
#
# Image rules for the AVM FRITZ!Box 7560 (xrx500/GRX350 subtarget).
#
# Subtarget KERNEL_LOADADDR / KERNEL_ENTRY. There is no target-wide
# default to inherit, and the generic MIPS value is wrong for GRX350
# under EVA in any case. The kernel's arch/mips/intel-mips/Platform sets
#   load-$(CONFIG_INTEL_MIPS) = 0xffffffff80500000   (CONFIG_EVA=y path)
# CONFIG_INTEL_MIPS in v6.18 selects CPU_MIPS32_3_5_EVA which selects
# EVA, so the EVA branch is taken. The 64-bit sign-extended form
# 0xffffffff80500000 truncates to 0x80500000 in OpenWrt's 32-bit
# KERNEL_LOADADDR makefile variable. This matches the canonical GRX350
# PHYS_OFFSET 0x20000000 + 0x500000 offset mapped into KSEG0.
KERNEL_LOADADDR := 0x80500000
KERNEL_ENTRY := 0x80500000

define Device/avm_fritz7560
  $(Device/AVM)
  # Device/NAND MUST be invoked AFTER Device/AVM. Makefile late binding:
  # whichever macro's IMAGE/sysupgrade.bin assignment runs last wins, and
  # we want the Device/NAND one (append-kernel | pad-to KERNEL_SIZE |
  # append-ubi | check-size | append-metadata) rather than Device/AVM's
  # append-rootfs | pad-rootfs chain. Swapping the order would silently
  # produce a sysupgrade.bin that the FB7560 cannot mount as ubifs at
  # first boot.
  $(Device/NAND)
  DEVICE_VENDOR := AVM
  DEVICE_MODEL := FRITZ!Box 7560
  SOC := xrx500
  # The image embeds AVM's bootcore (see EVA_BOOTCORE below), which may not
  # be redistributed, so the buildbots must not build or publish this device.
  # Selecting it in menuconfig pulls in package/boot/avm-fritz7560-bootcore
  # and builds the image locally.
  DEFAULT := n
  # Explicit DEVICE_DTS override. The Device/Default block in image/Makefile
  # sets DEVICE_DTS = $$(SOC)_$(1) which would auto-resolve to
  # xrx500_avm_fritz7560, but the board DTS lives at
  # arch/mips/boot/dts/intel-mips/seale_avm_fritz7560.dts. Use the
  # bare name (no subdir) so append-dtb's `cat $(KDIR)/image-$(DEVICE_DTS).dtb`
  # path resolves cleanly; include the subdir in DEVICE_DTS_DIR below.
  DEVICE_DTS := seale_avm_fritz7560
  # The kernel-side DTS lives at arch/mips/boot/dts/intel-mips/. With
  # DEVICE_DTS unprefixed (above), include the intel-mips/ subdir here so
  # image.mk:Image/BuildDTB still finds the source file.
  # NOTE: this image-side DTB is technically unused at runtime because
  # BUILTIN_DTB=y bakes the same DTB into vmlinux; but image.mk's
  # Device/Build/kernel auto-generates a dtb compile rule for every
  # DEVICE_DTS entry regardless of BUILTIN_DTB, so the rule must still find
  # the source file or the install step aborts.
  DEVICE_DTS_DIR := $(LINUX_DIR)/arch/mips/boot/dts/intel-mips
  # append-dtb concatenates the DTS-compiled DTB after vmlinux.bin. The
  # kernel does not read it — appended-DTB lookup is off and the built-in
  # DTB is used instead (see ../../config-6.18). The copy is there to give
  # EVA's DTB-selection fallback something to overwrite that is not the
  # built-in one; ../../config-6.18 explains the substitution in full.
  # avm-preamble injects a DTB lookup table into the kernel's entry padding
  # so AVM's urlader finds the SubRevision-1 DTB (from avm-hw-revision node)
  # inside the binary. MUST run BEFORE eva-dual-kernel — the preamble scans
  # raw FDT magic bytes which would be unreachable after LZMA compression.
  # eva-dual-kernel packs the raw kernel + AVM's bootcore into the
  # dual-kernel EVA TI-record format the FB7560 urlader requires. It
  # performs LZMA compression internally, so no `| lzma` step is added.
  KERNEL := kernel-bin | append-dtb | avm-preamble | eva-dual-kernel
  KERNEL_INITRAMFS := $$(KERNEL)
  # AVM's bootcore, staged into STAGING_DIR_IMAGE by
  # package/boot/avm-fritz7560-bootcore and packed as the second kernel by
  # eva-dual-kernel. The addresses are the ones AVM's own image carries for
  # that record, readable with `eva-image info`, and are fixed by the blob:
  # 0x8DFFFFFC is KSEG0 for physical 0x2DFFFFFC (PHYS_OFFSET 0x20000000), so
  # the bootcore runs from just below the top 32 MiB of the 256 MiB part,
  # clear of the low 128 MiB the memory node hands to Linux.
  EVA_BOOTCORE := avm_fritz7560-bootcore.bin
  EVA_BOOTCORE_LOADADDR := 0x8DFFFFFC
  EVA_BOOTCORE_ENTRY := 0x8E691770
  # KERNEL_SIZE matches the kernel partition size from the AVM 5-partition
  # map (seale_avm_fritz7560.dtsi partition@500000 / partition@d00000 — both
  # are 0x800000 = 8 MiB). The reserved-kernel slot is intentionally NOT
  # used here; sysupgrade flashes only the primary kernel partition.
  KERNEL_SIZE := 8192k
  # IMAGE_SIZE is the partition-size cap (0x6b00000 = 109568 KiB = the ubi
  # partition size from the AVM map). check-size enforces this upper bound
  # on sysupgrade.bin. NOTE: this is NOT the rootfs-usable bound — UBI
  # consumes some PEBs for its own metadata (typically ~5 PEBs * 128 KiB =
  # 640 KiB for the volume table + EC headers + VID headers, plus the
  # UBINIZE_OPTS -E 5 reserved PEBs below); the rootfs-usable cap is
  # enforced at mkfs.ubifs time via UBIFS_OPTS, not in IMAGE_SIZE.
  IMAGE_SIZE := 109568k
  # 5 reserved erase blocks for bad-block replacement on the Macronix
  # MX30LF1GE8AB. Matches the lantiq avm_fritz3370 precedent (vr9.mk).
  UBINIZE_OPTS := -E 5
  # The GPHY firmware is shipped by the xrx500-phy11g-firmware package, which
  # installs it as /lib/firmware/lantiq/xrx500-phy-fw.bin — the exact path the
  # DT 'firmware' property in seale_avm_fritz7560.dtsi's phy-xrx500 node names,
  # and therefore the string request_firmware() looks up. Renaming either side
  # alone leaves the GPHYs in ROM mode and the LAN ports dead.
  #
  # Blob: ltq_fw_PHY11G_IP_1v1_xRx5xx_A21_R8548.bin, sha256
  # d8269703afd369c28a6aeeb65d2751334e38e2228816eda0bdb11c2475b0df33.
  #
  # It has to be the xRx5xx variant, not the xRx3xx one carried in the
  # FRITZ.Box_7560-07.11 GPL drop. AVM's own driver loads the xRx5xx blob
  # into the LAN GPHYs and that is the one that brings the links up at
  # 1Gbps; the xRx3xx blob loads without complaint but leaves them down.
  DEVICE_PACKAGES := fritz-tffs xrx500-phy11g-firmware
endef
TARGET_DEVICES += avm_fritz7560
