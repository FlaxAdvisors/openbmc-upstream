FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append = " file://ttyS2.conf"
OBMC_BMC_TTY = "ttyS4"
