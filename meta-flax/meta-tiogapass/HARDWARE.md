# TiogaPass Hardware Reference

Captured from live TiogaPass hardware running AMI BMC firmware (kernel
5.4.53, built 2026-01-20).  Reference files live in `reference/`.

This document compares three DTS/config sources:

| Source | Description |
|--------|-------------|
| **AMI** | Decompiled from running firmware (`reference/ami-decompiled.dts`) |
| **Upstream** | `meta-facebook/meta-tiogapass` + kernel `aspeed-bmc-facebook-tiogapass.dts` |
| **Flax** | `meta-flax/meta-tiogapass` (our working build) |

---

## Board Identity

| Field | Value |
|-------|-------|
| Board Manufacturer | Wistron |
| Product Manufacturer | Wiwynn |
| Product Name | Type6 Tioga Pass Single Side |
| Part Number | WTH18040C5ZA1 (board), B91.00X01.0001 (product) |
| Serial Number | WTF18110271MA1 |
| Build Date | 2018-04-04 |
| SoC | AST2500 (ARM1176JZF-S, aspeed-g5) |
| Memory | 504 MB (AMI DTS: `0x1f800000`), 512 MB (upstream DTS: `0x20000000`) |

Source: `reference/fru-eeprom.txt` (i2c bus 6, address 0x54, AT24C64).

---

## Flash Layout

| Partition | Offset | Size | Label |
|-----------|--------|------|-------|
| u-boot | 0x000000 | 512 KB | u-boot |
| u-boot-env | 0x080000 | 128 KB | u-boot-env |
| kernel | 0x0A0000 | 5.3 MB | kernel |
| rofs | 0x5F0000 | 24.25 MB | rofs (SquashFS, read-only) |
| rwfs | 0x1E30000 | 1.875 MB | rwfs (JFFS2, read-write overlay) |

AMI uses OverlayFS: SquashFS `mtdblock4` (ro) + JFFS2 `mtdblock5` (rw).
Only 496 KB free on rwfs at time of capture.

| Config | Upstream | AMI | Flax |
|--------|----------|-----|------|
| Flash size | 32 MB | 32 MB partitions in 64 MB chip | **64 MB** |
| Layout include | `openbmc-flash-layout.dtsi` | (inline, matches 32 MB) | `openbmc-flash-layout-64.dtsi` |

Flax patch `0001-tiogapass-use-64MB-flash-layout.patch` switches the include.

---

## I2C Bus Topology

### Comparison: what each source defines in DTS

| Bus | Purpose | AMI DTS | Upstream DTS | Flax DTS | Notes |
|-----|---------|---------|-------------|----------|-------|
| 0 | Airmax Conn B / CPU PIROM | Enabled, empty | Enabled, empty | Enabled, empty | IPMB @ 0x1010 found on live scan |
| 1 | X24 Riser | PCA9544 + **full child nodes** | PCA9544 + **full child nodes** | PCA9544 + **empty channels** | See riser section below |
| 2 | Mezz Mgmt SMBus | Enabled, empty | Enabled, empty | Enabled, empty | 3 devices found on live scan |
| 3 | Board ID / Misc | Enabled, empty | Enabled, empty | Enabled, empty | 5 devices found on live scan |
| 4 | BMC Debug Header | Enabled, empty | **ipmb@10 node** | Enabled, empty | Upstream has IPMB; AMI/Flax do not |
| 5 | CPU Voltage Regulators | 9x pxe1610 | 9x pxe1610 | 9x pxe1610 | All three match |
| 6 | Baseboard Sensors | TPM + 2x TMP421 + EEPROM | TPM + 2x TMP421 + EEPROM | TPM + 2x TMP421 + EEPROM | All three match |
| 7 | HSC / AirMax Conn A | **Empty** | adm1278 (`adm1275`) | adm1278 (`adi,adm1278`) | AMI discovers at runtime; upstream has wrong compatible; Flax fixes it |
| 8 | Mezz Sensor SMBus | TMP421 @ 0x1f | TMP421 @ 0x1f | TMP421 @ 0x1f | All three match |
| 9 | USB Debug Connector | Enabled, empty | **ipmb@10 node** | Enabled, empty | Upstream has IPMB; AMI/Flax do not |
| 10 | (unused) | **Disabled** | Enabled, empty | Enabled, empty | AMI disables; upstream/Flax leave enabled |
| 11 | (unused) | **Disabled** | Enabled, empty | Enabled, empty | Same |
| 12 | (unused) | **Disabled** | Enabled, empty | Enabled, empty | Same |
| 13 | (unused) | **Disabled** | Enabled, empty | Enabled, empty | Same |

### Riser mux topology (bus 1)

The PCA9544 at bus 1 address 0x71 creates buses i2c-16 through i2c-19.
Each riser slot has a PCA9546 sub-mux at 0x73 creating i2c-20 through i2c-31.

| Approach | Child device nodes | Sub-mux PCA9546 nodes | Result when no riser |
|----------|--------------------|----------------------|---------------------|
| **AMI** | Full (ina230, tmp75, tmp421, eeprom) | Full (4 channels each) | Works (devices silently fail to probe) |
| **Upstream** | Full | Full | **~40 cascading I2C errors** |
| **Flax** | **Stripped** | **Stripped** | Clean boot, runtime discovery via entity-manager |

