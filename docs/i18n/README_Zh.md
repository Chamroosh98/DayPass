
<div align="center">
  <img src="../../ui/ico/dp.svg" alt="DayPass Logo" width="77" height="77" style="vertical-align: middle; margin-right: 8px;">
  <h1>
    <span style="vertical-align: middle;">DayPass</span>
  </h1>
</div>

<p align="center">
  <strong>🕊️ 纪念 2026 年 1 月 8–9 日伊朗大屠杀 ...</strong>
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
  <a href="../README.md"><strong>English</strong></a>
</p>

---

- [🚀 什么是 DayPass？](#-什么是-daypass)
- [✨ 功能特点](#-功能特点)
- [🖥️ 硬件兼容性](#️-硬件兼容性)
- [🚀 安装](#-安装)
  - [🟢 稳定版](#-稳定版)
  - [🟠 测试版](#-测试版)
- [🔀 Multi-WAN 与负载均衡](#-multi-wan-与负载均衡)
  - [🔌 带 USB 接口的路由器（支持 USB WAN）](#-带-usb-接口的路由器支持-usb-wan)
- [🌐 Wi-Fi 管理与隔离](#-wi-fi-管理与隔离)
- [🧼 Cloudflare Clean IP 管理](#-cloudflare-clean-ip-管理)
  - [❓ 它能做什么？](#-它能做什么)
- [⚙️ 每日软件包更新](#️-每日软件包更新)

---

## 🚀 什么是 DayPass？

**DayPass** 是一款轻量、自动化、模块化的工具，专为 **OpenWrt** 路由器打造。它把网络管理、代理和智能路由整合在一起，让一切变得简单高效。

内置支持 **Passwall**、**Multi-WAN**、**Guest Network** 和 **Clean IP**，即使在严格的网络审查环境下，也能帮你保持更稳定、更智能的网络访问。从优选节点、流量分流，到替换 Cloudflare IP、使用现成的路由配置文件，DayPass 几乎覆盖了完整工作流。

它完美兼容新版 OpenWrt 的两种包管理器：

- **OpenWrt 24.x** → `opkg`
- **OpenWrt 25.x** → `apk`

软件包会根据你的 OpenWrt 版本和路由器硬件架构自动下载并安装。

---

## ✨ 功能特点

- 📦 **每日软件包同步（Daily Sync）**  
  自动下载所需软件包的更新，无需依赖官方 OpenWrt 软件源（在受制裁国家通常无法访问）。

- 🔀 **智能 Multi-WAN 管理**  
  可同时组合和管理多条互联网连接：包括有线/光纤（`WAN`）、手机共享和 USB 调制解调器（`USB WAN`），以及 Wi-Fi 客户端模式（`WWAN`），基于 `mwan3` 实现。

- 📡 **Wi-Fi 隔离与管理**  
  将路由器的接入点（Access Point）配置与客户端（Client/Station）模式完全分离，避免两者互相干扰，防止 Wi-Fi 意外断开。

- 🔄 **自动同步内部网络**  
  自动修改内部网络 IP、调整 DHCP 地址范围，并清理 `dhcp.leases` 文件中的旧租约记录。

- 🌐 **广泛的 OpenWrt 版本兼容性**  
  支持 OpenWrt 24.x（`opkg`）和 OpenWrt 25.x（`apk`），覆盖超过 9 种硬件架构。

---

## 🖥️ 硬件兼容性

| 处理器架构 | 兼容硬件与路由器示例 |
| :--- | :--- |
| **`aarch64_cortex-a53` / `aarch64_generic`** | **Raspberry Pi：** 3B、3B+、4B<br>**FriendlyELEC：** NanoPi R2S、R4S、R5S<br>**GL.iNet：** Flint（GL-AX1800）、Slate AX（GL-AXT1800）<br>**Xiaomi：** AX3000T、AX6000 |
| **`aarch64_cortex-a72` / `aarch64_cortex-a76`** | **Raspberry Pi：** 4B、5<br>**SBC：** Rockchip RK3399、RK3588（NanoPi R6S、Orange Pi 5） |
| **`arm_cortex-a7_neon-vfpv4` / `arm_cortex-a9`** | **Linksys：** EA8300、MR8300<br>**Netgear：** R7000、R7800、R8000<br>**ASUS：** RT-AC68U、RT-AC87U<br>**GL.iNet：** B1300（ConnextDrive） |
| **`mipsel_24kc`** | **Xiaomi：** Mi Router 3G、4A Gigabit<br>**TP-Link：** Archer C50、C6、C7、TL-WR841N<br>**Ubiquiti：** EdgeRouter X（ER-X）<br>**GL.iNet：** Mango（GL-MT300N-V2）、Shadow（GL-AR300M） |
| **`x86_64` / `i386_pentium4`** | **迷你电脑与迷你服务器：** Intel N100、N5105、J4125<br>**工业硬件：** Protectli Vault、Qotom、Topton（配备 Intel i225/i226 网口）<br>**虚拟机：** VMware、Proxmox VE、KVM、VirtualBox |

---

## 🚀 安装

DayPass 仍在持续开发中，不断为不同架构添加新功能。因此提供两个版本：

- **稳定版** —— 功能较少，但非常稳定可靠。
- **测试版** —— 几乎每天更新，功能更多，但可能存在 bug。

> **‼️ 注意：** 测试版仅推荐给具备基本相关知识、能够自行调试并提交反馈的用户。新手建议使用稳定版。

---

### 🟢 稳定版

在路由器终端中执行以下命令：

```bash
wget -qO- https://chamroosh98.github.io/DayPass/install.sh | sh
```

如果路由器上已经安装了 `curl`，可以使用以下命令：

```bash
curl -sSL https://chamroosh98.github.io/DayPass/install.sh | sh
```

---

### 🟠 测试版

安装测试版：

```bash
wget -qO- https://chamroosh98.github.io/DayPass/beta/install.sh | sh
```

或：

```bash
curl -sSL https://chamroosh98.github.io/DayPass/beta/install.sh | sh
```

> ⚠️ **提醒：** 测试版可能存在 bug，因此仅推荐给有经验的用户或喜欢尝鲜的朋友。

---

## 🔀 Multi-WAN 与负载均衡

使用 DayPass，你可以在路由器上同时配置和管理多条互联网连接。

* **🌐 有线互联网（`Ethernet WAN`）**  
  通过 WAN 口（使用网线）从 ADSL/VDSL 调制解调器或光纤获取互联网。

> 💡 **WAN 与 LAN 端口的区别**  
> * **`WAN` 口（互联网入口）：** 路由器从主调制解调器、光纤或外部天线接收互联网。  
> * **`LAN` 口（互联网出口）：** 路由器将接收到的互联网分配给内部设备（电脑、电视、二级路由器或交换机）。

* **📱 手机与 USB 调制解调器互联网（`USB WAN`）**  
  将 Android 手机、iPhone 或 4G/5G USB 调制解调器连接到路由器的 USB 接口。DayPass 支持 CDC-Ethernet 和 RNDIS 模式。

### 🔌 带 USB 接口的路由器（支持 USB WAN）

| 处理器架构 | 带 USB 接口的型号 | USB 接口数量与类型 |
| :--- | :--- | :--- |
| **`aarch64_cortex-a53`** | **Raspberry Pi：** 3B、3B+、4B<br>**FriendlyELEC：** NanoPi R2S、R4S、R5S<br>**GL.iNet：** Flint（GL-AX1800）、Slate AX（GL-AXT1800）<br>**Xiaomi：** AX6000 | **Raspberry Pi：** 4× USB<br>**NanoPi：** 1–2× USB<br>**GL.iNet：** 1× USB 3.0<br>**Xiaomi：** 1× USB 3.0 |
| **`aarch64_cortex-a72/a76`** | **Raspberry Pi：** 4B、5<br>**SBC：** Rockchip RK3399、RK3588（NanoPi R6S、Orange Pi 5） | **Raspberry Pi：** 2× USB 3.0 + 2× USB 2.0<br>**Orange Pi / NanoPi：** 2–3× USB |
| **`arm_cortex-a7_neon-vfpv4` / `arm_cortex-a9`** | **Linksys：** EA8300、MR8300<br>**Netgear：** R7000、R7800、R8000<br>**ASUS：** RT-AC68U、RT-AC87U<br>**GL.iNet：** B1300 | **Linksys：** 1× USB 3.0 / 2.0<br>**Netgear / ASUS：** 1× USB 3.0 + 1× USB 2.0<br>**GL.iNet B1300：** 1× USB 3.0 |
| **`mipsel_24kc`** | **Xiaomi：** Mi Router 3G<br>**TP-Link：** Archer C7<br>**GL.iNet：** Mango（GL-MT300N-V2）、Shadow（GL-AR300M） | **Xiaomi 3G：** 1× USB 3.0<br>**Archer C7：** 2× USB 2.0<br>**GL.iNet Mango/Shadow：** 1× USB 2.0 |
| **`x86_64` / `i386`** | **迷你电脑与迷你服务器：** Intel N100、N5105、Protectli、Topton<br>**虚拟环境：** VMware、Proxmox（通过 USB 直通） | **大多数具备 2 到 4 个 USB 3.0/2.0 接口** |

> * **`USB WAN (Tethering)`**  
>   通过 USB 线将手机或 4G/5G 调制解调器的互联网共享给路由器的统称。  
> * **`RNDIS`**  
>   微软制定的通过 USB 模拟网卡的标准，多用于较旧的 Android 手机和部分 USB 网卡。  
> * **`CDC-Ethernet`**  
>   Linux/POSIX 的开放标准，速度更高、延迟更低、稳定性更好，适用于 iPhone、新款 Android 设备以及现代调制解调器。

* **📡 无线互联网（`WWAN`）**  
  从其他路由器、调制解调器或热点获取互联网，并分享给本地网络。

这些连接会自动注册到 `mwan3` 中，并提供两项主要功能：

* **Failover（故障转移）**  
  当其中一条连接中断时，流量会自动切换到其他可用路径。

* **Load Balancing（负载均衡）**  
  流量在多条连接之间分配，从而同时使用多条互联网路径。

> **注意：** 负载均衡**并不意味着**单个下载任务的速度会等于所有连接速度的总和。流量会在可用路径之间分配，实际效果取决于连接类型和 `mwan3` 的配置。

---

## 🌐 Wi-Fi 管理与隔离

在 OpenWrt 中，当路由器同时作为**接入点（Access Point）**和**客户端（Client）**运行时，经常会出现问题。修改其中一个模式的配置可能会影响另一个模式，甚至导致 Wi-Fi 断开。

DayPass 通过完全分离这两种配置来解决此问题：

* 管理路由器作为家庭网络接入点（2.4 GHz 和 5 GHz）的配置  
* 管理通过 Wi-Fi 接收互联网（`WWAN` / 客户端模式）的配置，且不影响接入点设置

---

## 🧼 Cloudflare Clean IP 管理

本功能专为位于 **Cloudflare Worker / CDN** 后面的配置设计。由于严格的网络过滤，原始 IP 或域名可能会失效。

### ❓ 它能做什么？

- 从已保存的配置中选择一个损坏或不稳定的配置。
- 直接从分享链接中提取 **端口**。
- 在 **相同端口** 上测试候选 IP 列表。
- 显示可用的 IP 及其延迟。
- 仅替换配置中的 **Address** 字段为 Clean IP。
- 完整保留 `SNI`、`Host`、`Path` 等重要参数。
- 如果用户需要，可以将更新后的配置导入到 Passwall。

---
## ⚙️ 每日软件包更新

DayPass 每天自动更新所有需要的软件包。流程如下：

1. 📥 从 **SourceForge** 下载软件包  
2. 📦 根据 **9 种硬件架构和 2 个 OpenWrt 版本** 进行分类和准备  
3. 🌐 将文件发布到 **jsDelivr CDN**
