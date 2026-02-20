# meta-flax Design Review & Recommendations

**Reviewer:** Firmware Engineering
**Date:** 2026-02-19
**Scope:** meta-flax layer (shared) + meta-flax/meta-tiogapass (machine-specific)
**Build:** OpenBMC 2.18.0 / core/2.18.0 branch, AST2500 SoC, 64 MB flash

---

## 1. Executive Summary

The meta-flax layer is a well-structured replacement for meta-facebook that avoids
Facebook's feature removals (no Web UI, no LDAP, no iKVM, no net-IPMI) and
correctly re-enables full OpenBMC functionality. The layer split
(shared `meta-flax/` vs machine-specific `meta-flax/meta-tiogapass/`) is sound.

However, the current implementation has several issues ranging from
misconfigured sensor discovery to broken services, many of which are visible in
the journalctl error log. This document categorizes each error, identifies root
causes, and recommends concrete fixes.

### What Works Well

- **Architecture**: Clean two-layer split; `flax.inc` correctly replaces the
  facebook.inc include chain without inheriting facebook's restrictive removals.
- **x86-power-control**: GPIO mapping in `power-config-host0.json` matches the
  upstream device tree signal names. Power on/off/cycle/reset should work.
- **Entity-manager configs**: FBTP.json has comprehensive sensor definitions
  with correct I2C addresses matching the AMI OEM reference data.
- **FBTP-Zone.json**: Stepwise fan profile based on inlet temperature is a
  reasonable starting point matching the AMI FSC table.
- **Kernel config**: All necessary drivers enabled (TMP421, PXE1610, ADM1278,
  PECI, TPM, INA2XX, IPMB).
- **64 MB flash**: Patch and FLASH_SIZE correctly configured.
- **SOL/Console**: ttyS2 for host, ttyS4 for BMC correctly mapped.
- **BIOS update**: Working flash procedure with ME recovery mode.

### Critical Issues

1. FBTP.json Probe never matches (no FRU device on bus 6 with matching product name)
2. In-band IPMI (KCS channel 15) is not configured in channel_config.json
3. flax-ipmi-oem (fb-ipmi-oem) builds against wrong machine context
4. obmc-fru-fault-monitor.service has a bad ExecStart path
5. Fan/sensor hwmon paths not matched by dbus-sensors
6. Entity-manager ships ~35 irrelevant configuration JSONs

---

## 2. Layer Structure Assessment

### 2.1 What Can Be Simplified

| Area | Current | Recommendation |
|------|---------|----------------|
| Entity-manager configs | 37 JSON files from Intel reference platforms | Remove all except FBTP.json, FBTP-Zone.json, and TiogaPass.json (if used) |
| Schemas | 6 schema files shipped | These are upstream defaults; remove from layer unless customized |
| fb-powerctrl | Custom power-util + setup_gpio scripts | Keep setup_gpio; power-util duplicates x86-power-control busctl interface |
| dbus-broker bbappend | Adds RPROVIDES/RREPLACES for dbus | May be needed; verify if still required with current solver |
| phosphor-fan extras | Custom poweroff targets and stub script | Stub does nothing; remove or implement |
| flax-ipmi-oem | Builds fb-ipmi-oem from upstream | Needs machine-specific meson config or will fail at runtime |
| busybox wall/timeout | Extra applets enabled | Fine as-is; minimal overhead |

### 2.2 Files to Remove from Entity-Manager Configurations

These configs will never match on TiogaPass and add ~200 KB to the image and
slow down entity-manager probe cycles:

```
1Ux16 Riser.json, 2Ux8 Riser.json, 8X25 HSBP.json,
A2UL16RISER.json, A2UX8X4RISER.json, AHW1UM2RISER.json,
AXX1P100HSSI_AIC.json, AXX2PRTHDHD.json, BNP Baseboard.json,
CYP-baseboard.json, Delta DPS-750XB PSU.json,
F1U12X25 HSBP.json, F1U4X25 HSBP.json, F2U12X35 HSBP.json,
F2U8X25 HSBP.json, FBYV2.json, FCXXPDBASSMBL_PDB.json,
Flextronics S-1100ADU00-201 PSU.json, Intel Front Panel.json,
MIDPLANE-2U2X12SWITCH.json, NVME P4000.json, OPB2RH-Chassis.json,
PCIE SSD Retimer.json, PSSF132202A.json, PSSF162205A.json,
PSSF212201A.json, PSSF222201A.json, R1000 Chassis.json,
R2000 Chassis.json, SAS Module.json, STP Baseboard.json,
STP P4000 Chassis.json, SOLUM_PSSF162202_PSU.json,
SensorSBFan.json, SensorBoard.json, TNP-baseboard.json,
WC-Baseboard.json, WFT Baseboard.json, WP-Baseboard.json
```

