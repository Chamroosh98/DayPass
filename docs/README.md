
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
  <a href="https://github.com/Chamroosh98/DayPass/releases"><img src="https://img.shields.io/github/v/release/Chamroosh98/DayPass?style=for-the-badge&label=&color=181717&logo=github&logoColor=white" alt="Release"></a>
  <a href="https://openwrt.org/"><img src="https://img.shields.io/badge/OpenWrt-00C7B7?style=for-the-badge&logo=openwrt&logoColor=white" alt="OpenWrt"></a>
  <a href="https://sourceforge.net/"><img src="https://img.shields.io/badge/SourceForge-FF6600?style=for-the-badge&logo=sourceforge&logoColor=white" alt="SourceForge"></a>
  <a href="https://www.gnu.org/software/bash/"><img src="https://img.shields.io/badge/POSIX%20Shell-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white" alt="Shell"></a>
  <a href="https://go.dev/"><img src="https://img.shields.io/badge/Go-00ADD8?style=for-the-badge&logo=go&logoColor=white" alt="Go"></a>
  <a href="https://t.me/Chamroosh98"><img src="https://img.shields.io/badge/Telegram-26A5E4?style=for-the-badge&logo=telegram&logoColor=white" alt="Telegram"></a>
</p>

<p align="center">
  <a href="i18n/README_Fa.md"><strong>Persian</strong></a> | 
  <a href="i18n/README_Ru.md"><strong>Русский</strong></a> | 
  <a href="i18n/README_Zh.md"><strong>中文</strong></a>
</p>

---

