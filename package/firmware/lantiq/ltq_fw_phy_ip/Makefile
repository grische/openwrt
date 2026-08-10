# SPDX-License-Identifier: GPL-2.0-or-later

include $(TOPDIR)/rules.mk

PKG_NAME:=ltq_fw_phy_ip
PKG_VERSION:=8.5.2.10
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://gitlab.com/prpl-foundation/intel/ltq_fw_phy_ip.git
PKG_SOURCE_VERSION:=178c46f36e398ddc54748c61ddf1d537ddc319d1
PKG_MIRROR_HASH:=bb64c6de8cf9062248db1f5bbb71572d159da0845b078be925fede14ca037b56

PKG_FLAGS:=nonshared
PKG_LICENSE:=Lantiq-Software-License-Agreement
PKG_LICENSE_FILES:=LICENSE

include $(INCLUDE_DIR)/package.mk

define Package/xrx500-phy11g-firmware
  SECTION:=firmware
  CATEGORY:=Firmware
  TITLE:=xRx500 Gigabit Ethernet PHY Firmware
  DEPENDS:=@TARGET_intel_mips
  DEFAULT:=n
endef

define Package/xrx500-phy11g-firmware/description
  This package contains firmware for the Gigabit Ethernet PHYs integrated in
  the xRx500/GRX350 SoC. The driver requests it as lantiq/xrx500-phy-fw.bin,
  so the rev A21 blob is installed under that name.
endef

define Build/Compile
endef

define Package/xrx500-phy11g-firmware/install
	$(INSTALL_DIR) $(1)/lib/firmware/lantiq
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/LICENSE \
		$(1)/lib/firmware/lantiq/xrx500-phy-fw.bin.LICENSE
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/xRx5xx/ltq_fw_PHY11G_IP_1v1_xRx5xx_A21_R8548.bin \
		$(1)/lib/firmware/lantiq/xrx500-phy-fw.bin
endef

$(eval $(call BuildPackage,xrx500-phy11g-firmware))
