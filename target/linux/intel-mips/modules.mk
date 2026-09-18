# SPDX-License-Identifier: GPL-2.0-only
#
# Target level, which is also the only level that would work: package/kernel/
# linux/Makefile builds its list by globbing target/linux/* exactly one level
# deep, so a modules.mk under a subtarget directory would never be read at all.
# DEPENDS keeps these packages off other targets; which board carries which is
# decided per device in image/seale.mk.

define KernelPackage/leds-lgm-sso
  SUBMENU:=$(LEDS_MENU)
  TITLE:=Intel SSO LED controller support
  KCONFIG:=CONFIG_LEDS_LGM
  FILES:=$(LINUX_DIR)/drivers/leds/blink/leds-lgm-sso.ko
  DEPENDS:=@TARGET_intel_mips
  #
  # The trailing 1 is the boot flag: it puts the module in
  # /etc/modules-boot.d rather than /etc/modules.d, so preinit loads it
  # instead of the normal modules stage. That matters here because the
  # boot-progress and failsafe states are set during preinit, and a missing
  # LED is silent -- led_set_attr() in lib/functions/leds.sh tests for the
  # sysfs file and skips the write when it is absent, so a late module means
  # a dark panel and no diagnostic. The DT carries default-state = "on" for
  # the power lamp to cover the window before even this load happens.
  #
  AUTOLOAD:=$(call AutoLoad,60,leds-lgm-sso,1)
endef

define KernelPackage/leds-lgm-sso/description
  Kernel support for the Serial Shift Output LED controller in the GSWIP
  block of Intel MIPS SoCs. Drives the FRITZ!Box 7590's front panel, whose
  lamps hang off a shift register rather than off SoC GPIOs.
endef

$(eval $(call KernelPackage,leds-lgm-sso))

define KernelPackage/intel-xrx500-mdio
  SUBMENU:=$(NETWORK_DEVICES_MENU)
  TITLE:=Intel xRX500 GPHY firmware loader and MDIO bus
  KCONFIG:=CONFIG_INTEL_XRX500_MDIO
  FILES:=$(LINUX_DIR)/drivers/net/ethernet/lantiq/intel-xrx500-mdio.ko
  DEPENDS:=@TARGET_intel_mips +xrx500-phy11g-firmware
  #
  # The trailing 1 is the boot flag: /etc/modules-boot.d rather than
  # /etc/modules.d, so preinit loads it. Nothing links the proprietary
  # GPHY firmware into the kernel image, so the loader has to run with a
  # mounted rootfs -- and it has to run before the network comes up,
  # because until the PHYs answer MDIO there are no netdevs at all and
  # failsafe has no LAN port.
  #
  AUTOLOAD:=$(call AutoLoad,41,intel-xrx500-mdio,1)
endef

define KernelPackage/intel-xrx500-mdio/description
  GPHY firmware loader and MDIO bus driver for the Gigabit PHYs integrated
  in the Intel xRX500/GRX350 SoC. The PHYs stay in ROM mode until the
  firmware is loaded, so without this package no LAN port comes up.
endef

$(eval $(call KernelPackage,intel-xrx500-mdio))
