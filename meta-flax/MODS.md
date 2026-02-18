# OpenBMC Flax Layer Modifications

This document summarizes the `meta-flax` layer that replaces `meta-facebook`
for the TiogaPass platform, including the hardware platforming fixes applied
after first boot on real hardware.

---

## Why meta-flax?

The Facebook layer (`meta-facebook`) deliberately removes several features
that are needed for general-purpose BMC deployment:

| Feature | Facebook Status | Flax Status |
|---------|----------------|-------------|
| Network IPMI (RMCP+) | Removed | **Enabled** |
| LDAP user management | Removed | **Enabled** |
| Web UI (webui-vue) | Removed (phosphor-no-webui) | **Enabled** |
| iKVM (KVM over IP) | Removed | **Enabled** |
| Virtual Media | Not configured | **Enabled** (vm-websocket) |
| ipmitool (in-image) | Not included | **Included** |
| bmcweb basic auth | Not configured | **Enabled** |
| Serial console baud | 57600 | **115200** (OEM default) |
| Flash size | 32MB | **64MB** |
| SSH server | OpenSSH | **Dropbear** (default) |

---

## Layer Structure

```
meta-flax/                              ← shared layer (replaces meta-facebook)
├── conf/
│   ├── layer.conf
│   ├── machine/include/flax.inc        ← replaces facebook.inc chain
│   └── recipes/flax-consoles.inc
├── recipes-flax/
│   ├── packagegroups/packagegroup-flax-apps.bb
│   ├── ipmi/flax-ipmi-oem_git.bb       ← rebranded fb-ipmi-oem
│   └── obmc_functions/                  ← rebranded fb-common-functions
├── recipes-phosphor/                    ← shared bbappends
│   ├── images/obmc-phosphor-image.bbappend + flax-phosphor-image.inc
│   ├── interfaces/bmcweb_%.bbappend
│   ├── ipmi/phosphor-ipmi-config.bbappend  ← IPMI whitelist + configs
│   ├── console/ fans/ state/ watchdog/ dump/ sel-logger/
│   ├── logging/ network/ health/ settings/ host/ hostlogger/
│   └── sensors/ (shared virtual-sensor bbappend)
├── recipes-core/systemd/ busybox/
└── recipes-extended/rsyslog/ timezone/

meta-flax/meta-tiogapass/               ← machine layer
├── conf/machine/tiogapass.conf          ← 64MB flash, flax.inc
├── recipes-kernel/linux/
│   └── linux-aspeed/
│       ├── 0001-tiogapass-use-64MB-flash-layout.patch
│       └── 0002-tiogapass-fix-adm1278-and-disable-riser-mux.patch
├── recipes-phosphor/
│   ├── configuration/entity-manager/TiogaPass.json  ← baseboard sensor map
│   ├── leds/phosphor-led-manager/led-group-config.json
│   ├── sensors/ (dbus-sensors, nvme, virtual-sensor configs)
│   ├── ipmi/ flash/
│   └── images/
├── recipes-x86/chassis/
│   └── x86-power-control/power-config-host0.json    ← GPIO map
├── recipes-tiogapass/fb-powerctrl/      ← power control + GPIO setup
└── recipes-bsp/u-boot/
```

---

## Key Configuration Files

### Machine Configuration
- `meta-flax/conf/machine/include/flax.inc` — Shared machine config
  - Enables all MACHINE_FEATURES for state/fan/flash/chassis/host management
  - Uses x86-power-control for host/chassis state
  - Does NOT include phosphor-no-webui or phosphor-production
  - Does NOT remove ldap, avahi, or ikvm

### Image Configuration
- `meta-flax/recipes-phosphor/images/flax-phosphor-image.inc`
  - SSH via default Dropbear (smaller than OpenSSH)
  - Adds: ipmitool, curl, dbus-top, iproute2, jq, strace, tcpdump, tmux, usbutils, wget
  - Does NOT remove obmc-net-ipmi or obmc-user-mgmt-ldap

### bmcweb Configuration
- `meta-flax/recipes-phosphor/interfaces/bmcweb_%.bbappend`
  - Enables: vm-websocket, basic-auth, cookie-auth
  - Enables: Redfish dbus-log, dump-log, experimental subscriptions
  - Enables: insecure-redfish-expand (query parameter support)

### Console Configuration
- SSH serial console **enabled** (Facebook disables it)
- Baud rate: 115200 (was 57600)
- Host console: ttyS2, BMC console: ttyS4

### TiogaPass Machine
- `meta-flax/meta-tiogapass/conf/machine/tiogapass.conf`
  - Flash: 64MB (FLASH_SIZE=65536)
  - AST2500 SoC, aspeed-bmc-facebook-tiogapass device tree
  - Requires flax.inc (not facebook-compute-singlehost.inc)

---

## Default Credentials

- **User:** root
- **Password:** 0penBmc
- Set by `meta-phosphor/conf/distro/include/phosphor-defaults.inc`
- `allow-root-login` IMAGE_FEATURE adds root to: ipmi, web, redfish, priv-admin groups

