
<div align="center">

  <img src="../ui/ico/dp.svg" alt="DayPass Logo" width="77" height="77" style="vertical-align: middle; margin-right: 8px;">
  <h1>
    <span style="vertical-align: middle;">DayPass</span>
  </h1>

</div>

<p align="center">
  <strong>🕊️ Remembering the IRAN Massacre on Jan 8-9, 2026 ...</strong>
</p>

---

<p align="center">
  <a href="https://github.com/Chamroosh98/DayPass/releases">
    <img src="https://img.shields.io/badge/Release-181717?style=for-the-badge&logo=github&logoColor=white" alt="Release">
  </a>
  <a href="https://openwrt.org/">
    <img src="https://img.shields.io/badge/OpenWrt-00C7B7?style=for-the-badge&logo=openwrt&logoColor=white" alt="OpenWrt">
  </a>
  <a href="https://sourceforge.net/">
    <img src="https://img.shields.io/badge/SourceForge-FF6600?style=for-the-badge&logo=sourceforge&logoColor=white" alt="SourceForge">
  </a>
  <a href="https://www.gnu.org/software/bash/">
    <img src="https://img.shields.io/badge/POSIX%20Shell-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white" alt="Shell">
  </a>
  <a href="https://go.dev/">
    <img src="https://img.shields.io/badge/Go-00ADD8?style=for-the-badge&logo=go&logoColor=white" alt="Go">
  </a>
</p>

<p align="center">
  <a href="i18n/README_Fa.md"><strong>Persian</strong></a> | 
  <a href="i18n/README_Ru.md"><strong>Русский</strong></a> | 
  <a href="i18n/README_Zh.md"><strong>中文</strong></a>
</p>

---