Flax patch `0002-tiogapass-fix-adm1278-and-disable-riser-mux.patch` removes
the hardcoded child nodes but keeps the four empty channel buses.  The AMI DTS
shows that having the full child nodes is safe on working firmware (the AMI
kernel 5.4.53 suppresses probe errors), but the OpenBMC 5.15 kernel reports
them loudly.

Per-slot riser devices (from AMI DTS and reference FBTP.json):

| Bus | Devices | Entity-Manager Sensors |
|-----|---------|----------------------|
| i2c-16 (slot 0) | ina230@0x45, tmp75@0x48, tmp421@0x49, eeprom@0x50, pca9546@0x73 | MB_C2_P12V_INA230, MB_C2_AVA_RTEMP, MB_C2_AVA_FTEMP |
| i2c-17 (slot 1) | ina230@0x45, tmp421@0x48, tmp421@0x49, eeprom@0x50, pca9546@0x73 | MB_C3_P12V_INA230, MB_C3_AVA_RTEMP, MB_C3_AVA_FTEMP |
| i2c-18 (slot 2) | ina230@0x45, tmp421@0x48, tmp421@0x49, eeprom@0x50, pca9546@0x73 | MB_C4_P12V_INA230, MB_C4_AVA_RTEMP, MB_C4_AVA_FTEMP |
| i2c-19 (slot 3) | ina230@0x40, ina230@0x41, ina230@0x45 | MB_CONN_P12V_INA230 |

NVMe drives behind sub-muxes: drives 0,1 on i2c-20,21 and drives 4-7 on
i2c-24..27 (see upstream `nvme_config.json`).

### Live I2C device inventory

Devices found via `i2cdetect` on the running AMI system.

#### Bus 0 -- Airmax Conn B, CPU PIROM
| Address | Device | In DTS | Notes |
|---------|--------|--------|-------|
| 0x1010 | IPMB | No (all three) | Upstream has IPMB on bus 4 and 9, not bus 0 |

#### Bus 1 -- X24 Riser
| Address | Device | In DTS | Notes |
|---------|--------|--------|-------|
| 0x71 | PCA9544 4-ch mux | Yes | No riser installed at capture time |

#### Bus 2 -- Mezz Management SMBus
| Address | Device | Identification | In DTS | Notes |
|---------|--------|---------------|--------|-------|
| 0x10 | Unknown | Returns 0x21 for all bytes | No | Possibly NIC MCTP endpoint or CPLD |
| 0x16 | Unknown | Returns 0xFF (unresponsive) | No | May be absent/unpopulated |
| 0x70 | I2C mux | Returns XX (write-only mux behavior) | No | PCA9548 or PCA9546 |

#### Bus 3 -- Board ID / Misc SMBus
| Address | Device | Identification | In DTS | Notes |
|---------|--------|---------------|--------|-------|
| 0x08 | Unknown | No response to byte reads (XX) | No | Possibly SMBus Alert Response or clock gen |
| 0x44 | Unknown | Reg 0x0f = 0x26 | No | Not a standard TMP75 (ID mismatch) |
| 0x51 | EEPROM | All 0xFF | No | Blank/unprogrammed |
| 0x68 | RTC | Returns time-like data (0x09 in seconds reg) | No | DS1307 or PCF8563; AMI kernel has `CONFIG_RTC_DRV_DS1307=y` |
| 0x6c | Intel ME SMBus | Characteristic `c7 ff 0f` pattern | No | ME firmware revision data |

#### Bus 4 -- BMC Debug Header
| Address | Device | In DTS | Notes |
|---------|--------|--------|-------|
| 0x1010 | IPMB | Upstream only | AMI has `/dev/ipmb-4` (remote addr 0x2C) |

#### Bus 5 -- CPU Voltage Regulators
| Address | Driver | VR Assignment (from FBTP.json) | In DTS |
|---------|--------|-------------------------------|--------|
| 0x48 | pxe1610 | MB_VR_CPU0_VCCIN + MB_VR_CPU0_VSA | Yes |
| 0x4a | pxe1610 | MB_VR_CPU0_VCCIO | Yes |
| 0x50 | pxe1610 | MB_VR_CPU1_VDDQ_GRPC | Yes |
| 0x52 | pxe1610 | MB_VR_CPU1_VDDQ_GRPD | Yes |
| 0x58 | pxe1610 | MB_VR_CPU1_VCCIN + MB_VR_CPU1_VSA | Yes |
| 0x5a | pxe1610 | MB_VR_CPU1_VCCIO | Yes |
| 0x68 | pxe1610 | MB_VR_PCH_PVNN + MB_VR_PCH_P1V05 | Yes |
| 0x70 | pxe1610 | MB_VR_CPU0_VDDQ_GRPA | Yes |
| 0x72 | pxe1610 | MB_VR_CPU0_VDDQ_GRPB | Yes |

