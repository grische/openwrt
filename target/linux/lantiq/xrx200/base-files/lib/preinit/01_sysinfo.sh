set_sysinfo_xrx200_for_fritz7360_model() {
    local board_name=$1
    local model
    local urlader_version urlader_memsize urlader_flashsize
    local hexdump_format='4/1 "%02x""\n"'

    # Values are based on urlader-parser-py
    # https://github.com/grische/urlader-parser-py/blob/42970bf8dec7962317df4ff734c57ebf36df8905/parser.py#L77-L84
    urlader_version="$(dd if=/dev/mtd0ro bs=1 skip=$((0x580+0x0)) count=4 | hexdump -e "${hexdump_format}")"
    if [ "${urlader_version}" != "00000003" ]; then
        logger -s -p warn -t sysinfo-xrx200 "unexpected urlader version found: ${urlader_version}"
        return
    fi

    urlader_memsize="$(dd if=/dev/mtd0ro bs=1 skip=$((0x580+0x4)) count=4 | hexdump -e "${hexdump_format}")"
    if [ "${urlader_memsize}" != "08000000" ]; then
        logger -s -p warn -t sysinfo-xrx200 "unexpected memsize found: ${urlader_memsize}"
        return
    fi

    urlader_flashsize="$(dd if=/dev/mtd0ro bs=1 skip=$((0x580+0x8)) count=4 | hexdump -e "${hexdump_format}")"
     case "${urlader_flashsize}" in
        "02000000")    # 32MB
            # see vr9_avm_fritz7360-v2.dts
            board_name="avm,fritz7360-v2"
            model="AVM FRITZ!Box 7360 V2"
            ;;
        "01000000")    # 16MB
            # see vr9_avm_fritz7360sl.dts
            board_name="avm,fritz7360sl"
            model="AVM FRITZ!Box 7360 SL"
            ;;
        *)
            logger -s -p warn -t sysinfo-xrx200 "unexpected flashsize found: ${urlader_flashsize}"
            return
            ;;
    esac

    logger -s -p notice -t sysinfo-xrx200 "detected ${board_name} from urlader partition /dev/mtd0ro. Enforcing model ${model}."
    echo "${board_name}" > /tmp/sysinfo/board_name
    echo "${model}" > /tmp/sysinfo/model
}

do_sysinfo_xrx200() {
    local reported_board board_name model

    [ -d /proc/device-tree ] || return
    reported_board="$(strings /proc/device-tree/compatible | head -1)"

    mkdir -p /tmp/sysinfo
    # 7360 is notoriously known for not writing "v2" on their labels and many
    # routers have flashed the wrong firmware with the wrong flash layout.
    # We ensure that the underlying hardware is reported correctly, so that
    # future upgrades will use the correct flash layout.
    # Using 7360v2 hardware, an upgrade from a 7360v1/sl firmware to a 7360v2
    # is working.
    case "${reported_board}" in
        *7360*)
            set_sysinfo_xrx200_for_fritz7360_model "${reported_board}"
            ;;
        *)
            # fall back to OpenWRT's sysinfo detection
            return
            ;;
    esac
}

boot_hook_add preinit_main do_sysinfo_xrx200