---

## Rebranded Facebook Packages

These packages are functionally identical to the Facebook originals:

- `flax-ipmi-oem` — OEM IPMI commands (from fb-ipmi-oem upstream)
- `flax-common-functions` — GPIO/I2C shell utilities
- `packagegroup-flax-apps` — Virtual package providers
- `fb-powerctrl` — TiogaPass power control (modernized: libgpiod instead of sysfs)

---

## Hardware Platforming Fixes

After first boot on real TiogaPass hardware, boot log analysis revealed 16
issues. These were triaged into three priority tiers, validated via live
patching on the running BMC, and then baked into meta-flax recipes.

### P0 — System Stability

| # | Issue | Root Cause | Fix | Recipe |
|---|-------|-----------|-----|--------|
| 1 | Virtual_Inlet_Temp false overtemp shutdown | Formula references non-existent D-Bus sensors; evaluates to NaN → CriticalLow trip | Simplified formula to passthrough MB_INLET_TEMP; CriticalLow=0 | `meta-tiogapass/recipes-phosphor/sensors/phosphor-virtual-sensor/virtual_sensor_config.json` |
| 2 | No entity-manager baseboard config | dbus-sensors skips all hwmon devices without JSON config | Created TiogaPass.json: 3 temps, HSC, 2 fans, 8 ADCs | `meta-tiogapass/recipes-phosphor/configuration/entity-manager/TiogaPass.json` |
| 3 | ADM1275/ADM1278 DTS mismatch | DTS says `compatible = "adm1275"`, hardware is ADM1278 | DTS patch: `"adi,adm1278"` | `0002-tiogapass-fix-adm1278-and-disable-riser-mux.patch` |

### P1 — Hardware Plumbing

| # | Issue | Root Cause | Fix | Recipe |
|---|-------|-----------|-----|--------|
| 4 | PCA9544 mux probe failure (40+ cascading errors) | X24 riser card not installed; mux at i2c-1 @ 0x71 absent | DTS patch: `status = "disabled"` on mux subtree | Same 0002 patch as issue 3 |
| 5 | Invalid GPIO exports (14, 33, 35, 145) | setup_gpio used legacy sysfs numbers | Rewrote to libgpiod: `gpioset gpiochip0 BMC_READY=0` | `fb-powerctrl/files/setup_gpio` |
| 6 | x86-power-control: missing ID_BUTTON, NMI_OUT | Default config expects GPIOs not in TiogaPass DTS | Custom power-config-host0.json without those entries | `meta-tiogapass/recipes-x86/chassis/x86-power-control/` |
| 7 | LED GroupManager service timeout | No LED group config defined | Created led-group-config.json (bmc_booted + enclosure_identify) | `meta-tiogapass/recipes-phosphor/leds/phosphor-led-manager/` |

### P2 — Non-Critical Warnings

| # | Issue | Status |
|---|-------|--------|
| 8 | Invalid IPMI channel: ipmi_kcs3 | Deferred (harmless) |
| 9 | NCSI bad packets on eth0/eth1 | Harmless NIC firmware quirk |
| 10 | DHCPv6 ClientIdentifier warning | Cosmetic (wrong section in .network file) |
| 11 | LDAP/nslcd connection failures | Expected when LDAP unconfigured |
| 12 | Watchdog pretimeout governor | Kernel config, harmless |
| 13 | PWM enable errors | May resolve with entity-manager config |
| 14 | IPMI whitelist missing | Fixed: permissive whitelist for testing |
| 15 | rsyslog working directory | Cosmetic |
| 16 | SPI1 PNOR JEDEC fail | Normal when host is off |

### Build Fixes (encountered during `bitbake`)

| Issue | Symptom | Fix |
|-------|---------|-----|
| DTS patch format | `patch fragment without header at line 17` — hand-written patch had malformed hunk headers | Regenerated patch with `git format-patch` from actual kernel source tree (proper index line, `@@ ... @@ context` headers, git version trailer) |
| Dropbear PAM file clash | `check_data_file_clashes: Package dropbear wants to install file .../etc/pam.d/dropbear` | Removed `libpam_%.bbappend` that installed a dropbear PAM shim — only needed when OpenSSH replaced Dropbear; with Dropbear back, its own PAM config is shipped |

### Live Patching Notes

The fixes above were first validated on live hardware via SSH (`mount -o remount,rw /dev/root /`). Key findings from live testing:

- **ADM1278 rebind limitation:** DT-instantiated I2C devices cannot be deleted via sysfs `delete_device` — only userspace-created devices can. The `adm1275` driver unbind works, but `new_device` fails with "Device or resource busy" since the DT node still occupies the address. **Confirmed build-time DTS patch is the only fix.**
- **IPMI whitelist JSON format:** Bare array `[{...}]` causes `json.exception.type_error.305`. Must be `{"filters":[{...}]}` (top-level object with `"filters"` key).
- **Riser absence confirmed:** `i2cdetect -y 1` showed 0x71 absent — riser not installed.
- **ADM1278 identity confirmed:** `i2cget -y 7 0x45 0xd0 w` → `0x0a25` (ADM1278 device ID). PMBus registers READ_VIN, READ_IOUT, READ_TEMPERATURE all return valid data.

