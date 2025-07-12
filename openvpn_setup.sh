#!/bin/bash

set -e
set -a
source .env
set +a

# Define marker files
SETUP_MARKER="/etc/.openvpn_tc_docker_setup_done"
NETWORK_MARKER="/etc/.openvpn_tc_network_setup_done"
SERVICE_MARKER="/etc/.openvpn_tc_service_created"

# Function to perform initial system setup (build.sh logic)
setup_system() {
    if [ ! -f "$SETUP_MARKER" ]; then
        echo "[+] First-time setup: Installing required packages and Docker..."

        apt update && apt upgrade -y
        apt install -y \
            dnsmasq \
            tcpdump \
            htop \
            vim \
            ncdu \
            curl \
            wget \
            net-tools \
            ca-certificates

        echo "[+] Adding Docker's official GPG key..."
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc

        echo "[+] Adding Docker repository..."
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
          $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
          tee /etc/apt/sources.list.d/docker.list > /dev/null

        apt-get update
        apt-get install -y \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            docker-buildx-plugin \
            docker-compose-plugin

        touch "$SETUP_MARKER"
        echo "[✓] Docker and required packages installed."
    else
        echo "[i] Docker and system dependencies already installed. Skipping setup..."
    fi

    echo "[+] Building Docker containers..."
    docker compose -f docker-compose.yml build
    echo "[✓] Docker containers built successfully."

    echo "[+] Attempting to start OpenVPN container without VPN config..."
    docker compose -f docker-compose.yml up -d openvpn_client || true

    echo "[i] If the VPN config is missing, the container will stop and be removed."
    sleep 2

    echo "[+] Checking logs for VPN cert error..."
    if docker logs "${CONTAINER_NAME}" 2>&1 | grep -q "ERROR: VPN CA cert missing!"; then
        echo "[!] Detected missing VPN CA certificate — this is expected in this validation step."
        
        echo "[i] Stopping and removing container..."
        docker stop "${CONTAINER_NAME}" || true
        docker rm "${CONTAINER_NAME}" || true
        
        if [ -d "$VPN_CONFIG_PATH" ]; then
            rm -rf "$VPN_CONFIG_PATH"
        fi

        echo "[✓] You may now run './openvpn_setup.sh start' to complete the setup."
        echo "[→] Make sure the ethernet interfaces are connected to the correct WAN and LAN networks."
        exit 0
    else
        echo "[!] VPN config appears to exist. This validation should run without a VPN config."
        
        echo "[!] Please remove the file:"
        echo "    -> ${VPN_CONFIG_PATH}"
        echo "[i] Then re-run './openvpn_setup.sh setup' to validate the missing config case properly."

        echo "[i] Stopping and removing container..."
        docker stop "${CONTAINER_NAME}" || true
        docker rm "${CONTAINER_NAME}" || true

        if [ -d "$VPN_CONFIG_PATH" ]; then
            rm -rf "$VPN_CONFIG_PATH"
        fi

        echo "[✗] Exiting because VPN config was unexpectedly found."
        exit 1
    fi
}

