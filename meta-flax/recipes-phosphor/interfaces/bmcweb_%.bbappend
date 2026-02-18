EXTRA_OEMESON:append = "\
    -Dredfish-dbus-log=enabled \
    -Dmeta-tls-common-name-parsing=enabled \
    -Dredfish-dump-log=enabled \
    -Dexperimental-redfish-dbus-log-subscription=enabled \
    -Dvm-websocket=enabled \
    -Dbasic-auth=enabled \
    -Dcookie-auth=enabled \
"

PACKAGECONFIG:append = " insecure-redfish-expand"