- [🚀 What is DayPass?](#-what-is-daypass)
- [✨ Features](#-features)
- [🖥️ Hardware Compatibility](#️-hardware-compatibility)
- [🚀 Installation](#-installation)
  - [🟢 Stable Version](#-stable-version)
  - [🟠 Beta Version](#-beta-version)
- [🔀 Multi-WAN and Load Balancing](#-multi-wan-and-load-balancing)
  - [🔌 Routers with USB Ports (USB WAN Compatible)](#-routers-with-usb-ports-usb-wan-compatible)
- [🌐 Wi-Fi Management and Isolation](#-wi-fi-management-and-isolation)
- [🧼 Clean IP Management for Cloudflare](#-clean-ip-management-for-cloudflare)
  - [❓ What does it do?](#-what-does-it-do)
- [⚙️ Daily Package Updates](#️-daily-package-updates)

---

## 🚀 What is DayPass?

**DayPass** is a lightweight, automated, and modular framework for **OpenWrt** routers that simplifies network management, combining multiple internet connections (**Multi-WAN**), and load balancing across different paths.

If official OpenWrt repositories are unavailable or package downloads fail, DayPass can automatically fetch the required packages daily from **SourceForge** and prepare them for download.

DayPass works with both package managers used in recent OpenWrt versions:

- **OpenWrt 24.x** with `opkg`
- **OpenWrt 25.x** with `apk`

Packages are fetched and installed based on the OpenWrt version and the hardware architecture of the router.

---

## ✨ Features

- 📦 **Daily Package Sync**  
  Automatically downloads the latest required packages without relying on official OpenWrt repositories (which are often inaccessible in sanctioned countries).

- 🔀 **Smart Multi-WAN Management**  
  Combine and manage multiple internet connections simultaneously — from wired and fiber (`WAN`) to phone tethering, USB modems (`USB WAN`), and wireless client mode (`WWAN`) using `mwan3`.

- 📡 **Wi-Fi Isolation and Management**  
  Keeps the Access Point configuration completely separate from Client/Station mode to prevent conflicts and unexpected Wi-Fi disconnections.

- 🔄 **Automatic Internal Network Synchronization**  
  Automatically updates the internal network IP, adjusts the DHCP range, and cleans up old leases from `dhcp.leases`.

- 🌐 **Wide OpenWrt Version Compatibility**  
  Supports both OpenWrt 24.x (`opkg`) and OpenWrt 25.x (`apk`) across more than 9 hardware architectures.

---

## 🖥️ Hardware Compatibility

| CPU Architecture | Compatible Hardware & Routers |
| :--- | :--- |
| **`aarch64_cortex-a53` / `aarch64_generic`** | **Raspberry Pi:** 3B, 3B+, 4B<br>**FriendlyELEC:** NanoPi R2S, R4S, R5S<br>**GL.iNet:** Flint (GL-AX1800), Slate AX (GL-AXT1800)<br>**Xiaomi:** AX3000T, AX6000 |
| **`aarch64_cortex-a72` / `aarch64_cortex-a76`** | **Raspberry Pi:** 4B, 5<br>**SBCs:** Rockchip RK3399, RK3588 (NanoPi R6S, Orange Pi 5) |
| **`arm_cortex-a7_neon-vfpv4` / `arm_cortex-a9`** | **Linksys:** EA8300, MR8300<br>**Netgear:** R7000, R7800, R8000<br>**ASUS:** RT-AC68U, RT-AC87U<br>**GL.iNet:** B1300 (ConnextDrive) |
| **`mipsel_24kc`** | **Xiaomi:** Mi Router 3G, 4A Gigabit<br>**TP-Link:** Archer C50, C6, C7, TL-WR841N<br>**Ubiquiti:** EdgeRouter X (ER-X)<br>**GL.iNet:** Mango (GL-MT300N-V2), Shadow (GL-AR300M) |
| **`x86_64` / `i386_pentium4`** | **Mini PCs & Mini Servers:** Intel N100, N5105, J4125<br>**Industrial Hardware:** Protectli Vault, Qotom, Topton (with Intel i225/i226 ports)<br>**Virtual Machines:** VMware, Proxmox VE, KVM, VirtualBox |

---

## 🚀 Installation

DayPass is under continuous development with new features being added for various architectures. There are two versions available:

- **Stable** — Fewer features, but fully reliable.
- **Beta** — Updated almost daily with more features, but may contain bugs.

> **‼️ Note:** The Beta version is recommended only for users who have basic familiarity with this field and are able to debug issues and report them. Beginners should use the Stable version.

---

### 🟢 Stable Version

Run the following command in your router’s terminal:

```bash
wget -qO- https://chamroosh98.github.io/DayPass/install.sh | sh
```

If `curl` is already installed on your router, you can use this instead:

```bash
curl -sSL https://chamroosh98.github.io/DayPass/install.sh | sh
```

---

### 🟠 Beta Version

Install the Beta version with:

```bash
wget -qO- https://chamroosh98.github.io/DayPass/beta/install.sh | sh
```

Or :

```bash
curl -sSL https://chamroosh98.github.io/DayPass/beta/install.sh | sh
```

> ⚠️ **Reminder :** The Beta version may contain bugs. It is recommended only for experienced users or those who enjoy testing new features.

---

## 🔀 Multi-WAN and Load Balancing

DayPass allows you to set up and manage multiple internet connections on your router at the same time.

* **🌐 Wired Internet (`Ethernet WAN`)**  
  Router receives internet from an ADSL/VDSL modem or fiber optic connection via the WAN port (using a LAN cable).

> 💡 **WAN vs LAN Ports**  
> * **`WAN` port (Internet input):** The router receives internet from the main modem, fiber, or external antenna.  
> * **`LAN` port (Internet output):** The router distributes the received internet to internal devices (computers, TVs, secondary routers, or switches).

* **📱 Phone & USB Modem Internet (`USB WAN`)**  
  Connect Android phones, iPhones, or 4G/5G USB modems to the router’s USB port. DayPass supports both CDC-Ethernet and RNDIS modes.

### 🔌 Routers with USB Ports (USB WAN Compatible)

| CPU Architecture | Models with USB Ports | Number & Type of USB Ports |
| :--- | :--- | :--- |
| **`aarch64_cortex-a53`** | **Raspberry Pi:** 3B, 3B+, 4B<br>**FriendlyELEC:** NanoPi R2S, R4S, R5S<br>**GL.iNet:** Flint (GL-AX1800), Slate AX (GL-AXT1800)<br>**Xiaomi:** AX6000 | **Raspberry Pi:** 4× USB<br>**NanoPi:** 1× to 2× USB<br>**GL.iNet:** 1× USB 3.0<br>**Xiaomi:** 1× USB 3.0 |
| **`aarch64_cortex-a72/a76`** | **Raspberry Pi:** 4B, 5<br>**SBCs:** Rockchip RK3399, RK3588 (NanoPi R6S, Orange Pi 5) | **Raspberry Pi:** 2× USB 3.0 + 2× USB 2.0<br>**Orange Pi / NanoPi:** 2× to 3× USB |
| **`arm_cortex-a7_neon-vfpv4` / `arm_cortex-a9`** | **Linksys:** EA8300, MR8300<br>**Netgear:** R7000, R7800, R8000<br>**ASUS:** RT-AC68U, RT-AC87U<br>**GL.iNet:** B1300 | **Linksys:** 1× USB 3.0 / 2.0<br>**Netgear / ASUS:** 1× USB 3.0 + 1× USB 2.0<br>**GL.iNet B1300:** 1× USB 3.0 |
| **`mipsel_24kc`** | **Xiaomi:** Mi Router 3G<br>**TP-Link:** Archer C7<br>**GL.iNet:** Mango (GL-MT300N-V2), Shadow (GL-AR300M) | **Xiaomi 3G:** 1× USB 3.0<br>**Archer C7:** 2× USB 2.0<br>**GL.iNet Mango/Shadow:** 1× USB 2.0 |
| **`x86_64` / `i386`** | **Mini PCs & Mini Servers:** Intel N100, N5105, Protectli, Topton<br>**Virtual Environments:** VMware, Proxmox (via USB Passthrough) | **Most have 2 to 4 USB 3.0/2.0 ports** |

> * **`USB WAN (Tethering)`**  
>   Sharing internet from a phone or 4G/5G modem with the router via USB cable.  
> * **`RNDIS`**  
>   Microsoft standard for emulating a network adapter over USB. Commonly used on older Android phones and some USB dongles.  
> * **`CDC-Ethernet`**  
>   Open standard used by Linux/POSIX systems. Offers higher speed, lower latency, and better stability on iPhones, modern Android devices, and newer modems.

* **📡 Wireless Internet (`WWAN`)**  
  Connect to another router, modem, or hotspot and share that internet with the local network.

These connections are automatically registered in `mwan3` and provide two main capabilities:

* **Failover**  
  If one connection goes down, traffic is automatically redirected through another path.

* **Load Balancing**  
  Traffic is distributed across multiple connections so several internet paths can be used at the same time.

> **Note:** Load Balancing does **not** mean that a single download will reach the combined speed of all connections. Traffic is distributed across the available paths, and the actual performance depends on the type of connections and the `mwan3` configuration.

---

## 🌐 Wi-Fi Management and Isolation

A common issue in OpenWrt occurs when a router operates simultaneously as both an **Access Point** and a **Client**. Changing the configuration of one mode can affect the other and even cause the Wi-Fi to disconnect.

DayPass prevents this problem by keeping the two configurations completely separate:

* Managing the router’s Access Point for the home network on both 2.4 GHz and 5 GHz bands  
* Managing internet reception via Wi-Fi (`WWAN` / Client mode) without touching the Access Point settings

---

## 🧼 Clean IP Management for Cloudflare

This section is designed for configurations that sit behind a **Cloudflare Worker / CDN**. Due to heavy filtering, the original IP or domain may become unavailable.

### ❓ What does it do?

- Selects a broken or unstable configuration from the saved configs.
- Extracts the **port** directly from the share link.
- Tests a list of candidate IPs on the **same port**.
- Displays the available IPs along with their latency.
- Replaces only the **Address** field with a Clean IP.
- Leaves important parameters such as `SNI`, `Host`, and `Path` completely untouched.
- Optionally imports the updated configuration into Passwall if the user chooses to do so.

---

## ⚙️ Daily Package Updates

DayPass automatically updates all required packages every day. The process works as follows:

1. 📥 Downloads packages from **SourceForge**
2. 📦 Categorizes and prepares packages based on **9 hardware architectures and 2 versions of OpenWrt**
3. 🌐 Publishes the files on the **jsDelivr CDN**