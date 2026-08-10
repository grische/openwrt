# SPDX-License-Identifier: GPL-2.0-only
#
# Sysupgrade platform hooks for intel-mips/xrx500.
#
# These are still placeholders: installation goes through the EVA
# bootloader over TFTP, not through sysupgrade. platform_do_upgrade()
# calls default_do_upgrade(), which writes a plain flash image, whereas
# the xrx500 sysupgrade image is a kernel partition plus a UBI image on
# NAND and needs nand_do_upgrade(). platform_check_image() likewise
# accepts anything rather than validating the board.

REQUIRE_IMAGE_METADATA=1

platform_check_image() {
	return 0
}

platform_do_upgrade() {
	default_do_upgrade "$1"
}