- [🚀 What is DayPass?](#-what-is-daypass)
- [✨ Features](#-features)
- [📋 Requirements](#-requirements)
- [📦 Dependencies](#-dependencies)
  - [Bootstrap (on the router)](#bootstrap-on-the-router)
  - [Installed automatically on first run](#installed-automatically-on-first-run)
  - [Passwall profile packages](#passwall-profile-packages)
  - [Feature-specific packages](#feature-specific-packages)
  - [CI / maintainer tools](#ci--maintainer-tools)
- [🖥️ Hardware Compatibility](#️-hardware-compatibility)
- [🚀 Installation](#-installation)
  - [🟢 Stable Version](#-stable-version)
  - [🟠 Beta Version](#-beta-version)
- [🧭 Interactive Menus](#-interactive-menus)
- [📦 Package Profiles](#-package-profiles)
- [🌐 Network Settings](#-network-settings)
  - [🔀 Multi-WAN and Load Balancing](#-multi-wan-and-load-balancing)
  - [🔌 Routers with USB Ports (USB WAN Compatible)](#-routers-with-usb-ports-usb-wan-compatible)
  - [🌐 Wi-Fi Management and Isolation](#-wi-fi-management-and-isolation)
  - [👥 Guest Network and QoS](#-guest-network-and-qos)
  - [🧭 DNS Manager](#-dns-manager)
  - [🏠 LAN IP and diagnostics](#-lan-ip-and-diagnostics)
- [🛡️ Proxy and Routing](#️-proxy-and-routing)
- [🧼 Clean IP Management for Cloudflare](#-clean-ip-management-for-cloudflare)
- [🛠️ Maintenance and Recovery](#️-maintenance-and-recovery)
- [⚙️ Daily Package Updates](#️-daily-package-updates)
- [🗂️ Project Layout](#️-project-layout)
- [💾 Data on the Router](#-data-on-the-router)

---

## 🚀 What is DayPass?

**DayPass** is a lightweight, automated, and modular toolkit built for **OpenWrt** routers. It brings network management, proxy tools, DNS control, and smart routing together in one POSIX-shell menu.

With built-in support for **Passwall / Passwall2**, **Multi-WAN**, **Guest Network**, **DNS Manager**, and **Clean IP**, it helps you stay online more reliably — even under heavy internet censorship. From selecting nodes and splitting traffic, to swapping Cloudflare IPs and applying ready-made routing profiles, DayPass covers the whole workflow.

It works with both package managers used in recent OpenWrt releases:

- **OpenWrt 24.x** (`24.10` feeds) → `opkg`
- **OpenWrt 25.x** (`25.12` feeds) → `apk`

Packages are downloaded from mirrored **SourceForge** Passwall builds (not from blocked official OpenWrt feeds) and installed according to your OpenWrt version and CPU architecture.

On the router, DayPass is a single generated `install.sh`. A Go engine in CI concatenates the shell modules, builds architecture zips, and publishes manifests to GitHub Pages / jsDelivr.

---

## ✨ Features

- 📦 **Daily package sync** — Latest Passwall-related packages for 9 architectures × 2 OpenWrt lines, served from GitHub Pages and jsDelivr.
- 🔒 **Passwall 1 and Passwall 2** — Recommended (Xray + Persian i18n) or custom engine / language / geo selection.
- 🧶 **Config manager** — Local node storage, subscriptions, enable/disable, push into Passwall.
- 🚦 **Routing / shunt** — Iran direct + foreign proxy, global proxy, or direct-only.
- ⚖️ **Node balancer and health checks** — Pick nodes, check latency, apply balancer settings to Passwall.
- 🧼 **Cloudflare Clean IP** — Probe candidate IPs on the same port and rewrite only the address field.
- 🔀 **Multi-WAN** — Ethernet WAN, USB tethering (`wan_usb`), Wi-Fi client (`wwan`), orchestrated with `mwan3` (failover + load balancing).
- 📡 **Wi-Fi isolation** — Home AP (2.4 / 5 GHz) kept separate from WWAN client mode.
- 👥 **Guest network** — Isolated interface + firewall, guest Wi-Fi, bandwidth limits (`tc` or SQM/CAKE).
- 🧭 **DNS Manager** — System DNS, Secure (DoT/DoH when available), DNS through Passwall tunnel, or hybrid fallback.
- 🏠 **LAN IP helper** — Change the router LAN address, DHCP range, and flush stale leases.
- 🖥️ **Resource view** — Architecture, OpenWrt version, RAM and overlay flash.
- 🛠️ **Maintenance** — Purge DayPass packages, clean cache, `sysupgrade` backup, factory reset (`firstboot`).

---

## 📋 Requirements

| Item | Detail |
| :--- | :--- |
| **OS** | OpenWrt **24.x** or **25.x** (other forks may work if `opkg`/`apk` and UCI exist) |
| **Shell** | POSIX `sh` (BusyBox ash on OpenWrt) |
| **Privileges** | Root on the router |
| **Network** | Working WAN so the installer can fetch `install.sh` and package zips |
| **Flash / RAM** | Enough free overlay for Passwall + Xray or Sing-box. Sing-box is heavier; avoid stacking both engines on small MIPS / low-RAM boards |
| **Bootstrap tool** | `wget` **or** `curl` already on the image (the script then installs the rest) |

You do **not** need Go, Git, or GitHub Actions on the router. Those are only for building releases.

---

## 📦 Dependencies

### Bootstrap (on the router)

Needed to start the installer:

| Tool | Role |
| :--- | :--- |
| `wget` or `curl` | Download `install.sh` and later artifacts |
| `sh` | Run the concatenated installer |
| `uci` | OpenWrt configuration (present on normal images) |

### Installed automatically on first run

`deploy_system_dependencies` fills gaps, then replaces stock `dnsmasq` with **`dnsmasq-full`**.

**All versions:**

| Package | Role |
| :--- | :--- |
| `ca-bundle` / `ca-certificates` | TLS trust store |
| `curl` | HTTPS downloads |
| `jq` | Parse manifests and stored JSON configs |
| `libnetfilter-conntrack` | Conntrack support used with `dnsmasq-full` |
| `dnsmasq-full` | DNS, DHCP, and Passwall-friendly DNS features |

**OpenWrt 24.x (`opkg`) extras:**

`coreutils`, `coreutils-base64`, `coreutils-nohup`, `coreutils-timeout`, `ip-full`, `unzip`, `resolveip`, `lua`, `libuci-lua`, `luci-compat`, `luci-lib-jsonc`, `luci-lua-runtime`, `lyaml`

OpenWrt 25.x (`apk`) uses the common set plus `dnsmasq-full`; LuCI/Lua extras are typically already on 25.x images.

### Passwall profile packages

Resolved by the installer (from DayPass manifests, not live OpenWrt feeds):

| Package | When |
| :--- | :--- |
| `luci-app-passwall` | Passwall 1 profile |
| `luci-app-passwall2` | Passwall 2 profile (default recommended) |
| `luci-i18n-passwall2-fa` / `-zh-cn` / `-ru` | Passwall 2 UI language (English needs no extra package) |
| `xray-core` | Default / recommended engine; also custom “Xray” or “both” |
| `sing-box` | Custom engine choice (higher RAM) |
| `tcping` | TCP ping / health helpers |
| `geoview` | Geo database viewer used by Passwall stacks |
| `v2ray-geoip` / `v2ray-geosite` | Official geo packages (`geoip` / `geosite` names on some apk feeds) |

**Iran geo (custom mode)** downloads `geoip.dat` / `geosite.dat` (full or lite) from [Chocolate4U/Iran-v2ray-rules](https://github.com/Chocolate4U/Iran-v2ray-rules) instead of official packages.

**Recommended profile** currently sets: Passwall 2, **Xray**, language **fa**, official geo packages.

### Feature-specific packages

Installed when you use that feature (from the router’s own feeds if the package exists):

| Feature | Packages |
| :--- | :--- |
| Multi-WAN | `mwan3` (and usually `luci-app-mwan3` if you install it yourself) |
| Guest simple QoS | `tc`, `kmod-sched` |
| Guest SQM | `sqm-scripts`; on 24.x also `luci-app-sqm` |
| USB tethering | Kernel modules already on most images (`kmod-usb-net-rndis`, `kmod-usb-net-cdc-ether`, …). Enable tethering on the phone first |
| DNS Secure (best path) | Optional: `stubby` (DoT) or `https-dns-proxy` (DoH). If missing, Passwall DoH is used; last resort is public DNS `1.1.1.1` / `8.8.8.8` |

### CI / maintainer tools

Only for people who build DayPass releases:

| Tool | Role |
| :--- | :--- |
| Go (CI `stable`, engine module `daypass-engine`) | `fetch.go` downloads feed zips; `.github/actions/engine` merges artifacts, writes `manifest.json`, generates `install.sh`, optional Telegram notify |
| `curl` on the runner | Fetch SourceForge package indexes and files |
| GitHub Actions | Matrix over OpenWrt 24/25 and 9 architectures; deploy `gh-pages`; purge jsDelivr |

Upstream package source: **SourceForge** project `openwrt-passwall-build` (`passwall_packages`, `passwall2`, `passwall_luci`).

---

## 🖥️ Hardware Compatibility

| CPU Architecture | Compatible Hardware & Routers |
| :--- | :--- |
| **`aarch64_cortex-a53` / `aarch64_generic`** | **Raspberry Pi:** 3B, 3B+, 4B<br>**FriendlyELEC:** NanoPi R2S, R4S, R5S<br>**GL.iNet:** Flint (GL-AX1800), Slate AX (GL-AXT1800)<br>**Xiaomi:** AX3000T, AX6000 |
| **`aarch64_cortex-a72` / `aarch64_cortex-a76`** | **Raspberry Pi:** 4B, 5<br>**SBCs:** Rockchip RK3399, RK3588 (NanoPi R6S, Orange Pi 5) |
| **`arm_cortex-a7_neon-vfpv4` / `arm_cortex-a9`** | **Linksys:** EA8300, MR8300<br>**Netgear:** R7000, R7800, R8000<br>**ASUS:** RT-AC68U, RT-AC87U<br>**GL.iNet:** B1300 (ConnextDrive) |
| **`mipsel_24kc`** | **Xiaomi:** Mi Router 3G, 4A Gigabit<br>**TP-Link:** Archer C50, C6, C7, TL-WR841N<br>**Ubiquiti:** EdgeRouter X (ER-X)<br>**GL.iNet:** Mango (GL-MT300N-V2), Shadow (GL-AR300M) |
| **`x86_64` / `i386_pentium4`** | **Mini PCs & Mini Servers:** Intel N100, N5105, J4125<br>**Industrial Hardware:** Protectli Vault, Qotom, Topton (with Intel i225/i226 ports)<br>**Virtual Machines:** VMware, Proxmox VE, KVM, VirtualBox |

Manifests currently ship all nine feed names: `aarch64_cortex-a53`, `aarch64_cortex-a72`, `aarch64_cortex-a76`, `aarch64_generic`, `arm_cortex-a7_neon-vfpv4`, `arm_cortex-a9_vfpv3-d16`, `mipsel_24kc`, `i386_pentium4`, `x86_64`.

---

## 🚀 Installation

DayPass is under continuous development. Two channels:

- **Stable (`main`)** — Fewer surprises; published to `https://chamroosh98.github.io/DayPass/`
- **Beta (`beta`)** — Newer menus (including DNS Manager); published to `.../DayPass/beta/`

> **‼️ Note:** Beta is for people who can recover a router and report bugs. Beginners should use Stable.

---

### 🟢 Stable Version

```bash
wget -qO- https://chamroosh98.github.io/DayPass/install.sh | sh
```

```bash
curl -sSL https://chamroosh98.github.io/DayPass/install.sh | sh
```

---

### 🟠 Beta Version

```bash
wget -qO- https://chamroosh98.github.io/DayPass/beta/install.sh | sh
```

```bash
curl -sSL https://chamroosh98.github.io/DayPass/beta/install.sh | sh
```

The script checks connectivity, detects architecture, installs core deps, optionally backups Passwall/Xray/Sing-box UCI, then opens the main menu. Re-run the same command later to return to the menu and update packages.

---

## 🧭 Interactive Menus

After `install.sh` starts:

1. **Install Package Profile** — Passwall 1 or 2, then Recommended or Custom (engine, language, geo), review, deploy.
2. **Check & Update Packages** — Compare installed versions with the CDN manifest; install/upgrade.
3. **Network Settings** — AP, guest, LAN IP, multi-WAN, info/speed, DNS Manager.
4. **Proxy & Routing Manager** — Configs, shunt, node balancer, health, profiles, Clean IP.
5. **System Resources & Hardware Info** — CPU arch, OpenWrt, RAM, flash.
6. **Maintenance & Recovery** — Purge, cache, backup, factory reset.

---

## 📦 Package Profiles

| Mode | What happens |
| :--- | :--- |
| **Recommended** | Passwall 2 + `xray-core` + official geo + Persian LuCI (`fa`) |
| **Custom** | Pick Xray / Sing-box / auto, Passwall 2 languages (fa, en, zh-cn, ru), geo skip / official / Iran full / Iran lite, extra packages from the paginated list |

Custom UI shortcuts: numbers toggle packages, `n`/`p` pages, `d` done, `q` quit. Combining Xray and Sing-box is supported on ARM64 / x86; it is discouraged on small MIPS boards.

---

## 🌐 Network Settings

### 🔀 Multi-WAN and Load Balancing

DayPass can register several uplinks and drive them with `mwan3`:

* **🌐 Wired Internet (`Ethernet WAN`)**  
  Router receives internet from an ADSL/VDSL modem or fiber via the WAN port.

> 💡 **WAN vs LAN Ports**  
> * **`WAN` port (Internet input):** The router receives internet from the main modem, fiber, or external antenna.  
> * **`LAN` port (Internet output):** The router distributes the received internet to internal devices (computers, TVs, secondary routers, or switches).

* **📱 Phone & USB Modem Internet (`USB WAN`)**  
  Connect Android phones, iPhones, or 4G/5G USB modems. Interface name `wan_usb` (CDC-Ethernet or RNDIS). Enable USB tethering on the phone before setup.

### 🔌 Routers with USB Ports (USB WAN Compatible)

| CPU Architecture | Models with USB Ports | Number & Type of USB Ports |
| :--- | :--- | :--- |
| **`aarch64_cortex-a53`** | **Raspberry Pi:** 3B, 3B+, 4B<br>**FriendlyELEC:** NanoPi R2S, R4S, R5S<br>**GL.iNet:** Flint (GL-AX1800), Slate AX (GL-AXT1800)<br>**Xiaomi:** AX6000 | **Raspberry Pi:** 4× USB<br>**NanoPi:** 1× to 2× USB<br>**GL.iNet:** 1× USB 3.0<br>**Xiaomi:** 1× USB 3.0 |
| **`aarch64_cortex-a72/a76`** | **Raspberry Pi:** 4B, 5<br>**SBCs:** Rockchip RK3399, RK3588 (NanoPi R6S, Orange Pi 5) | **Raspberry Pi:** 2× USB 3.0 + 2× USB 2.0<br>**Orange Pi / NanoPi:** 2× to 3× USB |
| **`arm_cortex-a7_neon-vfpv4` / `arm_cortex-a9`** | **Linksys:** EA8300, MR8300<br>**Netgear:** R7000, R7800, R8000<br>**ASUS:** RT-AC68U, RT-AC87U<br>**GL.iNet:** B1300 | **Linksys:** 1× USB 3.0 / 2.0<br>**Netgear / ASUS:** 1× USB 3.0 + 1× USB 2.0<br>**GL.iNet B1300:** 1× USB 3.0 |
| **`mipsel_24kc`** | **Xiaomi:** Mi Router 3G<br>**TP-Link:** Archer C7<br>**GL.iNet:** Mango (GL-MT300N-V2), Shadow (GL-AR300M) | **Xiaomi 3G:** 1× USB 3.0<br>**Archer C7:** 2× USB 2.0<br>**GL.iNet Mango/Shadow:** 1× USB 2.0 |
| **`x86_64` / `i386`** | **Mini PCs & Mini Servers:** Intel N100, N5105, Protectli, Topton<br>**Virtual Environments:** VMware, Proxmox (via USB Passthrough) | **Most have 2 to 4 USB 3.0/2.0 ports** |

> * **`USB WAN (Tethering)`** — Share phone or modem internet over USB.  
> * **`RNDIS`** — Microsoft USB-NIC emulation (older Android, some dongles).  
> * **`CDC-Ethernet`** — Linux/POSIX USB ethernet (iPhone, modern Android, many modems).

* **📡 Wireless Internet (`WWAN`)**  
  Station/client mode to another AP; interface `wwan`, kept separate from the home AP.

`mwan3` members: `wan` (metric 1), `wan_usb` (2), `wwan` (3). Policies: **balanced** (default IPv4 rule) and **failover**.

> **Note:** Load balancing does **not** bond a single TCP download to the sum of all links. Flows are spread across paths.

---

### 🌐 Wi-Fi Management and Isolation

A common OpenWrt issue is running **Access Point** and **Client** on the same radio and overwriting one config with the other.

DayPass keeps them apart:

* Home AP on 2.4 GHz and 5 GHz  
* WWAN / client receive path without rewriting AP SSIDs

---

### 👥 Guest Network and QoS

- Create a guest interface and firewall zone isolated from LAN  
- Optional guest SSID  
- Bandwidth: simple `tc` HTB, or SQM (`cake` / `piece_of_cake.qos`)  
- Remove guest network when you no longer need it  

---

### 🧭 DNS Manager

Persistent router DNS (not the temporary “fix DNS so `opkg` works” recovery in Network Checker).

| Mode | Behavior |
| :--- | :--- |
| **System** | dnsmasq uses WAN/ISP resolvers; Passwall DNS hijack off (proxy can stay enabled) |
| **Secure** | Prefer Stubby DoT → `https-dns-proxy` DoH → Passwall DoH (Cloudflare). If none exist, plaintext `1.1.1.1` / `8.8.8.8` |
| **Tunnel** | Requires Passwall. dnsmasq forwards to Passwall’s local DNS port; `dns_redirect` on; remote DNS over TCP through the proxy |
| **Hybrid** | Passwall/DoH first, then Cloudflare and Google in **strict order** as fallback |

State is stored in `/etc/daypass/dns/mode`.

---

### 🏠 LAN IP and diagnostics

- Change LAN IPv4, align DHCP, clear `/tmp/dhcp.leases`  
- Network info / speed helpers  
- DNS recovery (`1.1.1.1`, `8.8.8.8`, `9.9.9.9`) writes a temporary `/etc/resolv.conf` for package installs — separate from DNS Manager  

---

## 🛡️ Proxy and Routing

| Tool | Role |
| :--- | :--- |
| **Config Manager** | List / add share links, subscriptions, toggle, push one or all nodes into Passwall |
| **Traffic routing** | Iran direct + foreign proxy (`gfwlist`/`proxy`), global proxy, direct-only (disable Passwall) |
| **Node load balancing** | Select stored nodes and apply balancer mode to Passwall |
| **Health checker** | Reachability and approximate latency of stored hosts/ports (`tcping` when present) |
| **Routing profiles** | Balanced, Gaming, Streaming (Iran-direct base), Global Proxy, Direct Only |

Configs live under `/etc/daypass/proxy/` (JSON configs, subscriptions, balancer, health, routing, Clean IP candidates).

---

## 🧼 Clean IP Management for Cloudflare

For configs behind a **Cloudflare Worker / CDN** when the original IP or domain is blocked.

### ❓ What does it do?

- Selects a broken or unstable configuration from the saved configs.
- Extracts the **port** directly from the share link.
- Tests a list of candidate IPs on the **same port**.
- Displays the available IPs along with their latency.
- Replaces only the **Address** field with a Clean IP.
- Leaves important parameters such as `SNI`, `Host`, and `Path` completely untouched.
- Optionally imports the updated configuration into Passwall if the user chooses to do so.

---

## 🛠️ Maintenance and Recovery

- **Purge** packages recorded in `/etc/daypass/install.log`  
- **Clean cache** of `.ipk` / `.apk` / `.part` under `/etc/daypass`  
- **Backup** via `sysupgrade -b`  
- **Factory reset** via `firstboot -y` (type `RESET` to confirm)  

Startup also tries to archive existing `/etc/config/passwall`, `passwall2`, `xray`, `sing-box`, `niki` under `/tmp/daypass/backups`.

---

## ⚙️ Daily Package Updates

DayPass CI refreshes architecture zips and manifests (release: daily cron + pushes to `main`; beta: pushes to `beta`).

1. 📥 Download Passwall feeds from **SourceForge** (`openwrt-passwall-build`) per arch  
2. 📦 Build zips and `manifest.json` for **9 architectures** and **OpenWrt 24 + 25**  
3. 🌐 Publish `install.sh`, zips, and SHA-256 sums to **GitHub Pages**, then purge **jsDelivr**

On the router, **Check & Update Packages** compares installed versions/hashes with the manifest and installs only what changed.

---

## 🗂️ Project Layout

```
DayPass/
├── config/                  # architectures_24.json, architectures_25.json, providers, settings
├── docs/                    # This README + i18n
├── installer/               # Arch detect, zero-deps, opkg/apk, resolver, install, updater
├── modules/
│   ├── network/host/        # WAN, AP, WWAN, USB, LAN IP, mwan3, dns_fix, checker
│   ├── network/guest/       # Guest net + QoS
│   ├── network/dns/         # DNS Manager
│   ├── proxy/               # Configs, routing, balancer, health, profiles, Cloudflare
│   ├── system/              # Resources, backup, maintenance, version check
│   └── service/             # Service reload helpers
├── ui/                      # Menus, banner, styles
└── .github/actions/         # Go fetch + engine that emits install.sh
```

---

## 💾 Data on the Router

| Path | Purpose |
| :--- | :--- |
| `/etc/daypass/` | Root state, install log, downloaded packages |
| `/etc/daypass/dns/` | Selected DNS mode |
| `/etc/daypass/proxy/` | Nodes, subscriptions, routing, balancer, Clean IP |
| `/tmp/daypass/` | Transaction log, config backups |
