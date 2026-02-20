SUMMARY = "OpenBMC for Flax - Applications"
PR = "r1"

inherit packagegroup

PROVIDES = "${PACKAGES}"
PACKAGES = " \
        ${PN}-extras \
        ${PN}-fans \
        ${PN}-flash \
        ${PN}-system \
        ${PN}-chassis \
        ${PN}-hostmgmt \
        "

PROVIDES += "virtual/obmc-chassis-mgmt"
PROVIDES += "virtual/obmc-fan-mgmt"
PROVIDES += "virtual/obmc-flash-mgmt"
PROVIDES += "virtual/obmc-system-mgmt"

RPROVIDES:${PN}-chassis += "virtual-obmc-chassis-mgmt"
RPROVIDES:${PN}-fans += "virtual-obmc-fan-mgmt"
RPROVIDES:${PN}-flash += "virtual-obmc-flash-mgmt"
RPROVIDES:${PN}-system += "virtual-obmc-system-mgmt"

SUMMARY:${PN}-chassis = "Flax Chassis"

SUMMARY:${PN}-extras:tiogapass = "Extra features for tiogapass"
RDEPENDS:${PN}-extras:tiogapass = "phosphor-nvme"

SUMMARY:${PN}-fans = "Flax Fans"
RDEPENDS:${PN}-fans = " \
        phosphor-pid-control \
        "

SUMMARY:${PN}-flash = "Flax Flash"
RDEPENDS:${PN}-flash = " \
        phosphor-software-manager \
        "

RDEPENDS_PN_SYSTEM_EXTRAS = " \
        phosphor-ipmi-ipmb \
        flax-ipmi-oem \
        phosphor-sel-logger \
        phosphor-post-code-manager \
        phosphor-host-postd \
        phosphor-state-manager \
        "

SUMMARY:${PN}-system = "Flax System"
RDEPENDS:${PN}-system = " \
        entity-manager \
        dbus-sensors \
        phosphor-virtual-sensor \
        phosphor-gpio-monitor-monitor \
        tzdata-core \
        flax-common-functions \
        ${RDEPENDS_PN_SYSTEM_EXTRAS} \
        "
