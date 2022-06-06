#!/bin/sh

xrx500_board() {
	grep "^machine" /proc/cpuinfo | sed "s/^machine\s*:\s\([A-Za-z0-9]\+\).*$/\1/"
}

xrx500_soc_family() {
	grep "^system type" /proc/cpuinfo | sed "s/^system type\s*:\s\([A-Za-z0-9]\+\).*/\1/g"
}