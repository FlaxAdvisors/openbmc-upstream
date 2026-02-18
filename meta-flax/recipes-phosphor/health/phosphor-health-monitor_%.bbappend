FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI:append = " file://bmc_health_config.json"

CPU_CRIT_VAL = "90.0"
CPU_CRIT_TGT = "reboot.target"
CPU_WARN_VAL = "80.0"
CPU_WARN_TGT = ""
MEM_CRIT_VAL = "10.0"
MEM_CRIT_TGT = "reboot.target"
MEM_WARN_VAL = "15.0"
MEM_WARN_TGT = ""
STORAGE_CRIT_VAL = "5.0"
STORAGE_WARN_VAL = "10.0"

do_install:prepend() {
    sed -i \
        -e "s|\"CPU_CRIT_VAL\"|${CPU_CRIT_VAL}|g" \
        -e "s|\"CPU_CRIT_TGT\"|\"${CPU_CRIT_TGT}\"|g" \
        -e "s|\"CPU_WARN_VAL\"|${CPU_WARN_VAL}|g" \
        -e "s|\"CPU_WARN_TGT\"|\"${CPU_WARN_TGT}\"|g" \
        -e "s|\"MEM_CRIT_VAL\"|${MEM_CRIT_VAL}|g" \
        -e "s|\"MEM_CRIT_TGT\"|\"${MEM_CRIT_TGT}\"|g" \
        -e "s|\"MEM_WARN_VAL\"|${MEM_WARN_VAL}|g" \
        -e "s|\"MEM_WARN_TGT\"|\"${MEM_WARN_TGT}\"|g" \
        -e "s|\"STORAGE_CRIT_VAL\"|${STORAGE_CRIT_VAL}|g" \
        -e "s|\"STORAGE_WARN_VAL\"|${STORAGE_WARN_VAL}|g" \
        ${UNPACKDIR}/bmc_health_config.json
}
