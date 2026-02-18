FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append = " file://flax_host_settings.override.yml"

SETTINGS_HOST_TEMPLATES:append = " flax_host_settings.override.yml"
