#!/bin/bash

set -e
set -a
source .env
set +a

# --- One-time Network Setup ---
if [ ! -f /etc/.openvpn_tc_network_setup_done ]; then
    echo "[+] Running one-time network and dnsmasq setup..."

    echo "[+] Configuring network interfaces..."
    cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto $WAN_INTERFACE
iface $WAN_INTERFACE inet static
  address $WAN_IP_ADDRESS
  netmask 255.255.255.0
  gateway $WAN_GATEWAY

auto $LAN_INTERFACE
iface $LAN_INTERFACE inet static
  address $LAN_IP_ADDRESS
  netmask 255.255.255.0
EOF

    echo "[+] Restarting networking service..."
    systemctl restart networking

    echo "[+] Configuring dnsmasq..."
    cat > /etc/dnsmasq.conf <<EOF
dhcp-range=$LAN_RANGE,255.255.255.0,12h
dhcp-option=option:router,$LAN_IP
dhcp-option=option:dns-server,8.8.8.8
dhcp-authoritative
EOF

    echo "[+] Restarting dnsmasq service..."
    systemctl restart dnsmasq

    echo "[+] Setting resolver..."
    echo "nameserver 8.8.8.8" > /etc/resolv.conf

    # Marker file to avoid re-running this section
    touch /etc/.openvpn_tc_network_setup_done
    echo "[✓] Initial network setup complete."
else
    echo "[i] Network already set up. Skipping..."
fi

# --- Docker Compose Logic ---
echo "[+] Managing Docker services..."
docker compose -f docker-compose.yml down

if [ "$ENABLE_TC" = "true" ]; then
    echo "Starting OpenVPN client and Traffic Control services..."
    docker compose -f docker-compose.yml up -d
else
    echo "Starting OpenVPN client only (Traffic Control disabled)..."
    docker compose -f docker-compose.yml up -d openvpn_client
fi

# Wait for initialization
sleep 2

# --- VPN Config Check ---
echo "[+] Checking logs for VPN cert error..."
if docker logs "${CONTAINER_NAME}" 2>&1 | grep -q "ERROR: VPN CA cert missing!"; then
    echo "[!] Detected missing VPN CA certificate. Stopping container..."
    docker stop "${CONTAINER_NAME}"
    docker rm "${CONTAINER_NAME}"
    echo "[✗] Cannot continue without a valid VPN configuration file."

    if [ -d "$VPN_CONFIG_PATH" ]; then
        rm -rf "$VPN_CONFIG_PATH"
    fi

    exit 1
fi

# --- Continue Setup ---
echo "[✓] No VPN cert error detected. Continuing setup..."

# Routing adjustments inside container
echo "[+] Adjusting container routing..."
docker exec ${CONTAINER_NAME} sh -c "ip route del default || true"
docker exec ${CONTAINER_NAME} sh -c "ip route add default via ${WAN_GATEWAY} dev eth1"

# Wait for tun0 interface
docker exec ${CONTAINER_NAME} sh -c "
while [[ ! -d /sys/class/net/tun0 ]]; do
    echo 'Waiting for tun0 to come up in ${CONTAINER_NAME} container...'
    sleep 1
done"

# Add NAT rule for tun0
echo "[+] Adding iptables POSTROUTING MASQUERADE rule..."
docker exec ${CONTAINER_NAME} sh -c "iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE"

# Save iptables rules
echo "[+] Saving iptables rules to host..."
mkdir -p ./iptables
docker exec ${CONTAINER_NAME} iptables-save > ./iptables/${CONTAINER_NAME}_rules.v4

# Start dnsmasq inside container
echo "[+] Starting dnsmasq inside the container..."
docker exec ${CONTAINER_NAME} sh -c "dnsmasq"

echo "[✓] Setup complete. iptables rules saved in ./iptables/"

# --- Create systemd service ---
if [ ! -f /etc/.openvpn_tc_service_created ]; then
    echo "[+] Creating systemd service..."

    cat > /etc/systemd/system/openvpn-tc.service <<EOF
[Unit]
Description=OpenVPN with Traffic Control
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.service

[Service]
Type=simple
WorkingDirectory=$(pwd)
ExecStart=$(pwd)/service.sh
ExecStop=/usr/bin/docker compose -f $(pwd)/docker-compose.yml down
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 /etc/systemd/system/openvpn-tc.service
    chmod 755 service.sh

    echo "[+] Reloading systemd daemon..."
    systemctl daemon-reexec
    systemctl daemon-reload

    echo "[+] Enabling openvpn-tc.service..."
    systemctl enable --now openvpn-tc.service

    # Wait for initialization
    sleep 2

    # Marker to prevent re-creation
    touch /etc/.openvpn_tc_service_created

    echo "[✓] Systemd service created and enabled. You can now use:"
    echo "    systemctl start openvpn-tc"
    echo "    systemctl stop openvpn-tc"
    echo "    systemctl restart openvpn-tc"
    echo "    systemctl status openvpn-tc"
else
    echo "[i] Systemd service already created. Skipping..."
fi