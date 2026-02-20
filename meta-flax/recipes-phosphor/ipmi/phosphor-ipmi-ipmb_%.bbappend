FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

IPMB_CHANNELS ?= ""
IPMB_REMOTE_ADDR ?= ""

python do_ipmb_channels() {
    import json

    channels = d.getVar("IPMB_CHANNELS", True) or ""
    remote_addrs = d.getVar("IPMB_REMOTE_ADDR", True) or ""

    channels = channels.split()
    remote_addrs = remote_addrs.split()

    if len(channels) != len(remote_addrs):
        bb.fatal("IPMB_CHANNELS and IPMB_REMOTE_ADDR must have the same number of entries")

    data = {"channels": []}
    for i, (ch, addr) in enumerate(zip(channels, remote_addrs)):
        entry = {
            "type": "ipmb",
            "slave-path": ch,
            "bmc-addr": "0x20",
            "remote-addr": "0x" + addr,
            "devIndex": i,
        }
        data["channels"].append(entry)

    deploy_dir = d.getVar("UNPACKDIR", True)
    with open(deploy_dir + "/ipmb-channels.json", "w") as f:
        json.dump(data, f, indent=4)
}

addtask ipmb_channels after do_unpack before do_install
