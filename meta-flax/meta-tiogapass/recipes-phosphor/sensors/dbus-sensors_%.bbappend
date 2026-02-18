FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# Re-add sensors that may be removed at the shared layer level
PACKAGECONFIG:append = " intelcpusensor ipmbsensor"