---

## Entity-Manager Sensor Map

The `TiogaPass.json` baseboard configuration exposes:

| Sensor | Type | Bus/Address | Thresholds |
|--------|------|-------------|------------|
| MB_INLET_TEMP | TMP421 | i2c-6 @ 0x4e | CritHigh=90, WarnHigh=70 |
| MB_OUTLET_TEMP | TMP421 | i2c-6 @ 0x4f | CritHigh=90, WarnHigh=70 |
| MB_MEZZ_TEMP | TMP421 | i2c-8 @ 0x1f | CritHigh=90 |
| MB_HSC | ADM1278 | i2c-7 @ 0x45 | CritHigh=300W, PowerState=On |
| MB_FAN0 | AspeedFan | PWM0/Tach0 | CritLow=500 RPM |
| MB_FAN1 | AspeedFan | PWM1/Tach2 | CritLow=500 RPM |
| MB_ADC_P12V..P3V3 | ADC | ch0–ch7 | (none) |

Uses `"Probe": "TRUE"` (always match) for initial testing. For production,
replace with a probe expression that detects TiogaPass hardware via board
EEPROM FRU data.

---

## x86-power-control GPIO Map

| Config Name | DTS Line Name | GPIO | Polarity |
|-------------|--------------|------|----------|
| NMIButton | NMI_BUTTON | E4 | ActiveLow |
| PostComplete | POST_COMPLETE | AA7 | ActiveLow |
| PowerButton | POWER_BUTTON | E2 | ActiveLow |
| PowerOk | PS_PWROK | B6 | ActiveHigh |
| PowerOut | POWER_OUT | E3 | ActiveLow |
| ResetButton | RESET_BUTTON | E0 | ActiveLow |
| ResetOut | RESET_OUT | E1 | ActiveLow |
| SioOnControl | SIO_ONCONTROL | Y3 | ActiveLow |
| SioPowerGood | SIO_POWER_GOOD | Z1 | ActiveHigh |
| SIOS5 | SIO_S5 | Y1 | ActiveLow |

Removed from upstream default: `IdButton` (ID_BUTTON) and `NMIOut` (NMI_OUT) —
no such pins on TiogaPass.

---

## Build Instructions

```bash
# Clean previous build artifacts
rm -rf build/tiogapass/tmp build/tiogapass/conf

# Initialize build environment (picks up meta-flax templates)
source setup tiogapass

# Verify bblayers.conf references meta-flax (not meta-facebook)
grep meta-flax build/tiogapass/conf/bblayers.conf

# Build
bitbake obmc-phosphor-image
```

If rebuilding after recipe changes without a full clean:
```bash
# After DTS patch changes — must cleansstate the kernel
bitbake linux-aspeed -c cleansstate && bitbake obmc-phosphor-image

# After image feature changes (e.g., SSH server swap)
bitbake obmc-phosphor-image -c cleanall && bitbake obmc-phosphor-image
```

---

## Verification Checklist

After flashing the image:

- [ ] SSH: `ssh root@<bmc-ip>` with password `0penBmc` (Dropbear)
- [ ] `ipmitool -C 17 -I lanplus -U root -P 0penBmc -H <bmc-ip> lan print 1`
- [ ] Web UI: `https://<bmc-ip>/` shows login page
- [ ] Redfish: `curl -k https://<bmc-ip>/redfish/v1/` returns ServiceRoot
- [ ] Virtual Media: `/redfish/v1/Managers/bmc/VirtualMedia`
- [ ] Serial Console: `ssh -p 2200 <bmc-ip>` for host serial
- [ ] Sensors: `busctl tree xyz.openbmc_project.HwmonTempSensor` shows MB_INLET_TEMP
- [ ] Entity-manager: `busctl tree xyz.openbmc_project.EntityManager` shows TiogaPass Baseboard
- [ ] Fans: `busctl tree xyz.openbmc_project.FanSensor` shows MB_FAN0, MB_FAN1
- [ ] ADC: `busctl tree xyz.openbmc_project.ADCSensor` shows voltage rails
- [ ] IPMI SDR: `ipmitool sdr list` shows sensor readings
- [ ] No false overtemp: `journalctl -p 0..4 | grep -i virtual` is silent
- [ ] No DTS errors: `dmesg | grep -i mismatch` is silent
- [ ] No GPIO errors: `dmesg | grep -i "invalid GPIO"` is silent
- [ ] LED manager running: `systemctl status xyz.openbmc_project.LED.GroupManager`

### Expected remaining warnings (harmless)

- NCSI bad packets on eth0 (NIC firmware quirk)
- SPI1 JEDEC fail (host is off)
- Watchdog pretimeout governor (kernel config)
- LDAP/nslcd failures (until configured)