Keep only: **FBTP.json** and **FBTP-Zone.json** (and TiogaPass.json if it
serves a distinct purpose, but currently appears redundant with FBTP.json).

### 2.3 fb-powerctrl vs x86-power-control

There is overlap:
- `x86-power-control` handles chassis/host state via GPIO with proper D-Bus
  integration, systemd targets, and power policies.
- `fb-powerctrl/power-util` is a shell wrapper calling the same busctl
  properties that x86-power-control exposes.

**Recommendation**: Keep `setup_gpio` (for BMC_READY and PECI_MUX_SELECT init)
as a standalone oneshot service. Consider removing `power-util` or marking it as
a convenience alias only; it should NOT be on the ExecStart path of any systemd
service that competes with x86-power-control's state machine.

The `host-poweron.service` and `host-poweroff.service` in fb-powerctrl may
conflict with x86-power-control's own targets. Verify that
`phosphor-state-manager` bbappend correctly wires the state transitions to
x86-power-control and not to fb-powerctrl.

---

## 3. Journalctl Error Analysis

### 3.1 CRITICAL — Broken Services & Missing Functionality

#### 3.1.1 Entity-Manager Probe Failure
```
Can't find matched I2C, GPIO or Hwmon configuration
Failed GetSubTree call for configuration interface: ...ResourceNotFound
```

**Root Cause**: FBTP.json probe is:
```json
"Probe": "xyz.openbmc_project.FruDevice({'PRODUCT_PRODUCT_NAME': '.*Tioga*', 'BUS': 6})"
```
This requires a FRU EEPROM on I2C bus 6 with a product name matching `.*Tioga*`.
The device tree defines an `at24c64` EEPROM at bus 6 address 0x54 (FRU EEPROM).
For this probe to work:
1. The FRU EEPROM must be accessible (it is — bus 6 @ 0x54 confirmed by AMI scan)
2. `fru-device` daemon must successfully parse the FRU binary
3. The PRODUCT_PRODUCT_NAME field must match the regex

The AMI OEM data shows the FRU product name is `Type6 Tioga Pass Single Side` —
the regex `.*Tioga*` should match this. If fru-device fails to read the EEPROM
at all (bad address, driver conflict), the probe will never fire.

**Resolution**:
1. Verify `fru-device` can read bus 6 address 0x54: `busctl tree xyz.openbmc_project.FruDevice`
2. If the EEPROM address is wrong, fix it in FBTP.json or the blacklist
3. Check that the `blacklist.json` entry `{"BUS": 0, "ADDRESS": 80}` (0x50 on
   bus 0) is not inadvertently blocking bus 6 devices
4. As a fallback, change the Probe to a simpler match like
   `"TRUE"` (always match) since this is a single-board system

#### 3.1.2 In-Band IPMI (KCS) Not Working
```
Invalid channel name: ipmi_kcs3
```

**Root Cause**: The upstream device tree defines KCS channels 2 and 3
(`&kcs3` and `&kcs4` nodes). The default meta-phosphor `channel_config.json`
maps channel 15 to `ipmi_kcs3` for in-band host IPMI. However, meta-flax's
`channel_config.json` marks channel 15 as `RESERVED` with `is_valid: false`.

This means:
- The host cannot send IPMI commands to the BMC via KCS
- BIOS POST IPMI queries will fail
- SOL activation from the host side won't work
- ipmitool from the host OS won't work

**Resolution**: Add channel 15 to meta-flax's `channel_config.json`:
```json
"15": {
    "name": "ipmi_kcs3",
    "is_valid": true,
    "active_sessions": 0,
    "channel_info": {
        "medium_type": "system-interface",
        "protocol_type": "kcs",
        "session_supported": "session-less",
        "is_ipmi": true
    }
}
```

#### 3.1.3 fb-ipmi-oem Dynamic Commands Crash
```
ERROR opening IPMI provider /usr/lib/ipmid-providers/libdynamiccmds.so.0.1:
  undefined symbol: _ZN5boost7process2v25error22get_exit_code_categoryEv
```

**Root Cause**: `flax-ipmi-oem` builds `fb-ipmi-oem` from upstream master
(commit `27010c1`). This version uses `boost::process::v2` which requires a
newer Boost than what's available in the OpenBMC 2.18.0 toolchain. The symbol
`boost::process::v2::error::get_exit_code_category()` is missing from the
runtime Boost libraries.

