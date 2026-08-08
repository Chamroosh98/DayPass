<br>

<div align="center">
  <img src="ui/ico/dp.svg" alt="DayPass Logo" width="77" height="77" style="vertical-align: middle; margin-right: 8px;">
  <h1>
    <span style="vertical-align: middle;">DayPass</span>
  </h1>
</div>

<p align="center">
  <strong>🕊️ Remembering the IRAN Massacre on Jan 8-9, 2026 (18-19 Day 1404)</strong>
</p>

---

<p align="center">
  <a href="https://github.com/Chamroosh98/DayPass/releases"><img src="https://img.shields.io/github/v/release/Chamroosh98/DayPass?style=for-the-badge&label=&color=1D63ED&logo=github&logoColor=white" alt="Release"></a>
  <a href="https://openwrt.org"><img src="https://img.shields.io/badge/POSIX_ash-4E9A06?style=for-the-badge&logo=gnu-bash&logoColor=white" alt="POSIX ash"></a>
  <a href="https://openwrt.org"><img src="https://img.shields.io/badge/OpenWrt-0066CC?style=for-the-badge&logo=openwrt&logoColor=white" alt="OpenWrt"></a>
  <a href="https://github.com/Chamroosh98/DayPass/blob/main/LICENSE"><img src="https://img.shields.io/badge/MIT-4C1D95?style=for-the-badge" alt="MIT License"></a>
</p>

---

> 💡 **Note:** The main documentation is in English. For the full Persian guide, please visit [**راهنمای پارسی 🦁☀️**](docs/i18n/README_FA.md).

---


- [🚀 What is this?](#-what-is-this)
- [**DayPass** is a lightweight, responsive terminal interface designed specifically for OpenWrt routers and embedded Linux systems. It provides real-time system diagnostics, ISP network details, DNS/latency health checking, and live speed monitoring—all wrapped in a clean, ANSI-aligned terminal UI without the bloat of heavy external dependencies.](#daypass-is-a-lightweight-responsive-terminal-interface-designed-specifically-for-openwrt-routers-and-embedded-linux-systems-it-provides-real-time-system-diagnostics-isp-network-details-dnslatency-health-checking-and-live-speed-monitoringall-wrapped-in-a-clean-ansi-aligned-terminal-ui-without-the-bloat-of-heavy-external-dependencies)
- [✨ Key Features](#-key-features)
- [⚡ Quick Start](#-quick-start)
  - [🟢 Stable version](#-stable-version)
  - [🟠 Beta version](#-beta-version)

---

## 🚀 What is this?

**DayPass** is a lightweight, responsive terminal interface designed specifically for OpenWrt routers and embedded Linux systems. It provides real-time system diagnostics, ISP network details, DNS/latency health checking, and live speed monitoring—all wrapped in a clean, ANSI-aligned terminal UI without the bloat of heavy external dependencies.
---

## ✨ Key Features

* **🖥 System Overview:** Instant view of architecture, OpenWrt release version, RAM usage, and overlay storage with visual progress bars.
* **🌐 Network Diagnostics:** Detailed public IP discovery, geolocation lookup, ISP name, and ASN identifier using fast failover APIs.
* **🔎 Health Checker:** Concurrent DNS resolution, Ping loss evaluation, and HTTPS latency testing across major edge nodes (`google.com`, `cloudflare.com`, etc.).
* **📊 Live Speed Monitor:** Real-time WAN interface bandwidth monitoring (`KB/s` / `MB/s`) with zero terminal flickering.
* **🧰 Package Manager Integration:** Interactive CLI menu to streamline custom package installations.

---

## ⚡ Quick Start

> 📌 **Note:** If `curl` is pre-installed on your system, using the `curl` command is recommended. Otherwise, use `wget`.

### 🟢 Stable version

**Using curl :**
```bash
curl -sSL https://chamroosh98.github.io/DayPass/install.sh | sh
```

**Using wget :**
``` bash
wget -qO- https://chamroosh98.github.io/DayPass/install.sh | sh
```

### 🟠 Beta version 

**Using curl :**
``` bash
curl -sL https://chamroosh98.github.io/DayPass/beta/install.sh | sh
```
**Using wget :**
```bash
wget -qO- https://chamroosh98.github.io/DayPass/beta/install.sh | sh
```
