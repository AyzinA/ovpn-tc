#!/bin/bash

# Source environment variables
set -a
source .env
set +a

# Step 1: Tear down existing services
docker compose -f docker-compose.yml down

# Step 2: Start services based on configuration
if [ "$ENABLE_TC" = "true" ]; then
    echo "Starting OpenVPN client and Traffic Control services..."
    docker compose -f docker-compose.yml up -d
else
    echo "Starting OpenVPN client only (Traffic Control disabled)..."
    docker compose -f docker-compose.yml up -d openvpn_client
fi

# Wait a bit for the containers to initialize
sleep 2

# Step 2: Update routing table inside the OpenVPN client container
# Remove any existing default route (if present)
docker exec openvpn_client_1 sh -c "ip route del default || true"

# Add a new default route via the WAN gateway using eth1
docker exec openvpn_client_1 sh -c "ip route add default via ${WAN_GATEWAY} dev eth1"

# Step 3: Wait for the OpenVPN tunnel interface (tun0) to appear
docker exec openvpn_client_1 sh -c "
    while [[ ! -d /sys/class/net/tun0 ]]; do
        echo 'Waiting for tun0 to come up in openvpn_client_1 container...'
        sleep 1
    done"

# Step 4: Set up NAT so packets leaving via tun0 are masqueraded
echo -e "\nAdding POSTROUTING to iptables NAT of container 'openvpn_client_1'"
docker exec openvpn_client_1 sh -c "iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE"
echo -e "\nPOSTROUTING Added successfully"
sleep 1

# Step 5: Confirm setup completed
echo -e "\nContainers started and added iptables POSTROUTING MASQUERADE rules to each"

# Step 6: Save the iptables rules to a file on the host (for backup or audit)
docker exec openvpn_client_1 iptables-save > ./iptables/openvpn_client_1_rules.v4

# Step 7: Start dnsmasq (DHCP and DNS service) inside the container
docker exec openvpn_client_1 sh -c "dnsmasq"

# Final message with hint
echo -e "iptables were saved into ./iptables/ \n\
    => Check out the volumes section in the docker-compose.yml !!!"
