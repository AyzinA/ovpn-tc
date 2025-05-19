FROM alpine:3.20.3

# Install packages
RUN apk --no-cache --no-progress upgrade && \
    apk --no-cache --no-progress add \
        bash \
        curl \
        iptables \
        ip6tables \
        openvpn \
        tcpdump \
        vim \
        net-tools \
        htop \
        mtr \
        openrc \
        dnsmasq \
        shadow \
        shadow-login \
        tini \
        tzdata && \
    addgroup -S vpn && \
    rm -rf /tmp/*

# Configure dnsmasq to use Google DNS
RUN echo -e "no-resolv\nserver=8.8.8.8\nserver=8.8.4.4" > /etc/dnsmasq.conf
# Cloudflare
#RUN echo -e "no-resolv\nserver=1.1.1.1\nserver=1.0.0.1" > /etc/dnsmasq.conf
# OpenDNS
#RUN echo -e "no-resolv\nserver=208.67.222.222\nserver=208.67.220.220" > /etc/dnsmasq.conf
# Quad9
#RUN echo -e "no-resolv\nserver=9.9.9.9\nserver=149.112.112.112" > /etc/dnsmasq.conf

# Copy startup script
COPY openvpn.sh /usr/bin/openvpn.sh
RUN chmod +x /usr/bin/openvpn.sh

# Enable IP forwarding
RUN echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf

# Healthcheck: confirms public IP is retrievable (indicates tunnel is up)
HEALTHCHECK --interval=60s --timeout=15s --start-period=120s \
    CMD curl -fsSL https://api.ipify.org || exit 1

# Define a volume for mounting the OpenVPN config
VOLUME ["/vpn"]

# Use tini as the entrypoint to handle PID 1 and signals cleanly
ENTRYPOINT ["/sbin/tini", "--", "/usr/bin/openvpn.sh"]
