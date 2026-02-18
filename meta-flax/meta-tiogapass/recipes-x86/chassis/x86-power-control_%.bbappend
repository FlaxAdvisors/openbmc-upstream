FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"
EXTRA_OEMESON += "-Dchassis-system-reset=enabled"

SRC_URI:append = " file://power-config-host0.json"

do_install:append() {
    install -d ${D}${datadir}/${PN}
    install -m 0644 ${UNPACKDIR}/power-config-host0.json ${D}${datadir}/${PN}
}
