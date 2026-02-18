FILESEXTRAPATHS:append := ":${THISDIR}/${PN}"
SRC_URI:append = " file://TiogaPass.json"

do_install:append() {
     install -d ${D}${datadir}/entity-manager/configurations
     install -m 0444 ${UNPACKDIR}/TiogaPass.json ${D}${datadir}/entity-manager/configurations
}
