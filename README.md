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
├── service.sh                # Systemd service script that will run at system startup
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
* Automatically creates and enables a systemd service called `openvpn-tc.service` (once)

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

## Systemd Service (Automated via Script)

This project includes an automated setup for a systemd service that will run OpenVPN with Traffic Control if enabled at system startup.

### Service File Details

The following systemd unit is created at `/etc/systemd/system/openvpn-tc.service`:

```ini
[Unit]
Description=OpenVPN with Traffic Control
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.service

[Service]
Type=simple
WorkingDirectory=/opt/openvpn-tc
ExecStart=/opt/openvpn-tc/service.sh
ExecStop=/usr/bin/docker compose -f /opt/openvpn-tc/docker-compose.yml down
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

> Note: `WorkingDirectory` and `ExecStart` are automatically adjusted to the current working directory when `start.sh` is executed.

### Commands to Use

- Start: `sudo systemctl start openvpn-tc`
- Stop: `sudo systemctl stop openvpn-tc`
- Restart: `sudo systemctl restart openvpn-tc`
- Status: `sudo systemctl status openvpn-tc`

This service ensures that the OpenVPN client container and routing/NAT logic are automatically restored at system boot.

---

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file.

## Credits

This project builds on:

* [dperson/openvpn-client](https://github.com/dperson/openvpn-client)
* [tum-lkn/tcgui](https://github.com/tum-lkn/tcgui)
