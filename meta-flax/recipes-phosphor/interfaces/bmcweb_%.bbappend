EXTRA_OEMESON:append = "\
    -Dredfish-dbus-log=enabled \
    -Dmutual-tls-auth=enabled \
    -Dredfish-dump-log=enabled \
    -Dexperimental-redfish-dbus-log-subscription=enabled \
    -Dvm-websocket=enabled \
    -Dbasic-auth=enabled \
    -Dcookie-auth=enabled \
"

PACKAGECONFIG:append = " insecure-redfish-expand"
