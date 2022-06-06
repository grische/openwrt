define Device/avm_fritz7560
  $(Device/dsa-migration)
  $(Device/AVM)
  $(Device/NAND)
  DEVICE_MODEL := FRITZ!Box 7560
  KERNEL_SIZE := 4096k
  IMAGE_SIZE := 49152k
  DEVICE_PACKAGES := kmod-usb3 fritz-tffs kmod-avm-wasp kmod-avm-wasp \
	-kmod-owl-loader
endef
TARGET_DEVICES += avm_fritz7560