Each PXE1610 exposes: 6x current, 6x voltage, 6x power, 3x temperature via
hwmon (hwmon4-12).  VR sensors are **not yet in Flax entity-manager config**
but are fully defined in `reference/entity-manager/configurations/FBTP.json`.

#### Bus 6 -- Baseboard Sensors
| Address | Driver | Device | In DTS | Notes |
|---------|--------|--------|--------|-------|
| 0x20 | slb9645tt | Infineon TPM 1.2 | Yes | |
| 0x4e | tmp421 | MB_INLET_TEMP | Yes | hwmon1 |
| 0x4f | tmp421 | MB_OUTLET_TEMP | Yes | hwmon2 |
| 0x54 | 24c64 | FRU EEPROM | Yes | Contains board identity (Wistron/Wiwynn) |

#### Bus 7 -- HSC, AirMax Conn A
| Address | Driver | Device | In DTS | Notes |
|---------|--------|--------|--------|-------|
| 0x45 | adm1278 | Hot-swap controller | Yes (Flax only) | AMI discovers at runtime (no DTS node) |

#### Bus 8 -- Mezz Sensor SMBus
| Address | Driver | Device | In DTS | Notes |
|---------|--------|--------|--------|-------|
| 0x1f | tmp421 | MB_MEZZ_TEMP | Yes | hwmon3 |

#### Bus 9 -- USB Debug Connector
| Address | Device | Identification | In DTS | Notes |
|---------|--------|---------------|--------|-------|
| 0x27 | PCF8574 GPIO expander | Reads `0x92` (8-bit port) | No | Controls unknown board-level functions |

---

## ADM1278 HSC (bus 7, 0x45) -- DTS Comparison

