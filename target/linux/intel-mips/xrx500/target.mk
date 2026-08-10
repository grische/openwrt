ARCH:=mips
SUBTARGET:=xrx500
BOARDNAME:=XRX500
FEATURES+=nand usb pci pcie targz
# Drop the mips16 default that include/target.mk adds for CPU_MIPS32_R2.
# Userspace binaries built with -mips16 hit SIGBUS on this kernel at init.
FEATURES := $(filter-out mips16,$(FEATURES))
CPU_TYPE:=24kc

DEFAULT_PACKAGES+=kmod-leds-gpio \
	kmod-gpio-button-hotplug

define Target/Description
	Intel/Lantiq GRX350 (xRX500 family) -- FB7560 target
endef