# Function to configure network and start services (start.sh logic)
start_services() {
    # One-time network setup
    if [ ! -f "$NETWORK_MARKER" ]; then
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

        touch "$NETWORK_MARKER"
        echo "[✓] Initial network setup complete."
    else
        echo "[i] Network already set up. Skipping..."
    fi

    # Docker Compose logic
    echo "[+] Managing Docker services..."
    docker compose -f docker-compose.yml down

    if [ "$ENABLE_TC" = "true" ]; then
        echo "Starting OpenVPN client and Traffic Control services..."
        docker compose -f docker-compose.yml up -d
    else
        echo "Starting OpenVPN client only (Traffic Control disabled)..."
        docker compose -f docker-compose.yml up -d openvpn_client
    fi

    sleep 2

    # VPN Config Check
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

    # Continue Setup
    echo "[✓] No VPN cert error detected. Continuing setup..."

    echo "[+] Adjusting container routing..."
    docker exec "${CONTAINER_NAME}" sh -c "ip route del default || true"
    docker exec "${CONTAINER_NAME}" sh -c "ip route add default via ${WAN_GATEWAY} dev eth1"

    echo "[+] Waiting for tun0 interface..."
    docker exec "${CONTAINER_NAME}" sh -c "
    while [[ ! -d /sys/class/net/tun0 ]]; do
        echo 'Waiting for tun0 to come up in ${CONTAINER_NAME} container...'
        sleep 1
    done"

    echo "[+] Adding iptables POSTROUTING MASQUERADE rule..."
    docker exec "${CONTAINER_NAME}" sh -c "iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE"

    echo "[+] Saving iptables rules to host..."
    mkdir -p ./iptables
    docker exec "${CONTAINER_NAME}" iptables-save > ./iptables/${CONTAINER_NAME}_rules.v4

    echo "[+] Starting dnsmasq inside the container..."
    docker exec "${CONTAINER_NAME}" sh -c "dnsmasq"

    echo "[✓] Setup complete. iptables rules saved in ./iptables/"

    # Create systemd service
    if [ ! -f "$SERVICE_MARKER" ]; then
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
ExecStart=$(pwd)/openvpn_setup.sh service
ExecStop=/usr/bin/docker compose -f $(pwd)/docker-compose.yml down
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

        chmod 644 /etc/systemd/system/openvpn-tc.service
        chmod 755 "$0"

        echo "[+] Reloading systemd daemon..."
        systemctl daemon-reexec
        systemctl daemon-reload

        echo "[+] Enabling openvpn-tc.service..."
        systemctl enable --now openvpn-tc.service

        sleep 2

        touch "$SERVICE_MARKER"
        echo "[✓] Systemd service created and enabled. You can now use:"
        echo "    systemctl start openvpn-tc"
        echo "    systemctl stop openvpn-tc"
        echo "    systemctl restart openvpn-tc"
        echo "    systemctl status openvpn-tc"
    else
        echo "[i] Systemd service already created. Skipping..."
    fi
}

# Function to run as a systemd service (service.sh logic)
run_service() {
    echo "[+] Starting Docker container as a systemd service..."
    docker compose -f docker-compose.yml down

    if [ "$ENABLE_TC" = "true" ]; then
        docker compose -f docker-compose.yml up -d
    else
        docker compose -f docker-compose.yml up -d openvpn_client
    fi

    sleep 2

    echo "[+] Checking logs for VPN cert error..."
    if docker logs "${CONTAINER_NAME}" 2>&1 | grep -q "ERROR: VPN CA cert missing!"; then
        echo "[!] Detected missing VPN CA certificate. Stopping container..."
        docker stop "${CONTAINER_NAME}"
        docker rm "${CONTAINER_NAME}"
        echo "[✗] Cannot continue without a valid VPN configuration file."
        exit 1
    fi

    echo "[✓] No VPN cert error detected. Continuing setup..."

    echo "[+] Adjusting container routing..."
    docker exec "${CONTAINER_NAME}" sh -c "ip route del default || true"
    docker exec "${CONTAINER_NAME}" sh -c "ip route add default via ${WAN_GATEWAY} dev eth1"

    echo "[+] Waiting for tun0 interface..."
    docker exec "${CONTAINER_NAME}" sh -c "
    while [[ ! -d /sys/class/net/tun0 ]]; do
        echo 'Waiting for tun0 to come up in ${CONTAINER_NAME} container...'
        sleep 1
    done"

    echo "[+] Adding iptables POSTROUTING MASQUERADE rule..."
    docker exec "${CONTAINER_NAME}" sh -c "iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE"

    echo "[+] Saving iptables rules to host..."
    mkdir -p iptables
    docker exec "${CONTAINER_NAME}" iptables-save > iptables/${CONTAINER_NAME}_rules.v4

    echo "[+] Starting dnsmasq inside the container..."
    docker exec "${CONTAINER_NAME}" sh -c "dnsmasq"

    echo "[✓] Setup complete. iptables rules saved."

    if [ "$ENABLE_TC" = "true" ]; then
        exec docker compose -f docker-compose.yml logs -f
    else
        exec docker compose -f docker-compose.yml logs -f openvpn_client
    fi
}

# Main logic based on command-line argument
case "$1" in
    setup)
        setup_system
        ;;
    start)
        start_services
        ;;
    service)
        run_service
        ;;
    *)
        echo "Usage: $0 {setup|start|service}"
        echo "  setup: Install dependencies, build Docker containers, and validate missing VPN config."
        echo "  start: Configure network, start services, and set up systemd service."
        echo "  service: Run as a systemd service."
        exit 1
        ;;
esac