**Resolution options** (pick one):
1. **Pin to an older fb-ipmi-oem revision** that doesn't use boost::process::v2
   (pre-May 2024 commits)
2. **Upgrade Boost** in the build (may cascade to other recipes)
3. **Disable the crashdump/process-launching features** via meson options
4. **Remove fb-ipmi-oem entirely** if no Facebook OEM IPMI commands are needed
   (most are Facebook-datacenter-specific and irrelevant for standalone use)

**Recommendation**: Option 4 is simplest. The TiogaPass in standalone use
doesn't need Facebook OEM IPMI netfn commands. Remove `flax-ipmi-oem` from
`packagegroup-flax-apps` RDEPENDS and the recipe.

#### 3.1.4 obmc-fru-fault-monitor Bad ExecStart
```
obmc-fru-fault-monitor.service: Neither a valid executable name nor an
  absolute path: usr/libexec/phosphor-led-manager/phosphor-fru-fault-monitor
```

**Root Cause**: The service file has `ExecStart=usr/libexec/...` without a
leading `/`. This is an upstream bug in meta-phosphor's
`phosphor-led-manager_git.bb` service file.

**Resolution**: Create a bbappend to fix the path, or disable the fault monitor
if LED fault indication is not wired on TiogaPass:
```
# In meta-flax/recipes-phosphor/leds/phosphor-led-manager_%.bbappend
SYSTEMD_AUTO_ENABLE:${PN}-faultmonitor = "disable"
```

#### 3.1.5 LED Heartbeat Missing
```
Error setting property for physical LED...heartbeat
  ...ResourceNotFound
```

**Root Cause**: The `led-group-config.json` references a `heartbeat` LED, but
no physical LED sysfs entry exists at
`/xyz/openbmc_project/led/physical/heartbeat`. The upstream device tree does not
define any LED nodes (no `gpio-leds` node). The AST2500 on TiogaPass does have a
heartbeat LED (`SERVER_POWER_LED` on GPIO AA2), but it's not wired as a
kernel `gpio-leds` device.

**Resolution**: Either:
1. Add a `gpio-leds` node to the device tree patch for TiogaPass:
   ```dts
   leds {
       compatible = "gpio-leds";
       heartbeat {
           gpios = <&gpio ASPEED_GPIO(AA, 2) GPIO_ACTIVE_LOW>;
           linux,default-trigger = "heartbeat";
       };
   };
   ```
2. Or remove the heartbeat reference from `led-group-config.json` and use an
   `identify` LED only (or remove the LED config entirely if not wired).

#### 3.1.6 SOL / Host Console Connection Refused
```
Failed to start SOL payload: connect: Connection refused
Encountered exception when starting host console...connect: Connection refused
```

**Root Cause**: `obmc-console-server` for ttyS2 fails to connect because the
UART routing (`aspeed-uart-routing`) may not be configured. The
`server.ttyS2.conf` has:
```
aspeed-uart-routing = "OBMC_SOL_ROUTING"
```
But `OBMC_SOL_ROUTING` is set to empty string (`""`) by default in the
bbappend. On AST2500, UART routing must be explicitly configured to connect
UART3 (IO2) to UART2 for SOL to work.

**Resolution**: Set `OBMC_SOL_ROUTING` in the TiogaPass machine config:
```
OBMC_SOL_ROUTING = "io2:uart2"
```
Or remove the `aspeed-uart-routing` line from `server.ttyS2.conf` if UART
routing is already handled by the device tree (the upstream DTS does configure
`lpc-ctrl` and `lpc-snoop` but not UART routing explicitly).

For QEMU: SOL won't work because QEMU doesn't emulate the AST2500 UART routing
hardware. The workaround is to use a pty-based console instead.

### 3.2 HIGH — Sensor & Hardware Errors

#### 3.2.1 TMP421 Instantiation Failures
```
Failed to instantiate 'tmp421' at address '31' on bus '8'
Failed to instantiate 'tmp421' at address '78' on bus '6'
Failed to instantiate 'tmp421' at address '79' on bus '6'
i2c i2c-6: Failed to register i2c client tmp421 at 0x4e (-16)
i2c i2c-6: Failed to register i2c client tmp421 at 0x4f (-16)
i2c i2c-8: Failed to register i2c client tmp421 at 0x1f (-16)
tmp421 6-004e: Could not read configuration register (-6)
tmp421 6-004f: Could not read configuration register (-6)
tmp421 8-001f: Could not read configuration register (-6)
```

**Root Cause**: The device tree already statically instantiates TMP421 devices
on buses 6 and 8. Then `dbus-sensors` / entity-manager tries to dynamically
instantiate them again, causing `-EBUSY` (-16) registration failures. The `-6`
(ENXIO) errors mean the devices are not responding — possibly because the mezz
card (bus 8) is absent, or the TMP421 chips need host power for their remote
channel.

