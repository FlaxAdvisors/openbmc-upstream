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
│       └── 0001-tiogapass-use-64MB-flash-layout.patch
├── recipes-phosphor/
│   ├── configuration/entity-manager/             ← AMI reference configs
│   │   ├── blacklist.json                        ← device probe blacklist
│   │   └── configurations/                       ← 42 JSON configs + schemas
│   │       ├── TiogaPass.json                    ← always-on baseboard basics
│   │       ├── FBTP.json                         ← rich baseboard (FRU-probed)
│   │       ├── FBTP-Zone.json                    ← fan PID/stepwise zones
│   │       ├── *.json                            ← risers, HSBPs, NVMe, PSUs, etc.
│   │       └── schemas/                          ← validation schemas
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
| 2 | No entity-manager baseboard config | dbus-sensors skips all hwmon devices without JSON config | Installed full AMI reference entity-manager configs: baseboard (FBTP.json), fan zones (FBTP-Zone.json), plus 40+ FRU-probed accessory configs (risers, HSBPs, NVMe, PSUs, retimers) | `meta-tiogapass/recipes-phosphor/configuration/entity-manager/` |
| 3 | ADM1275/ADM1278 DTS mismatch | DTS says `compatible = "adm1275"`, hardware is ADM1278 | **Patch removed** — AMI's FBTP.json reads HSC via IpmbSensor (through ME), bypassing the kernel hwmon driver entirely. See DTS note below. | *(was `0002-...patch`, now deleted)* |

### P1 — Hardware Plumbing

| # | Issue | Root Cause | Fix | Recipe |
|---|-------|-----------|-----|--------|
| 4 | PCA9544 mux probe failure (40+ cascading errors) | Hardcoded child device nodes (INA230, TMP75, EEPROM, PCA9546) probed on empty riser slots | **Patch removed** — entity-manager FRU-probed riser configs (1Ux16, 2Ux8, A2UL16RISER, AHW1UM2RISER, etc.) handle runtime discovery; cascading I2C errors are harmless log noise | *(was `0002-...patch`, now deleted)* |
| 5 | Invalid GPIO exports (14, 33, 35, 145) | setup_gpio used legacy sysfs numbers | Rewrote to libgpiod: `gpioset gpiochip0 BMC_READY=0` | `fb-powerctrl/files/setup_gpio` |
| 6 | x86-power-control: missing ID_BUTTON, NMI_OUT | Default config expects GPIOs not in TiogaPass DTS | Custom power-config-host0.json without those entries | `meta-tiogapass/recipes-x86/chassis/x86-power-control/` |
| 7 | LED GroupManager service timeout + heartbeat error | No LED group config defined; no physical LEDs in DTS | Created led-group-config.json with empty members (no physical LEDs exist); `SERVER_POWER_LED` (GPIO AA2/210) needs `gpio-leds` DTS node for identify support | `meta-tiogapass/recipes-phosphor/leds/phosphor-led-manager/` |

### P2 — Non-Critical Warnings

| # | Issue | Status |
|---|-------|--------|
| 8 | Invalid IPMI channel: ipmi_kcs3 | Deferred (harmless) |
| 9 | NCSI bad packets on eth0/eth1 | Harmless NIC firmware quirk |
| 10 | DHCPv6 ClientIdentifier warning | Cosmetic (wrong section in .network file) |
| 11 | LDAP/nslcd connection failures | Expected when LDAP unconfigured |
| 12 | Watchdog pretimeout governor | Kernel config, harmless |
| 13 | Fan sensor PWM errors / missing match | Fixed: `"PWM"` (all caps) changed to `"Pwm"` (camelCase); `MB_FAN1` Index corrected from 1 to 2 (fan3_input = index 2); added `Connector.Name` field |
| 14 | IPMI whitelist missing | Fixed: permissive whitelist for testing |
| 15 | rsyslog working directory | Cosmetic |
| 16 | SPI1 PNOR JEDEC fail | Normal when host is off |

### Build Fixes (encountered during `bitbake`)

| Issue | Symptom | Fix |
|-------|---------|-----|
| DTS patch format | `patch fragment without header at line 17` — hand-written patch had malformed hunk headers | Regenerated patch with `git format-patch` (historical; the 0002 ADM1278/riser patch was later removed entirely in favor of entity-manager runtime discovery) |
| Dropbear PAM file clash | `check_data_file_clashes: Package dropbear wants to install file .../etc/pam.d/dropbear` | Removed `libpam_%.bbappend` that installed a dropbear PAM shim — only needed when OpenSSH replaced Dropbear; with Dropbear back, its own PAM config is shipped |

### Live Patching Notes

