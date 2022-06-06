ARCH:=mips
SUBTARGET:=xrx500
BOARDNAME:=XRX500
FEATURES+=atm nand ramdisk
CPU_TYPE:=24kc

DEFAULT_PACKAGES+=kmod-leds-gpio \
	kmod-gpio-button-hotplug \
	ltq-vdsl-app \
	ppp-mod-pppoa

define Target/Description
	Intel GRX500 platform
endef