**Resolution**:
1. Since the device tree already creates these devices, entity-manager should
   NOT try to instantiate them. Set `"CreatesHWMon": false` or remove the
   `"Bus"` and `"Address"` fields from the TMP421 entries in FBTP.json to let
   dbus-sensors find them via hwmon scan instead of I2C instantiation.
2. For the mezz TMP421 on bus 8 — if no mezzanine card is installed, this
   sensor will always fail. Add it to the blacklist or make it conditional.

#### 3.2.2 PXE1610 VR Failures
```
pxe1610 5-0048: Failed to read PMBUS_MFR_ID
pxe1610 5-004a: Failed to read PMBUS_MFR_ID
... (all 9 VR addresses)
```

**Root Cause**: The PXE1610 voltage regulators on bus 5 require host power to
respond. When the host is off, they are power-gated and the PMBus reads fail.
This is **expected behavior** during standby.

**Resolution**: No action needed — these errors are cosmetic during standby.
However, to reduce log noise, consider:
1. Making VR sensors `CPURequired` or `PowerState: "BiosPost"` in
   entity-manager config so dbus-sensors only polls them when the host is on
2. Or simply accept the one-time error at boot

#### 3.2.3 ADM1278 HSC Failure
```
adm1275 7-0045: Failed to read Manufacturer ID
```

**Root Cause**: The HSC is on bus 7 @ 0x45. The device tree instantiates it
as `adm1278`. The driver probes it as adm1275 (parent driver). If the device
isn't responding, it may need standby power which is present. More likely, the
I2C scan in the AMI OEM reference shows 0x45 (7-bit) responding, so this should
work.

Check if there's an I2C bus speed issue — the upstream DTS sets bus 7 to
standard 100 kHz. The ADM1278 supports up to 400 kHz. This error may be
transient (timing issue during boot) or indicate the HSC variant is different
(ADM1293 instead of ADM1278).

**Resolution**: Verify the device responds with `i2cdetect -y 7`. If the
device is an ADM1293 or similar, update the device tree compatible string.

#### 3.2.4 Fan Sensor Errors
```
'aspeed_pwm_tacho' not found in sensor whitelist
'iio_hwmon' not found in sensor whitelist
'ast2500-adc' not found in sensor whitelist
failed to find match for '/sys/class/hwmon/hwmon0/fan1_input'
failed to find match for '/sys/class/hwmon/hwmon0/fan3_input'
Sensor name: MB_FAN0, reading error!
Sensor name: MB_FAN1, reading error!
Error read/write '/sys/class/hwmon/hwmon0/pwm1_enable'
Error read/write '/sys/class/hwmon/hwmon0/pwm2_enable'
```

**Root Cause**: Multiple issues:

1. **Sensor whitelist**: `dbus-sensors` uses a whitelist to determine which
   hwmon drivers to scan. The drivers `aspeed_pwm_tacho`, `iio_hwmon`, and
   `ast2500-adc` are not in the default whitelist.

2. **hwmon path mismatch**: The fan tach inputs are at
   `/sys/class/hwmon/hwmon0/fan1_input` and `fan3_input` (0-indexed: channels 0
   and 2 as defined in the device tree). FBTP.json references tach indices 0 and
   2 which should map correctly, but the entity-manager config says
   `"Type": "AspeedFan"` which dbus-sensors maps to the `aspeed_pwm_tacho`
   driver — if that driver isn't whitelisted, discovery fails.

3. **PWM enable**: Writing to `pwm1_enable` / `pwm2_enable` fails if the hwmon
   driver doesn't support the `pwm_enable` attribute or if the file permissions
   are wrong.

**Resolution**:
1. Ensure dbus-sensors is built with `PACKAGECONFIG:append = " fansensor"` (or
   equivalent) and that the fan sensor daemon scans for `aspeed_pwm_tacho`.
2. Check if entity-manager needs a config that maps to the correct hwmon path.
3. For the whitelist: the `dbus-sensors` fansensor binary should inherently
   know about `aspeed_pwm_tacho`. If it doesn't, this may be a version mismatch.

#### 3.2.5 PCA9544 Mux Failure
```
pca954x 1-0071: probe failed
```

**Root Cause**: The riser I2C mux (PCA9544 at bus 1 address 0x71) is defined in
the device tree but the physical mux doesn't respond because no riser card is
installed. The mux is power-gated when no riser is present.

