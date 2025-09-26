# IPsec Manager for strongSwan on Debian

A simple yet powerful Bash script to manage multiple strongSwan IPsec VPN connections. This tool automates the entire process of connecting, routing, and disconnecting, making it ideal for developers and system administrators who frequently switch between different IPsec VPNs on Debian systems.

![Language](https://img.shields.io/badge/language-Bash-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Platform](https://img.shields.io/badge/platform-Debian-A81D33.svg)

## Features

-   **Multi-VPN Management**: Easily manage multiple VPN profiles.
-   **Full Automation**: Automates tunnel initiation, virtual IP detection, and network route setup.
-   **Intelligent Detection**: Automatically detects the active network interface and the virtual IP assigned by the server.
-   **"Smart Stop" Command**: The `stop` command automatically finds and terminates the active connection without needing its name.
-   **Clear Status Command**: A clean `status` command to view active connection details, including uptime and configured routes.
-   **Clean Configuration**: Separates logic from data by using an external configuration file for VPN routes.
-   **System-Wide Command**: Can be easily installed as a system-wide command for access from anywhere in the terminal.
-   **Debug Mode**: An optional debug mode to troubleshoot connection issues.

## Prerequisites

-   A Linux distribution based on **Debian**. The script was developed and tested on **Debian 12 (Bookworm)** and **Debian Testing (Trixie/Forky)**. It is expected to be compatible with derivatives like **Ubuntu**, **Mint**, etc.
-   `strongswan` and its `swanctl` utility installed (`sudo apt install strongswan`).
-   Your strongSwan connections must be configured in `/etc/swanctl/conf.d/`.
-   `sudo` privileges.

## Installation

Follow these steps to install `ipsec_manager` as a system-wide command.

**1. Save the Script**

Save the script provided in the repository as `ipsec_manager.sh` in your home directory.

**2. Create the Configuration File**

The script reads VPN routes from an external file. Let's create the system-wide configuration file.

```bash
# Create the configuration directory
sudo mkdir -p /etc/ipsec_manager/

# Create and open the routes file with a text editor
sudo nano /etc/ipsec_manager/routes.conf