The fixes above were first validated on live hardware via SSH (`mount -o remount,rw /dev/root /`). Key findings from live testing:

- **ADM1278 rebind limitation:** DT-instantiated I2C devices cannot be deleted via sysfs `delete_device` — only userspace-created devices can. The `adm1275` driver unbind works, but `new_device` fails with "Device or resource busy" since the DT node still occupies the address. This is moot now — FBTP.json reads HSC via IpmbSensor, bypassing the kernel hwmon driver.
- **IPMI whitelist JSON format:** Bare array `[{...}]` causes `json.exception.type_error.305`. Must be `{"filters":[{...}]}` (top-level object with `"filters"` key).
- **Riser absence confirmed:** `i2cdetect -y 1` showed 0x71 absent — riser not installed.
- **ADM1278 identity confirmed:** `i2cget -y 7 0x45 0xd0 w` → `0x0a25` (ADM1278 device ID). PMBus registers READ_VIN, READ_IOUT, READ_TEMPERATURE all return valid data.

---

## Entity-Manager Configuration

The entity-manager recipe installs the full AMI reference configuration set
from `meta-tiogapass/reference/entity-manager/`. These are FRU-probed — configs
only activate when matching hardware is physically present.

### TiogaPass Baseboard Configs

| File | Probe | Contents |
|------|-------|----------|
| `TiogaPass.json` | `TRUE` (always match) | 3 temps, HSC, 2 fans, 8 ADCs — basic baseboard |
| `FBTP.json` | FRU `.*Tioga*` on bus 6 | Full baseboard: VRs (bus 5), XeonCPU, INA230s, IpmbSensors (HSC, PCH temp, power), riser temps (buses 16-18), chassis intrusion, SDR records |
| `FBTP-Zone.json` | FRU `.*Tioga*` on bus 6 | Fan PID zones + stepwise thermal control (inlet temp → Zone 1, mezz temp → Zone 2) |

### FRU-Probed Accessory Configs (auto-discover when plugged in)

| Category | Files | Probe Examples |
|----------|-------|----------------|
| Risers | `1Ux16 Riser`, `2Ux8 Riser`, `A2UL16RISER`, `A2UX8X4RISER`, `AHW1UM2RISER` | FRU `BOARD_PRODUCT_NAME` match on mux channels |
| HSBPs | `8X25 HSBP`, `F1U12X25`, `F1U4X25`, `F2U12X35`, `F2U8X25` | FRU `BOARD_PRODUCT_NAME` match |
| NVMe/PCIe | `NVME P4000`, `PCIE SSD Retimer`, `AXX2PRTHDHD` | FRU product name match |
| PSUs | Delta DPS-750XB, Flextronics, PSSF/SOLUM variants | FRU `PRODUCT_PRODUCT_NAME` match |
| Other | Intel Front Panel, `FCXXPDBASSMBL` PDB, `AXX1P100HSSI` NIC, chassis configs | Various FRU probes |

Non-TiogaPass baseboard configs (BNP, CYP, STP, TNP, WC, WFT, FBYV2) are
included but harmless — their FRU probes will never match on TiogaPass hardware.

### DTS Note: ADM1278 Compatible String

The upstream DTS (`aspeed-bmc-facebook-tiogapass.dts`) still has
`compatible = "adm1275"` for the HSC at i2c-7 @ 0x45, but the actual chip is
an ADM1278 (confirmed via `i2cget -y 7 0x45 0xd0 w` → `0x0a25`). The AMI
`FBTP.json` config sidesteps this by reading the HSC via `IpmbSensor` (through
the Management Engine) rather than the kernel hwmon driver, so the DTS mismatch
has no functional impact. If direct hwmon access to the ADM1278 is needed in
the future, a minimal one-line DTS patch changing `compatible = "adm1275"` to
`compatible = "adi,adm1278"` would restore kernel driver binding.

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
- [ ] No DTS errors: `dmesg | grep -i mismatch` (ADM1275/1278 mismatch expected — harmless, HSC read via IpmbSensor)
- [ ] No GPIO errors: `dmesg | grep -i "invalid GPIO"` is silent
- [ ] LED manager running: `systemctl status xyz.openbmc_project.LED.GroupManager`

### Expected remaining warnings (harmless)

- ADM1275/ADM1278 mismatch on i2c-7 @ 0x45 (HSC read via IpmbSensor, not hwmon)
- PCA9544 mux child probe errors on i2c-16..19 (riser slots empty; entity-manager handles discovery)
- NCSI bad packets on eth0 (NIC firmware quirk)
- SPI1 JEDEC fail (host is off)
- Watchdog pretimeout governor (kernel config)
- LDAP/nslcd failures (until configured)