**Resolution**: This is expected with no riser installed. To suppress:
1. Remove the PCA9544 node from the device tree (requires a kernel patch), or
2. Use `status = "disabled"` in a DTS overlay, or
3. Accept the boot-time error (harmless — mux buses 16-19 will not exist but
   no sensors on those buses will be probed either)

### 3.3 MEDIUM — Network & Service Errors

#### 3.3.1 NCSI Ethernet Errors
```
ftgmac100 1e660000.ethernet eth0: NCSI: Handler for packet type 0x82 returned -19
ftgmac100 1e660000.ethernet eth0: NCSI: No GMA handler available for MFR-ID (0x0)
ftgmac100 1e680000.ethernet eth1: NCSI: No channel found to configure!
ftgmac100 1e6[68]0000.ethernet: Error applying setting, reverse things back
GetEthInfo failed on eth0: ioctl 0x8946: No such device
GetEthInfo failed on eth1: ioctl 0x8946: No such device
can't find matched NIC name.
```

**Root Cause**:
- **eth0**: NCSI is working but the NIC doesn't provide a GMA (Get MAC Address)
  OEM handler. Packet type 0x82 = AEN (Asynchronous Event Notification) which
  returns -ENODEV (-19). These are warnings, not failures.
- **eth1**: No NCSI channel found because on the FB ODM board, eth1 has no
  physical NIC connected (no LAN-on-motherboard RJ45 for the Intel NIC). The
  device tree enables both MACs but only eth0 (shared NCSI) has a physical link.
- **GetEthInfo/ioctl**: `phosphor-network` tries to query both interfaces but
  eth1 may not come up.

**Resolution**:
1. Consider disabling `&mac1` in the device tree to prevent eth1 errors entirely
2. Or accept eth1 errors as cosmetic (it won't get an IP but won't break
   anything)
3. The `systemd-networkd-wait-online --any` configuration already handles this
   correctly — it only waits for one interface

#### 3.3.2 DHCPv6 Configuration Warning
```
/etc/systemd/network/01-bmc-eth.network:19: Unknown key 'ClientIdentifier'
  in section [DHCPv6], ignoring.
```

