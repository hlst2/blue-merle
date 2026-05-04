# blue-merle — Mudi 7 (GL-E5800) port

> [!IMPORTANT]
> **This branch (`mudi7-gl-e5800`) is a work-in-progress port** of blue-merle from the original GL-E750 (Mudi 4G, MIPS) hardware to the **GL.iNet Mudi 7 (GL-E5800)** 5G router.
>
> - For the stable GL-E750 release see [`main`](https://github.com/srlabs/blue-merle/tree/main) or the [v2.0 tag](https://github.com/srlabs/blue-merle/tree/v2.0).
> - There are **no prebuilt `.ipk` releases** for this branch yet. Build from source ([see below](#building)) or grab the artifact from the GitHub Actions run for this branch.
> - The IMEI write path (`AT+EGMR=1,7,"<imei>"`) has been confirmed working through the GL.iNet web UI on the Mudi 7 — full end-to-end CLI / toggle / web flows still need on-device verification. Issues and PRs welcome.

The *blue-merle* software package enhances anonymity and reduces forensic traceability of the **GL.iNet Mudi 7 (GL-E5800) 5G mobile router**. The portable device is explicitly marketed to privacy-interested retail users.

*blue-merle* addresses the traceability drawbacks of the Mudi router by adding the following features:

1. Mobile Equipment Identity (IMEI) changer (per SIM slot)
2. Media Access Control (MAC) address log wiper
3. Basic Service Set Identifier (BSSID) randomization
4. MAC Address randomization

## Compatibility

**This branch targets v3.0**, which is for the **GL.iNet Mudi 7 (GL-E5800)** only:

| Component | Specification |
| --- | --- |
| SoC      | Qualcomm quad-core 2.2 GHz (aarch64) |
| 5G modem | Qualcomm Snapdragon X72 (Dragonwing MBB Gen 3) |
| SIM      | Dual nano-SIM |
| Firmware | gl-sdk4 based (GL.iNet 4.7.x or newer) |

For the legacy GL-E750 (Mudi 4G, MIPS) refer back to the [v2.0 README](https://github.com/srlabs/blue-merle/tree/v2.0) and the v2.x release packages.

> [!NOTE]
> SRLabs cannot guarantee that the project assets within this Git repository will be compatible with future firmware updates.

## How it talks to the modem

The X72 modem is attached over MHI/PCIe rather than the legacy USB serial bus. There is **no `/dev/ttyUSB3`** — instead, blue-merle 3.x routes every modem command through GL.iNet's `gl_modem` helper that ships with gl-sdk4. This also lets us address either SIM slot independently using `gl_modem -s {1,2} AT ...`.

The IMEI write command itself remains the Quectel-style `AT+EGMR=1,7,"<imei>"`, which the Mudi 7's modem firmware accepts (verified through the GL.iNet web UI). It can be overridden via `imei_generate.py --at-write '...'` should a future firmware require a different command.

## Installation

### Build & install from this branch

There are no prebuilt v3.x packages yet. To install on a Mudi 7:

1. **Build the `.ipk`** — push to a GitHub fork of this repo and let the [CI workflow](.github/workflows/ci.yml) produce an artifact, or build locally with the OpenWrt SDK as described under [Building](#building).
2. **Copy to the device:**

   ```sh
   scp -O blue-merle_3.0.0-*_aarch64_cortex-a53.ipk root@192.168.8.1:/tmp/
   ```

3. **Install over SSH:**

   ```sh
   ssh root@192.168.8.1
   opkg update
   opkg install /tmp/blue-merle_3.0.0-*_aarch64_cortex-a53.ipk
   ```

To re-install after a rebuild:

```sh
opkg install --force-reinstall /tmp/blue-merle_3.0.0-*.ipk
```

## Usage

You may initiate an IMEI update in three different ways:

1. **CLI** — via SSH on the command line
2. **Toggle** — using the Mudi's physical toggle switch
3. **Web** — via the LuCI web interface

You can set a deterministic, randomized, or static IMEI on the command line. The web and toggle interfaces always set a randomized IMEI.

### CLI

Connect to the device via SSH, then run `blue-merle`. The command:

1. Prompts you to choose **which SIM slot** (1, 2, or current) to operate on.
2. Reads the current IMEI/IMSI for that slot.
3. Disables the modem RF, sets a random "interim" IMEI, and asks you to swap the SIM card.
4. After the swap, asks whether to set a **random (`r`)** or **deterministic (`d`)** IMEI.
5. Offers to **reset the modem** or **shut down** the device.

We advise rebooting the device after changing the IMEI.

### Toggle

This is a two-stage process operating on the **currently active SIM slot**.

Flip the Mudi's hardware switch to initiate the first stage. Follow the instructions on the MCU display, which will ask you to **replace the SIM card in the active slot**.

After replacing the SIM card, flip the switch again. The second stage **changes the IMEI** and then **powers off** the device. You should **change location** before booting again.

> [!NOTE]
> Occasionally, commands may take longer than expected to execute. If the display goes blank for a few seconds, wait for the final message before pulling the switch again.

### Web

Open LuCI from `System` > `Advanced Settings` in the Mudi web interface. Find `Blue Merle` under the `Network` tab. The web UI now displays the IMEI and IMSI for **both SIM slots** and provides a per-slot `SIM swap…` button.

**Shut down the device** once the process is complete. Then **swap your SIM card** and **change location** before booting again.

## Building

This repository contains a CI workflow (GitHub Actions) that auto-builds the package against an `aarch64_cortex-a53` OpenWrt SDK. Fork the repo or replicate the workflow locally.

You can also set up a full OpenWrt build environment:

```sh
git clone https://github.com/openwrt/openwrt
cd openwrt
git clone https://github.com/srlabs/blue-merle package/blue-merle
./scripts/feeds update -a && ./scripts/feeds install -a
make distclean && make clean
make menuconfig
    # Target System: any aarch64 target (e.g. Qualcomm Atheros 802.11ax / qualcommax)
    # Target Profile: generic
    # In Utilities, select <M> for blue-merle
    # Save new configuration
make
make package/blue-merle/compile
```

The package ships only shell scripts, Python, and static web assets — there is no native code, so any aarch64 SDK produces an `.ipk` that opkg will install on the Mudi 7.

You will find the package in `./bin/packages/aarch64_cortex-a53/base/`.

## Implementation details

### IMEI randomization

The Mudi 7's baseband is a Qualcomm Snapdragon X72 (Dragonwing MBB Gen 3). Its modem firmware accepts the Quectel-style `AT+EGMR=1,7,"<imei>"` write command, which we use to apply a new IMEI.

`imei_generate.py` implements three approaches:

- **Random** — a fresh random IMEI on each invocation.
- **Deterministic** — the RNG is seeded from the IMSI, so the same SIM always produces the same IMEI regardless of which Mudi 7 is used.
- **Static** — a user-supplied IMEI, validated against the Luhn checksum.

To prevent leakage of the old IMEI under the new IMSI (or vice-versa), the modem RF is disabled (`AT+CFUN=4`) and an interim random IMEI is written **before** the user is asked to swap the SIM card.

### Dual-SIM handling

The Mudi 7 exposes both nano-SIM slots through a single modem. We address slots via `gl_modem -s {1,2} AT ...` and use `AT+QUIMSLOT?` / `AT+QUIMSLOT=N` (with a UCI fallback) to query/switch the active slot. Each slot has its own IMSI and you can write a different IMEI per slot if your operational model calls for it.

### BSSID randomization

The Mudi router BSSID is set by hostapd via `mac80211_prepare_vif()` in `/rom/lib/netifd/wireless/mac80211.sh` and persisted in `/etc/config/wireless`.

`blue-merle`'s init script generates a valid unicast address and overrides the `macaddr` fields of `wireless.@wifi-iface[0]` (2.4 GHz) and `wireless.@wifi-iface[1]` (5 GHz) on each boot, ensuring a fresh BSSID every cold start.

### MAC address log wiping

Connecting devices' MAC addresses are stored persistently within the Mudi at `/etc/oui-tertf`. On boot, *blue-merle* deletes the client database (using `shred`), mounts a `tmpfs` at this location, and restarts the services that manage the database. The DB is retained in RAM only — UI functionality is preserved, on-disk traces are not.

### MAC address randomization

*Blue-merle* sets a randomized MAC address for the WAN interface. In repeater mode the Mudi's upstream-facing MAC will change after every boot. This may interfere with MAC filtering on the upstream AP.

## Acknowledgement: blue merle

The Mudi device shares a name with a Hungarian dog breed typically used to guard and herd flocks of livestock. Mudi dogs are agile, fast-learners and extremely friendly.

"Blue merle" is one of the five coat colours recognized for the Mudi dog breed by the Federation Cynologique Internationale and is characterized by its mottled or patched appearance. The black splashes on the blueish-gray coat of the blue merle Mudi inspired the name of this project because of its obscuring appearance and camouflaging symbolism.
