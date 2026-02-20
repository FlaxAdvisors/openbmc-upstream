# dbus-broker is a drop-in replacement for dbus-daemon but the upstream
# recipe only sets RCONFLICTS without RPROVIDES/RREPLACES, so the solver
# cannot use it to satisfy the "dbus" dependency from systemd.
RPROVIDES:${PN} += "dbus"
RREPLACES:${PN} += "dbus"
