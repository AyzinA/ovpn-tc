# OpenVPN with Traffic Control GUI

This project sets up an OpenVPN client with traffic control capabilities using Docker containers. It uses separate networks for LAN and WAN traffic.

## Prerequisites

- Docker and Docker Compose
- Network interface with support for multiple networks
- OpenVPN client configuration file
- Linux system with `iptables` and `dnsmasq` support

## Project Structure

```
./
├── docker-compose.yml    # Docker services configuration
├── .env                  # Environment variables
├── start.sh             # Setup and initialization script
├── iptables/            # Directory for iptables rules backup
├── openvpn/             # OpenVPN client service
│   ├── docker/
│   │   └── Dockerfile   # OpenVPN container build configuration
│   ├── openvpn.sh       # OpenVPN startup script
│   └── vpn/             # OpenVPN configuration files
│       └── client.ovpn  # Your OpenVPN client config (you need to add this)
└── tcgui/              # Traffic Control GUI service
    ├── docker/
    │   └── Dockerfile   # TC-GUI container build configuration
    ├── main.py          # TC-GUI Python application
    ├── static/
    │   └── gui_styles.css  # TC-GUI styling
    └── templates/
        └── main.html    # TC-GUI web interface template
```

## Setup Instructions

1. Prepare your environment:
   - Copy your OpenVPN client configuration to `./openvpn/vpn/openvpn_client_1.ovpn`
   - Configure the `.env` file with your network settings:
     ```env
     # Network Interfaces
     LAN_INTERFACE=eth0          # LAN network interface name
     WAN_INTERFACE=eth0          # WAN network interface name

     # LAN Network Configuration
     LAN_SUBNET=192.168.20.0/24  # LAN network subnet
     LAN_GATEWAY=192.168.20.1    # LAN network gateway
     LAN_IP=192.168.20.11        # OpenVPN client IP on LAN network

     # WAN Network Configuration
     WAN_SUBNET=192.168.21.0/24  # WAN network subnet
     WAN_GATEWAY=192.168.21.1    # WAN network gateway
     WAN_IP=192.168.21.11        # OpenVPN client IP on WAN network

     # OpenVPN Configuration
     VPN_CONFIG_PATH=./openvpn/vpn/openvpn_client_1.ovpn
     TIMEZONE=CET

     # Traffic Control Configuration
     ENABLE_TC=true             # Set to 'true' to enable Traffic Control, 'false' to disable

     # Traffic Control GUI Configuration
     TCGUI_IP=0.0.0.0
     TCGUI_PORT=5000
     ```

2. Make the start script executable:
   ```bash
   chmod +x start.sh
   ```

3. Run the start script:
   ```bash
   ./start.sh
   ```
   The script will:
   - Start the Docker containers (OpenVPN client and optionally Traffic Control)
   - Configure routing in the OpenVPN client container
   - Set up NAT rules for the VPN tunnel
   - Start the DNS service
   - Save iptables rules for backup

   Note: The Traffic Control service will only start if `ENABLE_TC=true` in your `.env` file

4. Access the Traffic Control GUI:
   - Open your browser and navigate to `http://localhost:5000`
   - The interface will allow you to manage traffic shaping rules

## Network Architecture

- LAN Network: 192.168.20.0/24
  - Gateway: 192.168.20.1
  - OpenVPN client IP: 192.168.20.11

- WAN Network: 192.168.21.0/24
  - Gateway: 192.168.21.1
  - OpenVPN client IP: 192.168.21.11

## Troubleshooting

1. Check network interfaces:
   ```bash
   ip addr show
   ```

2. Verify container networks:
   ```bash
   docker network ls
   docker network inspect lan_vpn_net
   docker network inspect wan_vpn_net
   ```

3. Check container logs:
   ```bash
   docker-compose logs openvpn_client
   docker-compose logs tc-server
   ```

4. Check iptables rules:
   ```bash
   cat ./iptables/openvpn_client_1_rules.v4
   ```

5. Verify DNS service:
   ```bash
   docker exec openvpn_client_1 ps aux | grep dnsmasq
   ```

## Note

The `start.sh` script must be run each time you want to start the services, as it sets up the necessary routing and NAT rules. Simply running `docker-compose up -d` is not sufficient.
