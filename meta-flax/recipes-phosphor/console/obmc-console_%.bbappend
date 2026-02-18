FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

require conf/recipes/flax-consoles.inc

# Keep SSH console enabled (unlike Facebook which removes it)
# Remove default config so we can supply our own.
SRC_URI:remove = "file://${BPN}.conf"

OBMC_BMC_TTY = "ttyS4"
SERVER_CONFS = "${@ ' '.join([ f'file://server.{i}.conf' for i in d.getVar('OBMC_CONSOLE_TTYS', True).split() ])}"

SRC_URI:append = " ${SERVER_CONFS}"
SRC_URI:append = " file://client.conf "

OBMC_SOL_ROUTING ?= ""

do_install:append() {
  install -m 0644 ${UNPACKDIR}/client.conf ${D}${sysconfdir}/${BPN}/client.conf
}

do_install:prepend() {
    if [ -f "${UNPACKDIR}/server.${OBMC_CONSOLE_HOST_TTY}.conf" ]; then
        sed -i "s/\"OBMC_SOL_ROUTING\"/${OBMC_SOL_ROUTING}/g" ${UNPACKDIR}/server.${OBMC_CONSOLE_HOST_TTY}.conf
    fi
}
