FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append = " file://01-bmc-eth.network"

do_install:append() {
    install -d ${D}${sysconfdir}/systemd/network/
    install -m 0644 ${UNPACKDIR}/01-bmc-eth.network ${D}${sysconfdir}/systemd/network/
}