**Root Cause**: The `01-bmc-eth.network` file has `ClientIdentifier=duid` in
the `[DHCPv6]` section, but the systemd version in OpenBMC 2.18.0 doesn't
support this key in `[DHCPv6]` (it's a `[DHCP]` section key for DHCPv4).

**Resolution**: Remove `ClientIdentifier=duid` from the `[DHCPv6]` section. The
DHCPv6 DUID is already configured via `DUIDType=link-layer` and `IAID=0`.

#### 3.3.3 mDNS Stack Conflict
```
*** WARNING: Detected another IPv4 mDNS stack running on this host ***
*** WARNING: Detected another IPv6 mDNS stack running on this host ***
```

**Root Cause**: Both `avahi-daemon` and `systemd-resolved` (or bmcweb's built-in
mDNS) are trying to bind to the mDNS port 5353.

**Resolution**: Disable one of them. Since OpenBMC uses avahi for service
discovery, either:
1. Disable `systemd-resolved` mDNS: add `MulticastDNS=no` to `resolved.conf`
2. Or remove avahi if bmcweb handles its own mDNS (less common)

#### 3.3.4 LDAP Connection Errors
```
[8b4567] <group(all)> failed to bind to LDAP server ldap://127.0.0.1/:
  Can't contact LDAP server: Transport endpoint is not connected
```

**Root Cause**: `nslcd` (or `sssd`) is configured to connect to a local LDAP
server at 127.0.0.1, but no LDAP server is running locally. This is the default
configuration when LDAP is enabled in DISTRO_FEATURES but not configured.

**Resolution**: This is harmless but noisy. Either:
1. Configure LDAP properly if you want it, or
2. Disable `nslcd.service` at runtime until LDAP is needed:
   `systemctl disable nslcd.service`
3. Or remove LDAP from DISTRO_FEATURES if not needed:
   `DISTRO_FEATURES:remove = "ldap"` in `flax.inc`

### 3.4 LOW — Cosmetic & Expected Errors

#### 3.4.1 iKVM Core Dump
```
Process 348 (obmc-ikvm) of user 0 dumped core.
obmc-ikvm.service: Failed with result 'core-dump'.
```

**Root Cause**: `obmc-ikvm` crashes because:
1. `Failed to open video device` — no `/dev/video0` because the AST2500 video
   capture driver isn't loaded or there's no video signal
2. `Failed to search USB virtual hub port` — the USB gadget for HID
   (keyboard/mouse emulation) isn't configured

On TiogaPass, iKVM requires:
- The AST2500 video engine driver (aspeed-video)
- USB gadget configuration for HID device
- A host with video output connected

**Resolution for hardware**: Ensure the kernel config has `CONFIG_VIDEO_ASPEED=y`
and USB gadget mode is configured. This may need a device tree update to enable
the `&vhub` node.

**Resolution for QEMU**: iKVM cannot work in QEMU (no video capture hardware
emulation). Mask the service in QEMU testing:
`systemctl mask obmc-ikvm.service`

#### 3.4.2 Virtual Media / NBD Errors
```
I/O error, dev nbd0, sector ... (multiple)
block nbd0: shutting down sockets
UDC core: mass-storage: couldn't find an available UDC or it's busy
[vm_websocket.hpp:...] Error in VM socket write Broken pipe
```

**Root Cause**: Virtual media requires:
1. A USB Device Controller (UDC) — the AST2500 has one but it may not be
   configured as a gadget
2. The `mass-storage` USB gadget function
3. NBD (Network Block Device) connected to a remote image

The `UDC core: mass-storage: couldn't find an available UDC` error means the
USB gadget subsystem isn't properly initialized.

**Resolution**: Enable the USB gadget in the device tree:
```dts
&vhub {
    status = "okay";
};
```
And ensure `CONFIG_USB_GADGET=y`, `CONFIG_USB_ASPEED_VHUB=y`,
`CONFIG_USB_MASS_STORAGE=m` in the kernel config.

For QEMU: Virtual media won't work (no UDC emulation). Accept the errors.

#### 3.4.3 Watchdog Pretimeout Governor
```
Failed to set watchdog pretimeout governor to 'panic': No such file or directory
```

**Root Cause**: The kernel doesn't support watchdog pretimeout governors
(`CONFIG_WATCHDOG_PRETIMEOUT_GOV` not enabled or the `panic` governor isn't
built).

**Resolution**: Either add to `tiogapass.cfg`:
```
CONFIG_WATCHDOG_PRETIMEOUT_GOV=y
CONFIG_WATCHDOG_PRETIMEOUT_DEFAULT_GOV_PANIC=y
```
Or ignore (the watchdog will still work, just without a pretimeout action).

#### 3.4.4 rsyslog Queue Warnings
```
queue "action-X-builtin:omfile queue": queue.highWaterMark is set below queue size
```

**Root Cause**: rsyslog default queue sizes don't match the configured values.
Harmless — rsyslog auto-adjusts.

**Resolution**: No action needed.

#### 3.4.5 BMC UUID Not Found
```
Failed in reading BMC UUID property: ...InternalFailure
No Object has implemented the interface: xyz.openbmc_project.Common.UUID
```

**Root Cause**: No service provides the UUID interface. This affects IPMI
`Get Device GUID` command and Redfish `ServiceRoot.UUID`.

**Resolution**: The BMC UUID should be generated from the MAC address or a
random seed. `phosphor-bmc-code-mgmt` or `bmcweb` usually provides this. Check
if `phosphor-bmc-code-mgmt` is installed and running.

#### 3.4.6 SpecialMode Errors
```
error getting SpecialMode status: 'No route to host'
```

**Root Cause**: Some service is trying to contact the `SpecialMode` D-Bus
interface (used by AMI/Intel for manufacturing mode). This interface doesn't
exist in standard OpenBMC.

**Resolution**: Ignore, or track down which daemon is querying it (likely
`fb-ipmi-oem` — another reason to remove it).

#### 3.4.7 IPMI User Data File
```
Error in reading IPMI user data file
```

**Root Cause**: First boot — no user data file exists yet. `phosphor-ipmi-host`
creates it on first user configuration.

**Resolution**: Harmless on first boot. Will not recur after initial setup.

#### 3.4.8 SSL Handshake Failures
```
[http_connection.hpp:244] ... SSL handshake failed
```

**Root Cause**: Clients connecting to bmcweb port 443 without proper TLS
configuration, or automated health checks using HTTP instead of HTTPS.

**Resolution**: Cosmetic — normal in environments with monitoring tools probing
the HTTPS port.

#### 3.4.9 HTTP Response Body on No-Content
```
[http_response.hpp:213] Response content provided but code was no-content
  or not_modified
```

**Root Cause**: bmcweb bug — some handlers return a body with 204/304 status
codes. Upstream bmcweb issue.

**Resolution**: No action needed from meta-flax. Will be fixed when bmcweb is
updated upstream.

#### 3.4.10 overlayfs Warnings
```
overlayfs: ...falling back to redirect_dir=nofollow.
overlayfs: ...falling back to uuid=null.
overlayfs: failed to set xattr on upper
```

**Root Cause**: JFFS2 doesn't support all overlayfs features (xattrs, redirect
dirs, UUID). Standard for OpenBMC with JFFS2 overlay.

