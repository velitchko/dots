#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# bt-pair.sh <MAC> — pair, trust and connect a Bluetooth device.
#
# BlueZ only completes a pairing when a pairing *agent* is registered to answer
# it. Quickshell can't register one, so pairing from the island was rejected
# (the device connected for a moment, then dropped, and stayed "not paired").
# bluetoothctl brings its own agent: we keep one session open with a
# NoInputNoOutput ("just works") agent, which is what headphones, speakers and
# mice use. Devices that need a typed PIN (some keyboards) still need
# `bluetoothctl` by hand.
#
# Prints one line: "paired", "connected" or "failed: <reason>"; exit 0 on success.
set -uo pipefail

mac=${1:-}
[[ $mac =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] || { echo "failed: usage: bt-pair.sh <MAC>"; exit 2; }
command -v bluetoothctl >/dev/null || { echo "failed: bluetoothctl missing (bluez-utils)"; exit 1; }
systemctl is-active --quiet bluetooth || { echo "failed: bluetooth service off (sudo systemctl enable --now bluetooth)"; exit 1; }

info() { timeout 3 bluetoothctl info "$mac" 2>/dev/null; }
has()  { info | grep -q "^[[:space:]]*$1: yes"; }

# One interactive bluetoothctl session holds the agent while we wait.
coproc BT { bluetoothctl 2>&1; }
send() { printf '%s\n' "$1" >&"${BT[1]}"; }
cleanup() {
    local pid=${BT_PID:-}
    send "quit" 2>/dev/null || true
    [[ -n $pid ]] || return 0
    for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$pid" 2>/dev/null || return 0; sleep 0.2; done
    kill "$pid" 2>/dev/null || true
}
trap cleanup EXIT

send "agent NoInputNoOutput"
send "default-agent"
send "scan off"                      # discovery running during pairing makes some adapters fail
if ! has Paired; then
    send "pair $mac"
    end=$((SECONDS + 30))
    while (( SECONDS < end )); do has Paired && break; sleep 0.5; done
    has Paired || { echo "failed: the device didn't accept pairing (is it in pairing mode?)"; exit 1; }
fi
send "trust $mac"
send "connect $mac"
end=$((SECONDS + 15))
while (( SECONDS < end )); do has Connected && { echo "connected"; exit 0; }; sleep 0.5; done
echo "paired"   # paired and trusted, but it didn't connect (yet)
exit 0
