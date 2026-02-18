# Flax shared machine configuration
# Replaces the facebook.inc → facebook-withhost → facebook-compute →
# facebook-compute-singlehost include chain.
#
# Key differences from Facebook:
#   - Web UI enabled (no phosphor-no-webui)
#   - LDAP enabled (not removed from DISTRO_FEATURES)
#   - iKVM enabled (not removed from IMAGE_FEATURES)
#   - avahi/mDNS enabled
#   - Serial console at 115200 baud (OEM default)

DISTROOVERRIDES .= ":flax"

# cgroup support
require conf/distro/include/cgroup.inc

# DO NOT include phosphor-no-webui.inc — we want the web UI
# DO NOT include phosphor-production.inc — keep development features

# --- Machine features (combined from facebook.inc + withhost + compute-singlehost) ---
MACHINE_FEATURES += "\
        obmc-bmc-state-mgmt \
        obmc-phosphor-fan-mgmt \
        obmc-phosphor-flash-mgmt \
        obmc-chassis-state-mgmt \
        obmc-host-state-mgmt \
        obmc-phosphor-chassis-mgmt \
        obmc-host-ipmi \
        "

# --- Virtual runtime providers ---
VIRTUAL-RUNTIME_obmc-host-state-manager = "x86-power-control"
VIRTUAL-RUNTIME_obmc-chassis-state-manager = "x86-power-control"
VIRTUAL-RUNTIME_skeleton_workbook = "${MACHINE}-config"

# --- Package providers ---
PREFERRED_PROVIDER_virtual/obmc-chassis-mgmt = "packagegroup-flax-apps"
PREFERRED_PROVIDER_virtual/obmc-fan-mgmt = "packagegroup-flax-apps"
PREFERRED_PROVIDER_virtual/obmc-flash-mgmt = "packagegroup-flax-apps"
PREFERRED_PROVIDER_virtual/obmc-inventory-data ?= "${VIRTUAL-RUNTIME_skeleton_workbook}"
PREFERRED_PROVIDER_virtual/obmc-system-mgmt = "packagegroup-flax-apps"
PREFERRED_PROVIDER_virtual/obmc-host-ipmi-hw = "phosphor-ipmi-kcs"

# --- Image features ---
# Enable root login (adds root to ipmi, web, redfish, priv-admin groups)
IMAGE_FEATURES:append = " allow-root-login"

# --- Serial console at OEM default 115200 baud ---
SERIAL_CONSOLES:flax = "115200;ttyS4"

# --- Organization YAML ---
OBMC_ORG_YAML_SUBDIRS:append:flax = " com/meta"
