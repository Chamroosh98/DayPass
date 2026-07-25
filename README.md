<div align="center">

# DayPass

**🕊️ Remembering the IRAN Massacre on Jan 8-9, 2026**

*A Minimalist & High-Performance Network & System Utility for OpenWrt*


[![release](https://img.shields.io/badge/release-latest-purple?style=flat-square)](https://github.com/Chamroosh98/DayPass/releases)
[![shell](https://img.shields.io/badge/shell-POSIX%20ash-blue?style=flat-square&logo=gnu-bash)](https://www.openwrt.org)
[![platform](https://img.shields.io/badge/platform-OpenWrt-darkgreen?style=flat-square&logo=openwrt)](https://openwrt.org)

---

</div>

> 💡 **Note:** The main documentation is in English. For the full Persian guide, please visit [**🦁☀️ راهنمای پارسی**](./README_Fa.md).

---


- [DayPass](#daypass)
  - [🚀 What is this?](#-what-is-this)
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
curl -sL https://chamroosh98.github.io/DayPass/dev/install.sh | sh
```
**Using wget :**
```bash
wget -qO- https://chamroosh98.github.io/DayPass/dev/install.sh | sh
```
