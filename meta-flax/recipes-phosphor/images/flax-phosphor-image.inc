# Flax image configuration
# Unlike Facebook, we do NOT remove obmc-net-ipmi, obmc-user-mgmt-ldap, or obmc-ikvm.
# SSH uses default Dropbear (smaller than OpenSSH).

OBMC_IMAGE_EXTRA_INSTALL:append = "\
    curl \
    dbus-top \
    ipmitool \
    iproute2 \
    jq \
    socat \
    strace \
    tcpdump \
    tmux \
    usbutils \
    wget \
    "

IMAGE_LINGUAS = "en-us"

include recipes-phosphor/images/flax-${MACHINE}-phosphor-image.inc
