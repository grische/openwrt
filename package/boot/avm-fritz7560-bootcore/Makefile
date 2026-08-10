# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

PKG_NAME:=avm-fritz7560-bootcore
PKG_VERSION:=07.30
PKG_RELEASE:=1

# The FRITZ!Box 7560's urlader accepts only the dual-kernel EVA TI-record
# format, and the second kernel in that image is AVM's bootcore: it runs on
# the 4Kec boot core before Linux and programs the NGI fabric before handing
# control to the interAptiv kernel. Neither a stub nor a second copy of the
# primary kernel boots in its place, and there is no free replacement, so the
# bootcore has to come out of an AVM firmware image.
#
# That image is AVM proprietary. Its var/info.txt states that the firmware
# package "shall not be copied, distributed or otherwise made publicly
# available", which constrains three things here:
#
#   - it is not carried in this tree;
#   - PKG_MIRROR_HASH is deliberately unset, so it is never fetched from, or
#     archived on, the OpenWrt source mirrors;
#   - an image built from it embeds the bootcore, so the device that uses
#     this package is DEFAULT := n and the buildbots never publish one.
#
# A user who already holds the file, from AVM or dumped from their own
# device, can place it in $(DL_DIR); nothing is then downloaded.
PKG_SOURCE:=FRITZ.Box_7560-$(PKG_VERSION).image
PKG_SOURCE_URL:=https://download.avm.de/fritzbox/fritzbox-7560/deutschland/fritz.os
PKG_HASH:=69b4ed39b7fce9ab0f66acf371370ecb1c35b655bf0ffc4d2062bf7a9e239f49

PKG_FLAGS:=nonshared
PKG_LICENSE:=AVM-Proprietary

include $(INCLUDE_DIR)/package.mk

define Package/avm-fritz7560-bootcore
  SECTION:=boot
  CATEGORY:=Boot Loaders
  TITLE:=AVM FRITZ!Box 7560 EVA bootcore
  DEPENDS:=@TARGET_intel_mips_xrx500
  DEFAULT:=y if TARGET_DEVICE_intel_mips_xrx500_DEVICE_avm_fritz7560
  HIDDEN:=1
endef

define Package/avm-fritz7560-bootcore/description
  Extracts AVM's bootcore from a stock FRITZ!Box 7560 firmware image and
  stages it for the image build, which packs it as the second kernel of the
  dual-kernel EVA image the device's urlader requires. Nothing is installed
  into the root filesystem.
endef

# The firmware image is a plain GNU tar. The EVA image that gets written to
# the device's kernel partition sits inside it as ./var/tmp/kernel.image.
define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(TAR) -xOf $(DL_DIR)/$(PKG_SOURCE) ./var/tmp/kernel.image \
		> $(PKG_BUILD_DIR)/kernel.image
endef

define Build/Configure
endef

# eva-image is built as a host tool from tools/eva-kernel-image. Its extract
# decompresses both TI records to kernel1.bin and kernel2.bin and writes a
# metadata.json holding each record's load and entry address. Only
# the secondary record, the bootcore, is wanted here; its two addresses are
# what seale.mk passes back to eva-image pack.
define Build/Compile
	rm -rf $(PKG_BUILD_DIR)/eva
	$(STAGING_DIR_HOST)/bin/eva-image extract $(PKG_BUILD_DIR)/kernel.image \
		-o $(PKG_BUILD_DIR)/eva
endef

# Staged, not installed: this is an image-build input, like the artifacts the
# u-boot and trusted-firmware packages stage. The resulting .ipk is empty.
define Package/avm-fritz7560-bootcore/install
	$(INSTALL_DIR) $(STAGING_DIR_IMAGE)
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/eva/kernel2.bin \
		$(STAGING_DIR_IMAGE)/avm_fritz7560-bootcore.bin
endef

$(eval $(call BuildPackage,avm-fritz7560-bootcore))
