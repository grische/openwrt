# SPDX-License-Identifier: GPL-2.0-only
"""Root entry point of the eva-image zipapp; see ../Makefile."""

from __future__ import annotations

import sys

from eva_kernel_image.cli import main

raise SystemExit(main(sys.argv[1:]))
