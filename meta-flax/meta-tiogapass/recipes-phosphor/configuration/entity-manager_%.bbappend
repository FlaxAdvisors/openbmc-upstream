FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"
SRC_URI:append = " \
    file://blacklist.json \
    file://configurations \
    "

do_install:append() {
     install -d ${D}${datadir}/entity-manager/configurations
     install -d ${D}${datadir}/entity-manager/configurations/schemas
     install -m 0444 ${UNPACKDIR}/blacklist.json ${D}${datadir}/entity-manager/blacklist.json
     install -m 0444 ${UNPACKDIR}/configurations/*.json ${D}${datadir}/entity-manager/configurations/
     install -m 0444 ${UNPACKDIR}/configurations/schemas/*.json ${D}${datadir}/entity-manager/configurations/schemas/
}
