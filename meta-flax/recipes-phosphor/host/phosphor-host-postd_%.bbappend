FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

EXTRA_OEMESON += "-Dhost-instances='${OBMC_HOST_INSTANCES}'"
