# OpenVPN with Traffic Control GUI

This project sets up an OpenVPN client with traffic control capabilities using Docker containers. It utilizes separate networks for LAN and WAN traffic via macvlan.

## Prerequisites

* Linux system with `dnsmasq`, and Docker support
* Docker and Docker Compose installed
* Two physical or virtual network interfaces (for WAN and LAN separation)
* OpenVPN client configuration file (for final deployment only)

## Project Structure

```
./
├── docker-compose.yml        # Docker services configuration
├── .env                      # Environment variables
├── build.sh                  # Initial setup & VPN config validation script
├── start.sh                  # Final startup & routing configuration
├── iptables/                 # Directory for iptables rules to be saved
├── openvpn/                  # OpenVPN client service
│   ├── docker/
│   │   └── Dockerfile         # OpenVPN container build configuration
│   ├── openvpn.sh            # OpenVPN startup script
│   └── vpn/
│       └── openvpn_client_1.ovpn  # Your OpenVPN client config (added later)
└── tcgui/                    # Traffic Control GUI service
    ├── docker/
    │   └── Dockerfile         # TC-GUI container build configuration
    ├── main.py               # TC-GUI Python application
    ├── static/
    │   └── gui_styles.css    # TC-GUI styling
    └── templates/
        └── main.html         # TC-GUI web interface template
```

## Build Instructions (`build.sh`)

Run this script first to install required system packages and Docker. It also tests for the **absence** of the VPN config file.

```bash
chmod +x build.sh
./build.sh
```

* Installs Docker and tools (runs only once)
* Builds all Docker images
* Starts OpenVPN container briefly
* Checks for `VPN CA cert missing!` log message
* If VPN config is **present**, instructs user to remove it

> ✅ If validation passes (VPN config is missing), you will see:
>
> ```
> [✓] You may now continue to the next script (start.sh) to complete the setup.
> [→] Make sure the ethernet interfaces are connected to the correct WAN and LAN networks.
> ```

---

## Startup Instructions (`start.sh`)

After you've completed `build.sh` and placed the `.ovpn` file:

```bash
chmod +x start.sh
./start.sh
```

This script will:

* Validate presence of network interfaces (WAN and LAN)
* Configure `/etc/network/interfaces` and `dnsmasq` (once)
* Start OpenVPN and optionally the Traffic Control GUI
* Check for missing VPN cert and **abort** if it's missing
* Set container routing and NAT (via tun0)
* Save iptables rules
* Start dnsmasq inside the container

---

## Environment Configuration (`.env`)

```dotenv
LAN_INTERFACE=eth0
WAN_INTERFACE=eth1

LAN_SUBNET=192.168.21.0/24
LAN_IP_ADDRESS=192.168.21.10
LAN_IP=192.168.21.11
LAN_RANGE=192.168.21.20,192.168.21.254

WAN_SUBNET=192.168.20.0/24
WAN_GATEWAY=192.168.20.1
WAN_IP_ADDRESS=192.168.20.10
WAN_IP=192.168.20.11

# Container Name Configuration
CONTAINER_NAME=openvpn_client_1

VPN_CONFIG_PATH=./openvpn/vpn/openvpn_client_1.ovpn
TIMEZONE=CET

ENABLE_TC=false

DNS1=10.8.0.1
DNS2=
```

You may optionally override DNS1/DNS2 with Google, Cloudflare, OpenDNS, or Quad9.

---

## Systemd Service Setup

To autostart the full setup at boot:

1. Create a service file:

   ```bash
   sudo nano /etc/systemd/system/openvpn-tc.service
   ```
2. Add:

   ```ini
   [Unit]
   Description=OpenVPN with Traffic Control
   After=network-online.target docker.service
   Wants=network-online.target
   Requires=docker.service

   [Service]
   Type=simple
   WorkingDirectory=/opt/openvpn-tc
   ExecStart=/opt/openvpn-tc/start.sh
   ExecStop=/usr/bin/docker compose -f /opt/openvpn-tc/docker-compose.yml down
   Restart=on-failure
   RestartSec=5s

   [Install]
   WantedBy=multi-user.target
   ```
3. Install:

   ```bash
   sudo mkdir -p /opt/openvpn-tc
   sudo cp -r * /opt/openvpn-tc/
   sudo chown -R root:root /opt/openvpn-tc
   sudo chmod +x /opt/openvpn-tc/start.sh
   ```
4. Enable and start:

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable openvpn-tc
   sudo systemctl start openvpn-tc
   sudo systemctl status openvpn-tc
   ```

---

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file.

## Credits

This project builds on:

* [dperson/openvpn-client](https://github.com/dperson/openvpn-client)
* [tum-lkn/tcgui](https://github.com/tum-lkn/tcgui)
