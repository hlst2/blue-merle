#!/usr/bin/env ash

# Helper functions for blue-merle on the GL.iNet Mudi 7 (GL-E5800).
# Modem is Qualcomm Snapdragon X72 (Dragonwing MBB Gen 3) with two
# nano-SIM slots. All modem access goes through gl-sdk4's `gl_modem`
# helper rather than a hardcoded /dev/ttyUSB* path.


UNICAST_MAC_GEN () {
    loc_mac_numgen=`python3 -c "import random; print(f'{random.randint(0,2**48) & 0b111111101111111111111111111111111111111111111111:0x}'.zfill(12))"`
    loc_mac_formatted=$(echo "$loc_mac_numgen" | sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\)\(..\).*$/\1:\2:\3:\4:\5:\6/')
    echo "$loc_mac_formatted"
}

# Randomize BSSID for both 2.4 GHz and 5 GHz radios.
RESET_BSSIDS () {
    uci set wireless.@wifi-iface[1].macaddr=`UNICAST_MAC_GEN`
    uci set wireless.@wifi-iface[0].macaddr=`UNICAST_MAC_GEN`
    uci commit wireless
    # you need to reset wifi for changes to apply, i.e. executing "wifi"
}


RANDOMIZE_MACADDR () {
    # MAC clients see when connecting to the WiFi the device spawns.
    uci set network.@device[1].macaddr=`UNICAST_MAC_GEN`
    # MAC the upstream wifi sees in repeater mode.
    uci set glconfig.general.macclone_addr=`UNICAST_MAC_GEN`
    uci commit network
    # You need to restart the network, i.e. /etc/init.d/network restart
}

# Wrap `gl_modem AT` so callers can optionally specify a SIM slot.
# Usage: GL_MODEM_AT <slot|""> <AT command>
GL_MODEM_AT () {
    local slot="$1"
    shift
    if [ -n "$slot" ]; then
        gl_modem -s "$slot" AT "$@"
    else
        gl_modem AT "$@"
    fi
}

READ_ICCID () {
    local slot="$1"
    GL_MODEM_AT "$slot" AT+CCID
}

# Read the currently active SIM slot. Returns "1" or "2".
READ_SIM_SLOT () {
    local out
    out=$(gl_modem AT 'AT+QUIMSLOT?' 2>/dev/null)
    local slot
    slot=$(echo "$out" | grep -oE '\+QUIMSLOT:[[:space:]]*[12]' | grep -oE '[12]' | head -n1)
    if [ -z "$slot" ]; then
        # Fall back to GL.iNet's UCI representation if the AT query is
        # not implemented on the firmware build.
        slot=$(uci -q get glconfig.modem.sim_slot)
    fi
    [ -z "$slot" ] && slot=1
    echo "$slot"
}

# Switch to the requested SIM slot.
SET_SIM_SLOT () {
    local slot="$1"
    case "$slot" in
        1|2) ;;
        *) return 1 ;;
    esac
    gl_modem AT "AT+QUIMSLOT=${slot}" >/dev/null 2>&1
    uci -q set glconfig.modem.sim_slot="$slot"
    uci -q commit glconfig
}

READ_IMEI () {
    local slot="$1"
    local answer=1
    while [[ "$answer" -eq 1 ]]; do
            local imei=$(GL_MODEM_AT "$slot" AT+GSN | grep -w -E "[0-9]{14,15}")
            if [[ $? -eq 1 ]]; then
                    echo -n "Failed to read IMEI. Try again? (Y/n): "
                    read answer
                    case $answer in
                            n*) answer=0;;
                            N*) answer=0;;
                            *) answer=1;;
                    esac
                    if [[ $answer -eq 0 ]]; then
                            exit 1
                    fi
            else
                    answer=0
            fi
    done
    echo $imei
}

READ_IMSI () {
    local slot="$1"
    local answer=1
    while [[ "$answer" -eq 1 ]]; do
            local imsi=$(GL_MODEM_AT "$slot" AT+CIMI | grep -w -E "[0-9]{6,15}")
            if [[ $? -eq 1 ]]; then
                    echo -n "Failed to read IMSI. Try again? (Y/n): "
                    read answer
                    case $answer in
                            n*) answer=0;;
                            N*) answer=0;;
                            *) answer=1;;
                    esac
                    if [[ $answer -eq 0 ]]; then
                            exit 1
                    fi
            else
                    answer=0
            fi
    done
    echo $imsi
}


GENERATE_IMEI () {
    local seed=$(head -100 /dev/urandom | tr -dc "0123456789" | head -c10)
    local imei=$(lua /lib/blue-merle/luhn.lua $seed)
    echo -n $imei
}

SET_IMEI () {
    local imei="$1"
    local slot="$2"

    if [[ ${#imei} -eq 14 ]]; then
        GL_MODEM_AT "$slot" "AT+EGMR=1,7,\"${imei}\""
    else
        echo "IMEI is ${#imei} not 14 characters long"
    fi
}

CHECK_ABORT () {
        sim_change_switch=`cat /tmp/sim_change_switch`
        if [[ "$sim_change_switch" = "off" ]]; then
                echo '{ "msg": "SIM change      aborted." }' > /dev/ttyS0
                sleep 1
                exit 1
        fi
}