**Resolution**: No action needed. Standard behavior.

#### 3.4.11 UBI Attach Failure
```
ubi0 error: ubi_attach_mtd_dev: failed to attach mtd5, error -22
ubi0 error: ubi_read_volume_table: the layout volume was not found
```

**Root Cause**: The flash layout uses JFFS2, not UBI. The UBI subsystem tries
to attach mtd5 but finds no UBI volume table. This is the `pflash` (PNOR)
partition intended for host BIOS, which may be formatted differently.

**Resolution**: If UBI is not used, disable `CONFIG_MTD_UBI` in the kernel
config to eliminate these messages. Or just ignore them.

#### 3.4.12 Power Button/Reset Button Errors
```
Fail to get button Enabled property (.../Power0): Invalid argument
Fail to get button Enabled property (.../Reset0): Invalid argument
```

**Root Cause**: `button-handler` service looks for a
`xyz.openbmc_project.Chassis.Buttons` D-Bus interface that `x86-power-control`
should provide. If `x86-power-control` hasn't started yet or the GPIO
detection failed, these properties won't exist.

**Resolution**: Check startup ordering. These may be transient boot-time race
conditions. If persistent, verify GPIO line names match between
`power-config-host0.json` and the device tree.

#### 3.4.13 Misc Kernel
```
Couldn't write '16' to 'kernel/sysrq': No such file or directory
lastlog_openseek / lastlog_perform_login: /var/log/lastlog errors
syslogin_perform_logout: No such file or directory
```

**Resolution**: All harmless. SysRq not compiled in. lastlog not relevant for
BMC embedded system.

---

## 4. QEMU Testing Improvements

### 4.1 What Works in QEMU

- Basic boot, D-Bus services, bmcweb, IPMI host emulation (ipmitool local)
- Network (user-mode or tap networking)
- Most phosphor-* daemons

### 4.2 What Cannot Work in QEMU

| Feature | Reason | Workaround |
|---------|--------|------------|
| SOL | No UART routing hardware emulation | Use `socat` pty bridge to simulate host console |
| iKVM | No AST2500 video capture | Mask `obmc-ikvm.service` |
| Virtual Media | No USB Device Controller | Mask `phosphor-virtual-media` |
| FRU EEPROM | No I2C bus emulation with real devices | Write a fake FRU binary to /tmp and inject via dbus |
| Fan/Sensor hardware | No PWM/tach, ADC, TMP421 | Use phosphor-virtual-sensor with mock values |
| PECI | No CPU package emulation | Mock CPU temp via virtual sensors |
| KCS | Partial — QEMU emulates KCS but no host-side | Test via ipmitool local only |

### 4.3 Recommended QEMU Test Configuration

Create a QEMU-specific machine config or overlay that:

1. **Masks hardware-dependent services**:
   ```
   obmc-ikvm.service
   phosphor-pid-control.service (no fans)
   ```

2. **Provides mock FRU data**: Write a script that populates the FRU device
   inventory via D-Bus so entity-manager can probe.

3. **Uses virtual sensors**: The existing `virtual_sensor_config.json`
   references `MB_INLET_TEMP` which won't exist without hardware. Create a
   QEMU-specific virtual sensor config with static test values.

4. **SOL testing**: Use the obmc-console-server with a pty pair:
   ```bash
   socat pty,raw,echo=0,link=/dev/ttyS2 pty,raw,echo=0,link=/tmp/host-console &
   ```

---

## 5. Recommended Changes — Priority Order

### P0 — Must Fix (broken functionality)

| # | Change | Files | Impact |
|---|--------|-------|--------|
| 1 | Add KCS channel 15 to channel_config.json | `phosphor-ipmi-config/channel_config.json` | Enables in-band IPMI |
| 2 | Fix or remove flax-ipmi-oem | `flax-ipmi-oem_git.bb`, `packagegroup-flax-apps.bb` | Eliminates ipmid crash |
| 3 | Fix entity-manager probe (verify FRU EEPROM read) | `FBTP.json` probe, blacklist.json | Enables sensor discovery |
| 4 | Fix obmc-fru-fault-monitor path or disable it | `phosphor-led-manager_%.bbappend` | Eliminates service failure |
| 5 | Set OBMC_SOL_ROUTING for host console | `obmc-console_%.bbappend` or machine conf | Enables SOL |

### P1 — Should Fix (reduces noise, improves stability)

