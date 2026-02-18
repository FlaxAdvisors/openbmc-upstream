FILESEXTRAPATHS:prepend := "${THISDIR}/linux-aspeed:"
SRC_URI += "file://tiogapass.cfg"
SRC_URI += "file://0001-tiogapass-use-64MB-flash-layout.patch"
SRC_URI += "file://0002-tiogapass-fix-adm1278-and-disable-riser-mux.patch"
