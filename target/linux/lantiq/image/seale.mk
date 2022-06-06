define Device/avm_fritz7560
  $(Device/AVM)
  $(Device/NAND)
  DEVICE_MODEL := FRITZ!Box 7560
  KERNEL_SIZE := 4096k
  IMAGE_SIZE := 49152k
  DEVICE_PACKAGES := kmod-ath9k kmod-usb3 kmod-owl-loader wpad-basic-wolfssl fritz-tffs-nand fritz-caldata
endef
TARGET_DEVICES += avm_fritz7560