| # | Change | Files | Impact |
|---|--------|-------|--------|
| 6 | Remove 35+ irrelevant entity-manager JSON configs | `entity-manager/configurations/` | Faster boot, less confusion |
| 7 | Fix DHCPv6 ClientIdentifier in network config | `01-bmc-eth.network` | Eliminates warning |
| 8 | Disable eth1/mac1 if unused | Device tree patch | Eliminates NCSI errors |
| 9 | Resolve mDNS stack conflict | resolved.conf or avahi config | Eliminates mDNS warning |
| 10 | Add LED heartbeat DTS node or remove from config | DTS patch or led-group-config.json | Eliminates LED error |

### P2 — Nice to Have (polish)

| # | Change | Files | Impact |
|---|--------|-------|--------|
| 11 | Add USB gadget/vhub DTS node for virtual media | DTS patch + kernel config | Enables virtual media |
| 12 | Add watchdog pretimeout governor config | tiogapass.cfg | Cleaner watchdog behavior |
| 13 | QEMU test overlay / mock config | New files | Enables QEMU testing |
| 14 | Remove fb-powerctrl power-util (redundant) | fb-powerctrl recipe | Reduces confusion |
| 15 | Disable nslcd if LDAP not configured | systemd preset or DISTRO_FEATURES | Reduces log noise |

---

## 6. ADC Sensor Name Correction

The AMI OEM reference data (AMI_OEM.md) provides authoritative ADC
channel-to-rail mapping that differs from the current FBTP.json. The FBTP.json
sensor names appear correct (MB_P3V3, MB_P5V, MB_P12V, etc.) and match the AMI
OEM sensor names. The scale factors in FBTP.json use the iio_hwmon internal
2.5V reference convention, while the AMI OEM data uses a 1.8V reference. Since
dbus-sensors' ADC sensor daemon uses the kernel's iio_hwmon which already
handles the reference voltage internally, the FBTP.json scale factors should be
correct as-is for producing the right voltage readings.

**However**, verify that the ScaleFactor values account for the voltage divider
ratios correctly:

| ADC Ch | Rail | FBTP.json ScaleFactor | AMI OEM ScaleFactor | Match? |
|--------|------|----------------------|--------------------| ------|
| 0 | P3V3 | 0.4107 | 0.4107 | Yes |
| 1 | P5V | 0.2717 | 0.2717 | Yes |
| 2 | P12V | 0.1124 | 0.0643 | **No** — different ref voltage |
| 3 | P1V05 | (none) | 0.5695 | Need to add |
| 4 | PVNN_PCH | (none) | 0.569 | Need to add |
| 5 | P3V3_STBY | 0.4107 | 0.2308 | **No** — different ref voltage |
| 6 | P5V_STBY | 0.2717 | 0.1503 | **No** — different ref voltage |
| 7 | P3V_BAT | 0.3333 | special | Bridge GPIO |

The scale factor differences are because FBTP.json uses the divider ratio
(resistor network ratio), while AMI_OEM.md computes the inverse of the full
ADC conversion factor including the 1.8V reference. Since the Linux iio_hwmon
driver reports raw millivolts at the ADC pin (already scaled by the ADC
reference internally), the FBTP.json `ScaleFactor` is the **divider ratio**
(Vout/Vin) and is used by dbus-sensors to convert from pin voltage to rail
voltage: `rail_voltage = pin_voltage / ScaleFactor`. This should be correct
if the divider ratios are right.

---

## 7. dev_id.json Review

Current values:
```json
{
  "id": 32,
  "revision": 129,
  "addn_dev_support": 191,
  "manuf_id": 40981,
  "prod_id": 12614,
  "aux": 0
}
```

The AMI OEM reference shows:
- Device ID: 32 (matches)
- Manufacturer ID: 40092 (Wiwynn) — **does NOT match** 40981
- Product ID: 7220 (0x1c34) — **does NOT match** 12614 (0x3146)

**Recommendation**: Update to match the actual hardware:
```json
{
  "id": 32,
  "revision": 1,
  "addn_dev_support": 191,
  "manuf_id": 40092,
  "prod_id": 7220,
  "aux": 0
}
```

Or use the IANA PEN for the organization running the BMC (not necessarily
Wiwynn if this is a custom deployment).

---

## 8. Summary of Estimated Effort

| Priority | Items | Effort |
|----------|-------|--------|
| P0 | 5 critical fixes | 1-2 days |
| P1 | 5 noise-reduction items | 1 day |
| P2 | 5 polish items | 2-3 days |
| **Total** | **15 items** | **~1 week** |

The meta-flax layer is a solid foundation. The critical issues are all
configuration-level (JSON, bbappend, channel config) rather than architectural.
No major redesign is needed — just targeted fixes to complete the integration.
