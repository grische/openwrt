# SPDX-License-Identifier: GPL-2.0-only
#
# Intel MIPS (xRX500 / GRX500 family) target, named after the kernel-side
# arch/mips/intel-mips/ platform it builds for.
#
# This is a sibling of target/linux/lantiq/, not a subtarget of it. The
# kernel System type symbols CONFIG_INTEL_MIPS and CONFIG_LANTIQ sit in the
# same arch/mips/Kconfig choice block and are mutually exclusive, while
# OpenWrt's config merge keeps a parent's =y over a subtarget's "is not
# set". Placed under lantiq/, xrx500 would inherit CONFIG_LANTIQ=y and
# could not turn it off, breaking the kernel build.

include $(TOPDIR)/rules.mk

BOARD:=intel-mips
BOARDNAME:=Intel MIPS (xRX500 / GRX500)
FEATURES:=squashfs nand
SUBTARGETS:=xrx500

KERNEL_PATCHVER:=6.18

define Target/Description
	Build firmware images for Intel/Lantiq xRX500 (GRX350/GRX550) SoCs.
	First device: AVM FRITZ!Box 7560 (GRX350).
endef

include $(INCLUDE_DIR)/target.mk

$(eval $(call BuildTarget))