| Property | AMI | Upstream | Flax |
|----------|-----|---------|------|
| DTS node | **None** (runtime discovery) | `compatible = "adm1275"` | `compatible = "adi,adm1278"` |
| Shunt resistor | (entity-manager: 250 uOhm) | `shunt-resistor-micro-ohms = <250>` | `shunt-resistor-micro-ohms = <250>` |
| Binding | entity-manager + FruDevice | DTS (wrong compatible, won't bind) | DTS (correct compatible, binds) |

The upstream `adm1275` compatible causes the pmbus driver to detect a device
ID mismatch and refuse to bind.  Confirmed via `i2cget -y 7 0x45 0xd0 w` =
`0x0a25` (ADM1278 device ID).

---

## IPMB / ME Bridge

AMI firmware creates three IPMB devices: `/dev/ipmb-0`, `/dev/ipmb-4`, `/dev/ipmb-6`.

| Source | IPMB nodes | Configuration |
|--------|-----------|---------------|
| AMI | No DTS nodes; devices created by userspace | `/dev/ipmb-0`, `-4`, `-6` |
| Upstream | `ipmb@10` on **bus 4** and **bus 9** | `phosphor-ipmi-ipmb`: bus 4 (remote 0x2C), bus 9 (remote 0x60) |
| Flax | None | Not yet configured |

ME bridge status at capture: `ipmitool -b 0 -t 0x2c -m 0x20 sdr list` failed
(ME not responding or host powered off).  BMC reports IPMI 2.0 with Manufacturer
ID 0 and Product ID 0 (unconfigured).

IPMI channels:
- Channel 0: IPMB (I2C), session-less
- Channel 1: 802.3 LAN (MAC1), multi-session
- Channel 2: 802.3 LAN (MAC2), multi-session

---

## PECI

| Property | AMI DTS | Upstream DTS | Flax |
|----------|---------|-------------|------|
| Node | `bus@1e78b000/peci-bus@0` + `astpeci@0x1e78b000` | `bus@1e78b000/peci-bus@0` | Same as upstream |
| Compatible | `aspeed,ast2500-peci` (both nodes) | `aspeed,ast2500-peci` | Same |
| Clock | 24 MHz (`0x16e3600`) | 24 MHz | Same |
| cmd-timeout | 1000 ms | 1000 ms | Same |
| CPU clients | None enumerated (host off) | None in DTS (runtime via PECI scan) | Same |

AMI has a **second PECI node** (`astpeci@0x1e78b000`) with AMI's own compatible
alongside the standard `peci-bus`.  OpenBMC uses only the standard node.

CPU addresses when host is powered: 0x30 (CPU 1) and 0x31 (CPU 2) per FBTP.json.
PECI exposes CPU core temps and DIMM temps via `cputemp` and `dimmtemp` hwmon drivers.

---

## Networking

| Property | AMI DTS | Upstream DTS | Flax |
|----------|---------|-------------|------|
| MAC1 (eth1, 1e680000) | RMII2, NCSI | RMII2, NCSI | Same |
| MAC2 (eth0, 1e660000) | RMII1, NCSI | RMII1, NCSI | Same |

Both MACs use NCSI (shared NIC).  The NCSI netlink registration failure seen
on AMI (`ftgmac100: ncsi: failed to register netlink family`) is a kernel bug,
not a configuration issue -- networking functions normally despite the error.

---

## Power Control

### AMI approach
AMI uses `x86-power-control` (`Intel Power Control` service) with a simple
JSON config at `/usr/share/x86-power-control/power-config-host0.json`:

```json
{
    "PostComplete": "POST_COMPLETE",
    "PwrButton": "POWER_BUTTON",
    "PwrOK": "PS_PWROK",
    "PwrOut": "POWER_OUT",
    "RstButton": "RESET_BUTTON",
    "RstOut": "RESET_OUT"
}
```

### Upstream (meta-facebook) approach
Uses custom `fb-powerctrl` scripts:
- `setup_gpio`: Sets BMC_READY (GPIO S1/145) low, PECI_MUX_SELECT (GPIO AA4/212) high
- `power-util`: Shell script calling `busctl` for state transitions, `i2cset` for sled-cycle (ADM1278 reset via i2c7 0x45 0xd9)
- No `x86-power-control` -- uses separate `host-poweron.service` / `host-poweroff.service`

### Flax approach
Uses `x86-power-control` (same as AMI) with expanded `power-config-host0.json`:

| Config Name | GPIO Line Name | GPIO Number | Pin | Polarity |
|-------------|---------------|-------------|-----|----------|
| PowerButton | POWER_BUTTON | E2 (34) | F18 | ActiveLow |
| PowerOut | POWER_OUT | E3 (35) | F17 | ActiveLow |
| PowerOk | PS_PWROK | B6 (14) | H22 | ActiveHigh |
| ResetButton | RESET_BUTTON | E0 (32) | B20 | ActiveLow |
| ResetOut | RESET_OUT | E1 (33) | C20 | ActiveLow |
| PostComplete | POST_COMPLETE | AA7 (215) | P19 | ActiveLow |
| NMIButton | NMI_BUTTON | E4 (36) | E18 | ActiveLow |
| SioOnControl | SIO_ONCONTROL | Y3 (195) | P21 | ActiveLow |
| SioPowerGood | SIO_POWER_GOOD | Z1 (201) | AB20 | ActiveHigh |
| SIOS5 | SIO_S5 | Y1 (193) | R21 | ActiveLow |

Removed from defaults: `IdButton` (ID_BUTTON) and `NMIOut` (NMI_OUT) -- not
present on TiogaPass.

### GPIO ownership from live capture
The `power-control` daemon claims these GPIOs (from `reference/gpio/debug.txt`):
- gpio-14 (H22): input, low -- **PS_PWROK** (system power not good at capture time)
- gpio-32 (B20): input, high, IRQ -- **RESET_BUTTON** (not pressed)
- gpio-34 (F18): input, high, IRQ -- **POWER_BUTTON** (not pressed)
- gpio-215 (P19): input, high, IRQ -- **POST_COMPLETE** (not asserted)

---

## GPIO Signal Map

Full GPIO names from DTS `gpio-line-names` (all three sources agree on naming).

### Power and Reset Signals
| GPIO | Name | Dir | Default | Function |
|------|------|-----|---------|----------|
| E0 (32) | RESET_BUTTON | in | high | Front panel reset button input |
| E1 (33) | RESET_OUT | out | - | BMC reset pulse to host |
| E2 (34) | POWER_BUTTON | in | high | Front panel power button input |
| E3 (35) | POWER_OUT | out | - | BMC power pulse to host |
| E4 (36) | NMI_BUTTON | in | - | NMI button input |
| B6 (14) | (unnamed/PS_PWROK) | in | low | Platform power good status |
| AA7 (215) | (unnamed/POST_COMPLETE) | in | high | Host POST complete status |

Note: PS_PWROK and POST_COMPLETE are **unnamed in the DTS** `gpio-line-names`
array.  They appear as empty strings.  The `x86-power-control` config maps them
by name from a separate JSON config, but the upstream DTS names them in the
gpio-line-names (gpio B6 = `PS_PWROK`, gpio AA7 = `POST_COMPLETE`).

### Platform State Signals
| GPIO | Name | Dir | Function |
|------|------|-----|----------|
| S1 (145) | BMC_READY | out | BMC ready indication to host |
| Y0 (192) | SIO_S3 | in | ACPI S3 sleep state |
| Y1 (193) | SIO_S5 | in | ACPI S5 soft-off state |
| Y3 (195) | SIO_ONCONTROL | in | SIO power on control |
| Z1 (201) | SIO_POWER_GOOD | in | SIO power good |
| P7 (127) | RST_RSMRST | in | Resume reset |
| R5 (141) | RST_BMC_PLTRST_BUF | in | Platform reset (active low) |

### LED Signals
| GPIO | Name | Dir | Function |
|------|------|-----|----------|
| H0-H7 (56-63) | LED_POST_CODE_0..7 | out | 8-bit POST code display |
| U5 (165) | BMC_FAULT | out | BMC fault indicator |
| AA2 (210) | SERVER_POWER_LED | out | Power/identify LED |

`SERVER_POWER_LED` needs a `gpio-leds` DTS node to expose via
`/sys/class/leds/` for phosphor-led-manager identify support.  Currently
controllable only via `gpioset gpiochip0 210=0/1`.

### CPU Error and Thermal Signals
| GPIO | Name | Dir | Function |
|------|------|-----|----------|
| D6 (30) | CPU_ERR0_LVT3_BMC | in | CPU error 0 |
| D7 (31) | CPU_ERR1_LVT3_BMC | in | CPU error 1 |
| G0 (48) | CPU_ERR2_LVT3 | in | CPU error 2 |
| G1 (49) | CPU_CATERR_LVT3 | in | Catastrophic error |
| N3 (107) | CPU_MSMI_LVT3 | in | Machine check SMI |
| G2 (50) | PCH_BMC_THERMTRIP | in | PCH thermal trip |
| M4 (100) | CPU0_THERMTRIP_LATCH_LVT3 | in | CPU0 thermal trip latch |
| M5 (101) | CPU1_THERMTRIP_LATCH_LVT3 | in | CPU1 thermal trip latch |
| E6 (38) | CPU0_PROCHOT_LVT3_BMC | in | CPU0 PROCHOT (thermal throttle) |
| E7 (39) | CPU1_PROCHOT_LVT3_BMC | in | CPU1 PROCHOT |

### VR Hot and Fault Signals
| GPIO | Name | Dir | Function |
|------|------|-----|----------|
| B7 (15) | IRQ_PVDDQ_GHJ_VRHOT_LVT3 | in | VR hot: VDDQ GHJ |
| F0 (40) | IRQ_PVDDQ_ABC_VRHOT_LVT3 | in | VR hot: VDDQ ABC |
| F2 (42) | IRQ_PVCCIN_CPU0_VRHOT_LVC3 | in | VR hot: CPU0 VCCIN |
| F3 (43) | IRQ_PVCCIN_CPU1_VRHOT_LVC3 | in | VR hot: CPU1 VCCIN |
| F4 (44) | IRQ_PVDDQ_KLM_VRHOT_LVT3 | in | VR hot: VDDQ KLM |
| Z2 (202) | IRQ_PVDDQ_DEF_VRHOT_LVT3 | in | VR hot: VDDQ DEF |
| AA1 (209) | IRQ_SML1_PMBUS_ALERT | in | PMBus alert |
| I0 (64) | CPU0_FIVR_FAULT_LVT3 | in | CPU0 FIVR fault |
| I1 (65) | CPU1_FIVR_FAULT_LVT3 | in | CPU1 FIVR fault |

### Board ID and SKU
| GPIO | Name | Dir | Function |
|------|------|-----|----------|
| D1 (25) | BOARD_REV_ID0 | in | Board revision bit 0 |
| D3 (27) | BOARD_REV_ID1 | in | Board revision bit 1 |
| D5 (29) | BOARD_REV_ID2 | in | Board revision bit 2 |
| P0-P4 (120-124) | BOARD_SKU_ID0..4 | in | Board SKU (5 bits) |

### Miscellaneous
| GPIO | Name | Dir | Function |
|------|------|-----|----------|
| F6 (46) | P3VBAT_BRIDGE_EN | out | Battery voltage measurement bridge enable |
| L5 (93) | PMBUS_ALERT_BUF_EN | out | PMBus alert buffer enable |
| M3 (99) | OC_DETECT_EN | out | Overcurrent detection enable |
| S3 (147) | HSC_SMBUS_SWITCH_EN | in | HSC SMBus switch enable |
| V3 (171) | FAST_PROCHOT_EN | out | Fast PROCHOT enable |
| N5 (109) | BIOS_SPI_BMC_CTRL | in | SPI flash mux (BMC vs PCH) |
| AA4 (212) | PECI_MUX_SELECT | out | PECI mux select |
| AB1 (217) | OCP_MEZZA_PRES | in | OCP mezz card presence |
| G3 (51) | CPU0_SKTOCC_LVT3 | in | CPU0 socket occupied |
| AA0 (208) | CPU1_SKTOCC_LVT3 | in | CPU1 socket occupied |

---

## Pinmux State

From `reference/pinctrl-aspeed-g5-pinctrl.txt` (live AMI capture).

Only these pin groups are actively muxed (all others are GPIO or unclaimed):

| Pin Group | Function | Device | Pins |
|-----------|----------|--------|------|
| I2C3 | I2C bus 3 | 1e78a0c0.i2c-bus | 128 (A11), 129 (A10) |
| I2C4 | I2C bus 4 | 1e78a100.i2c-bus | 130 (A9), 131 (B9) |
| I2C5 | I2C bus 5 | 1e78a140.i2c-bus | 80 (L3), 81 (L4) |
| I2C6 | I2C bus 6 | 1e78a180.i2c-bus | 82 (L1), 83 (N2) |
| I2C7 | I2C bus 7 | 1e78a1c0.i2c-bus | 84 (N1), 85 (P1) |
| I2C8 | I2C bus 8 | 1e78a300.i2c-bus | 86 (P2), 87 (R1) |
| I2C9 | I2C bus 9 | 1e78a340.i2c-bus | 4 (C14), 5 (A13) |
| I2C10 | I2C bus 10 | 1e78a380.i2c-bus | 16 (C12), 17 (A12) |
| TXD1/RXD1 | UART1 (host console) | 1e783000.serial | 94 (V1), 95 (W1) |
| PWM0 | Fan 0 | 1e786000.pwm-tacho | 104 (V2) |
| PWM1 | Fan 1 | 1e786000.pwm-tacho | 105 (W2) |
| RMII1 | Ethernet MAC2 (eth0) | 1e660000.ethernet | 9 pins |
| RMII2 | Ethernet MAC1 (eth1) | 1e680000.ethernet | 9 pins |
| USB2AD | USB vHub | 1e6a0000.usb-vhub | 232 (A7), 233 (A8) |

I2C buses 0-2 use hardware-default pins (no explicit pinctrl claim needed).
I2C buses 11-13 are disabled in AMI DTS.  **No pin conflicts detected.**

---

## Fan / PWM

### DTS Configuration (all three sources agree)

| DTS Node | PWM Channel | Tach Channel | sysfs PWM | sysfs Tach |
|----------|------------|-------------|-----------|------------|
| fan@0 | 0 (reg) | 0 (tach-ch) | pwm1 | fan1_input |
| fan@1 | 1 (reg) | 2 (tach-ch) | pwm2 | fan3_input |

Mapping: `pwm{reg+1}`, `fan{tach_ch+1}_input`.  Tach channel 1 is unused.

### Live readings (from `reference/pwm-tacho.txt`)

| Fan | RPM | PWM Value | Duty % |
|-----|-----|-----------|--------|
| MB_FAN0 (fan1_input) | 3013 | 66/255 | 26% |
| MB_FAN1 (fan3_input) | 1627 | 25/255 | 10% |

### Entity-Manager AspeedFan Config

`fansensor` matches `"Index"` to sysfs `fan{Index+1}_input`.

| JSON Field | Type | Maps to |
|-----------|------|---------|
| `"Index"` | 0-based int | `fan{N+1}_input` |
| `"Connector"."Pwm"` | 0-based int | `pwm{N+1}` |
| `"Connector"."Name"` | string | Required by schema |
| `"Connector"."Tachs"` | array | Informational only |

**Important:** The key is `"Pwm"` (camelCase), NOT `"PWM"` (all caps).

### Fan PID / Thermal Zones

AMI reference config (`reference/entity-manager/configurations/FBTP-Zone.json`):

| Zone | Fan | Input Sensor | Type | Temp Range | Duty Range |
|------|-----|-------------|------|-----------|------------|
| 1 | MB_FAN0 | MB_INLET_TEMP | Stepwise | 20-40 C | 13-70% |
| 2 | MB_FAN1 | MEZZ_SENSOR_TEMP | Stepwise | 84-95 C | 10-70% |

Both zones: FailSafePercent=100, MinThermalOutput=10.
**Not yet deployed in Flax** -- fans currently run uncontrolled.

---

## ADC Channels

8 channels via AST2500 ADC, exposed as `iio-hwmon` (hwmon13).

### Channel mapping (AMI FBTP.json vs Flax TiogaPass.json)

| Index | FBTP.json Name | FBTP ScaleFactor | Flax Name | Flax ScaleFactor | Notes |
|-------|---------------|-----------------|-----------|-----------------|-------|
| 0 | MB_P3V3 | 0.4107 | MB_ADC_P12V | 1 | **Name and scale wrong in Flax** |
| 1 | MB_P5V | 0.2717 | MB_ADC_P5V_STBY | 1 | **Scale wrong** |
| 2 | MB_P12V | 0.1124 | MB_ADC_P3V3_STBY | 1 | **Name and scale wrong** |
| 3 | MB_P1V05 | (near 1.0) | MB_ADC_P1V8_STBY | 1 | **Name wrong** |
| 4 | MB_PVNN_PCH_STBY | (near 1.0) | MB_ADC_P1V2_STBY | 1 | **Name wrong** |
| 5 | MB_P3V3_STBY | 0.4107 | MB_ADC_P1V05_STBY | 1 | **Name and scale wrong** |
| 6 | MB_P5V_STBY | 0.2717 | MB_ADC_PVNN_PCH_STBY | 1 | **Name and scale wrong** |
| 7 | MB_P3V_BAT | 0.3333 | MB_ADC_P3V3 | 1 | **Name and scale wrong**; needs BridgeGpio P3VBAT_BRIDGE_EN |

The Flax ADC channel names and order are **incorrect** -- they were guessed
during initial bringup.  The AMI FBTP.json provides the authoritative mapping
with correct voltage divider scale factors and thresholds.

### Live ADC readings (from `reference/hwmon/hwmon13.txt`)

| Channel | Raw mV | FBTP Name | Expected V | Derived Scale |
|---------|--------|-----------|------------|--------------|
| in1 (ch0) | 0 | MB_P3V3 | 3.3 V | 0.4107 (off at capture) |
| in2 (ch1) | 0 | MB_P5V | 5.0 V | 0.2717 (off at capture) |
| in3 (ch2) | 1358 | MB_P12V | 12 V | 0.1124 (1358 * 1/0.1124 / 1000 = 12.08 V) |
| in4 (ch3) | 1049 | MB_P1V05 | 1.05 V | ~1.0 (matches 1.05 V standby) |
| in5 (ch4) | 998 | MB_PVNN_PCH_STBY | ~1.0 V | ~1.0 |
| in6 (ch5) | 1362 | MB_P3V3_STBY | 3.3 V | 0.4107 (1362 * 1/0.4107 / 1000 = 3.32 V) |
| in7 (ch6) | 1353 | MB_P5V_STBY | 5.0 V | 0.2717 (1353 * 1/0.2717 / 1000 = 4.98 V) |
| in8 (ch7) | 131 | MB_P3V_BAT | 3.0 V | 0.3333 (low -- bridge may be off) |

Channels 0 and 1 read 0 mV because the main power rails (3.3V, 5V) are off
when the host is powered down.  Standby rails (channels 2-7) show valid readings.

### FBTP.json ADC thresholds (for future Flax config)

| Channel | Name | Scale | CritLow V | CritHigh V | WarnLow V | WarnHigh V |
|---------|------|-------|-----------|-----------|-----------|-----------|
| 0 | MB_P3V3 | 0.4107 | 2.97 | 3.62 | 3.04 | 3.57 |
| 1 | MB_P5V | 0.2717 | 4.52 | 5.49 | 4.61 | 5.4 |
| 2 | MB_P12V | 0.1124 | 10.77 | 13.23 | 11.02 | 12.98 |
| 5 | MB_P3V3_STBY | 0.4107 | 2.97 | 3.62 | 3.04 | 3.57 |
| 6 | MB_P5V_STBY | 0.2717 | 4.52 | 5.49 | 4.61 | 5.4 |
| 7 | MB_P3V_BAT | 0.3333 | 2.73 | 3.74 | - | - |

---

## hwmon Device Map

| hwmon | Driver | I2C Device | Sensors |
|-------|--------|-----------|---------|
| hwmon0 | aspeed_pwm_tacho | platform | fan1_input, fan3_input, pwm1, pwm2 |
| hwmon1 | tmp421 | 6-004e | temp1_input, temp2_input |
| hwmon2 | tmp421 | 6-004f | temp1_input, temp2_input |
| hwmon3 | tmp421 | 8-001f | temp1_input, temp2_input |
| hwmon4-12 | pxe1610 | 5-00{48,4a,50,52,58,5a,68,70,72} | curr1-6, in1-6, power1-6, temp1-3 each |
| hwmon13 | iio_hwmon | platform (ADC) | in1-in8 |

---

## Console / UART Configuration

| UART | Address | Alias | Use | Baud | Status |
|------|---------|-------|-----|------|--------|
| UART1 | 1e783000 | serial0/ttyS0 | Host console (muxed TXD1/RXD1) | - | Enabled |
| UART2 | 1e78d000 | serial1/ttyS1 | SoL host console | - | `obmc-console@ttyS1` running on AMI |
| UART3 | 1e78e000 | serial2/ttyS2 | SoL BMC console | - | Enabled |
| UART4 | 1e78f000 | serial3/ttyS3 | (available) | - | Enabled |
| UART5 | 1e784000 | serial4/ttyS4 | **BMC console** | 115200 | `serial-getty@ttyS4` active |
| VUART | 1e787000 | serial5 | Virtual UART | - | Enabled |

Note: U-Boot uses **57600** baud on UART5 (upstream tiogapass.cfg), while Linux
uses **115200**.  Flax sets 115200 for both.

---

## LPC / KCS / IPMI

| Channel | Address | Status | Notes |
|---------|---------|--------|-------|
| KCS2 | 0xCA8 | Enabled | Primary IPMI channel |
| KCS3 | 0xCA2 | Enabled | Secondary (generates `invalid channel` warning) |
| LPC Snoop | Port 0x80 | Enabled | POST code capture |
| IBT | - | Disabled | |

---

## Running Services (AMI build)

From `reference/systemctl-list-units.txt`.

### Healthy
- bmcweb, avahi, dbus-broker, dropbear (SSH)
- phosphor-ipmi-host, phosphor-ipmi-kcs@ipmi-kcs3, phosphor-ipmi-net@eth0/eth1
- phosphor-pid-control (fan PID), phosphor-watchdog
- start-ipkvm, xyz.openbmc_project.VirtualMedia
- x86-power-control (Intel Power Control)
- ipmb, phosphor-dbus-monitor, phosphor-certificate-manager
- All phosphor state/logging/network/settings/user services

### Failed or crash-looping
| Service | State | Impact |
|---------|-------|--------|
| **EntityManager** | activating/auto-restart | **Root cause** of broken sensors |
| **SetBaseboardFru** | failed | FRU reader (reads GPIO + loads FRU) |
| **LED.GroupManager** | failed | LED groups, blocks `bmc_booted` LED assert |
| adcsensor, fansensor, hwmontempsensor | restart | Waiting on EntityManager |
| ipmbsensor, psusensor, exitairsensor | restart | Waiting on EntityManager |
| intrusionsensor, mcutempsensor | restart | Waiting on EntityManager |
| id-led-off | dead (waiting) | Blocked by LED.GroupManager |

The AMI build's EntityManager crash-loop explains why `busctl tree` shows no
sensor objects.  The sensor daemons are all running but restarting because they
can't find EntityManager's D-Bus configuration objects.

---

## Kernel Configuration Differences

Key differences between AMI kernel config and Flax kernel fragment
(`tiogapass.cfg`):

| Config | AMI | Flax Fragment | Notes |
|--------|-----|---------------|-------|
| `CONFIG_SENSORS_LM75` | y | (not set) | Needed for TMP75 on riser cards |
| `CONFIG_GPIO_PCA953X` | y | (not set) | Needed for PCF8574 on bus 9 |
| `CONFIG_SENSORS_NCT7904` | y | (not set) | May not be needed |
| `CONFIG_SENSORS_PECI_CPUPOWER` | y | (not set) | CPU power via PECI |
| `CONFIG_SENSORS_PECI_DIMMPOWER` | y | (not set) | DIMM power via PECI |
| `CONFIG_W1_MASTER_GPIO` | y | (not set) | 1-Wire over GPIO |
| `CONFIG_RD_XZ` | y | y | XZ initrd decompression |
| `CONFIG_SENSORS_PXE1610` | y | y | Match |
| `CONFIG_SENSORS_ADM1275` | y | (via default) | PMBus subsystem |
| `CONFIG_SENSORS_TMP421` | y | y | Match |
| `CONFIG_SENSORS_INA2XX` | y | y | Match |
| `CONFIG_PECI` | y | y | Match |
| `CONFIG_IPMB_DEVICE_INTERFACE` | y | y | Match |

---

## Comparison: What Flax is still missing vs AMI/Upstream

### DTS gaps (Flax vs AMI)
| Item | AMI | Upstream | Flax | Priority |
|------|-----|---------|------|----------|
| I2C buses 10-13 disabled | Yes | No | No | Low (cosmetic) |
| gpio-leds node for SERVER_POWER_LED | No | No | No | Medium |
| IPMB nodes on bus 4 and 9 | No | Yes | No | Medium (needed for ME sensors) |
| Riser child device nodes | Full | Full | Stripped | OK (intentional) |

### Entity-manager gaps (Flax vs FBTP.json)
| Item | FBTP.json | Flax TiogaPass.json | Priority |
|------|-----------|---------------------|----------|
| ADC names and scale factors | Correct | **Wrong** (guessed) | **High** |
| ADC thresholds | Full | None | High |
| VR sensors (9x pxe1610) | Full (with labels and thresholds) | Missing | Medium |
| IPMB sensors (PCH temp, HSC via ME) | Full | Missing | Medium |
| XeonCPU / PECI sensors | Full (CPU 1 @ 0x30, CPU 2 @ 0x31) | Missing | Medium (needs host on) |
| Riser card sensors (TMP75, INA230) | Full | Missing | Low (no riser) |
| Fan PID zones (FBTP-Zone.json) | Full | Missing | Medium |
| FRU-based probe expression | `FruDevice({'PRODUCT_PRODUCT_NAME': '.*Tioga*', 'BUS': 6})` | `"TRUE"` | Low (testing OK) |
| NVMe sensors | Upstream nvme_config.json | Missing | Low (no drives) |
| BridgeGpio for P3V_BAT ADC | Yes (P3VBAT_BRIDGE_EN, Low) | Missing | Low |

### Service gaps (Flax vs AMI)
| Item | AMI | Flax | Priority |
|------|-----|------|----------|
| fb-powerctrl setup_gpio (BMC_READY, PECI_MUX) | Has custom service | Has rewritten version | OK |
| SetBaseboardFru service | Failed on AMI too | Not present | Low |
| phosphor-pid-control config | Running (FBTP-Zone.json) | Running (no zone config) | Medium |

---

## Reference File Inventory

All captured data lives in `reference/`:

| File | Contents |
|------|----------|
| `ami.dtb` | Binary device tree blob from running AMI firmware |
| `ami-decompiled.dts` | Decompiled DTS (2269 lines) |
| `gpio/debug.txt` | Full GPIO state from `/sys/kernel/debug/gpio` |
| `gpio/info.txt` | `gpioinfo` output (232 lines) |
| `pinctrl-aspeed-g5-pinctrl.txt` | Complete pinmux state |
| `hwmon/hwmon13.txt` | ADC raw readings |
| `pwm-tacho.txt` | Fan RPM and PWM duty readings |
| `thermal.txt` | Thermal zones (empty -- none registered) |
| `i2c/mystery.txt` | Dumps of unknown devices on buses 2, 3, 9 |
| `fru-eeprom.txt` | FRU EEPROM hexdump (bus 6 @ 0x54) |
| `ipmb-me.txt` | IPMB devices, ME bridge test, MC info, channel info |
| `peci/devices.txt` | PECI bus (no clients -- host off) |
| `peci/address.txt` | PECI addresses (none) |
| `power.txt` | Power-related systemd units |
| `power-controls.txt` | x86-power-control JSON config and service unit |
| `mounted.txt` | Filesystem mounts, fstab, disk usage |
| `systemctl-list-units.txt` | All running services |
| `kernel/config.txt` | Full kernel .config (891 lines) |
| `kernel/uname-a.txt` | Kernel version string |
| `entity-manager/` | AMI entity-manager configs (FBTP.json, FBTP-Zone.json, etc.) |
