
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
  <a href="../README.md"><strong>English</strong></a> |
  <a href="README_Fa.md"><strong>Persian</strong></a> |
  <a href="README_Ru.md"><strong>Русский</strong></a>
</p>

---

- [🚀 什么是 DayPass？](#-什么是-daypass)
- [✨ 功能特点](#-功能特点)
- [📋 运行要求](#-运行要求)
- [📦 依赖](#-依赖)
  - [路由器上的启动条件](#路由器上的启动条件)
  - [首次运行自动安装](#首次运行自动安装)
  - [Passwall 配置文件相关包](#passwall-配置文件相关包)
  - [按功能安装的包](#按功能安装的包)
  - [CI / 维护者工具](#ci--维护者工具)
- [🖥️ 硬件兼容性](#️-硬件兼容性)
- [🚀 安装](#-安装)
  - [🟢 稳定版](#-稳定版)
  - [🟠 测试版](#-测试版)
- [🧭 交互菜单](#-交互菜单)
- [📦 软件包配置](#-软件包配置)
- [🌐 网络设置](#-网络设置)
  - [🔀 Multi-WAN 与负载均衡](#-multi-wan-与负载均衡)
  - [🔌 带 USB 的路由器](#-带-usb-的路由器)
  - [🌐 Wi-Fi 管理与隔离](#-wi-fi-管理与隔离)
  - [👥 访客网络与 QoS](#-访客网络与-qos)
  - [🧭 DNS 管理器](#-dns-管理器)
  - [🏠 LAN IP 与诊断](#-lan-ip-与诊断)
- [🛡️ 代理与路由](#️-代理与路由)
- [🧼 Cloudflare Clean IP](#-cloudflare-clean-ip)
- [🛠️ 维护与恢复](#️-维护与恢复)
- [⚙️ 每日软件包更新](#️-每日软件包更新)
- [🗂️ 项目结构](#️-项目结构)
- [💾 路由器上的数据](#-路由器上的数据)

---

## 🚀 什么是 DayPass？

**DayPass** 是面向 **OpenWrt** 路由器的轻量模块化工具：把网络管理、代理、DNS 和智能路由放进同一个 POSIX Shell 菜单。

内置 **Passwall / Passwall2**、**Multi-WAN**、**访客网络**、**DNS 管理器** 和 **Clean IP**，即使在严格审查下也能更稳定地访问网络：选节点、分流、替换 Cloudflare IP、套用现成路由配置。

兼容两种包管理器：

- **OpenWrt 24.x**（`24.10` 源）→ `opkg`
- **OpenWrt 25.x**（`25.12` 源）→ `apk`

软件包来自 SourceForge 上的 Passwall 构建（而不是经常无法访问的官方 OpenWrt 源），并按 OpenWrt 版本和 CPU 架构安装。

路由器上运行的是生成后的单一 `install.sh`。CI 里的 Go 引擎拼接 shell 模块、按架构打包 zip，并把清单发布到 GitHub Pages / jsDelivr。

---

## ✨ 功能特点

- 📦 每日同步 Passwall 相关包：9 种架构 × 两条 OpenWrt 线。
- 🔒 Passwall 1 / 2：推荐配置（Xray + 波斯语）或自定义引擎 / 语言 / Geo。
- 🧶 配置管理：节点、订阅、推送到 Passwall。
- 🚦 分流：伊朗直连 + 境外代理、全局代理、仅直连。
- ⚖️ 节点负载均衡与健康检查。
- 🧼 Cloudflare Clean IP。
- 🔀 Multi-WAN：有线 WAN、USB 共享（`wan_usb`）、Wi-Fi 客户端（`wwan`），由 `mwan3` 调度。
- 📡 家庭 AP 与 WWAN 隔离。
- 👥 访客网络与限速（`tc` 或 SQM/CAKE）。
- 🧭 DNS：系统、安全（DoT/DoH）、Passwall 隧道、混合。
- 🏠 修改 LAN IP、DHCP、清理租约。
- 🖥️ 硬件与资源信息。
- 🛠️ 卸载 DayPass 包、清缓存、`sysupgrade` 备份、恢复出厂。

---

## 📋 运行要求

| 项目 | 说明 |
| :--- | :--- |
| **系统** | OpenWrt **24.x** 或 **25.x** |
| **Shell** | POSIX `sh`（BusyBox ash） |
| **权限** | 路由器 root |
| **网络** | 可用 WAN，用于下载脚本和 zip |
| **存储/内存** | overlay 需能放下 Passwall + Xray 或 Sing-box。Sing-box 更吃内存；弱 MIPS 不要同时装两个引擎 |
| **启动工具** | 固件里已有 `wget` **或** `curl` |

路由器上不需要 Go、Git 或 GitHub Actions。

---

## 📦 依赖

### 路由器上的启动条件

`wget` 或 `curl`、`sh`、`uci`。

### 首次运行自动安装

补齐缺失依赖，并把普通 `dnsmasq` 换成 **`dnsmasq-full`**。

**所有版本：** `ca-bundle`、`ca-certificates`、`curl`、`jq`、`libnetfilter-conntrack`、`dnsmasq-full`

**OpenWrt 24.x（`opkg`）额外：** `coreutils`、`coreutils-base64`、`coreutils-nohup`、`coreutils-timeout`、`ip-full`、`unzip`、`resolveip`、`lua`、`libuci-lua`、`luci-compat`、`luci-lib-jsonc`、`luci-lua-runtime`、`lyaml`

### Passwall 配置文件相关包

| 软件包 | 时机 |
| :--- | :--- |
| `luci-app-passwall` | Passwall 1 |
| `luci-app-passwall2` | Passwall 2（推荐） |
| `luci-i18n-passwall2-fa` / `-zh-cn` / `-ru` | Passwall 2 界面语言 |
| `xray-core` | 默认 / 推荐引擎 |
| `sing-box` | 自定义（更占内存） |
| `tcping`、`geoview` | 探测 / Geo 查看 |
| `v2ray-geoip` / `v2ray-geosite` | 官方 Geo（部分 apk 源名为 `geoip` / `geosite`） |

自定义模式下的伊朗规则集来自 [Chocolate4U/Iran-v2ray-rules](https://github.com/Chocolate4U/Iran-v2ray-rules)。

**推荐配置：** Passwall 2 + Xray + 语言 **fa** + 官方 Geo。

### 按功能安装的包

| 功能 | 软件包 |
| :--- | :--- |
| Multi-WAN | `mwan3`（可选 `luci-app-mwan3`） |
| 访客简易 QoS | `tc`、`kmod-sched` |
| SQM | `sqm-scripts`；24.x 通常还有 `luci-app-sqm` |
| USB 共享 | 内核模块（`kmod-usb-net-rndis`、`kmod-usb-net-cdc-ether` 等） |
| 安全 DNS | 可选 `stubby` 或 `https-dns-proxy`；否则用 Passwall DoH；最后才是 `1.1.1.1` / `8.8.8.8` |

### CI / 维护者工具

Go（`fetch.go` 与引擎）、运行器上的 `curl`、GitHub Actions（24/25 × 9 架构、`gh-pages`、jsDelivr 刷新）。上游：SourceForge `openwrt-passwall-build`。

---

## 🖥️ 硬件兼容性

| 处理器架构 | 兼容硬件与路由器示例 |
| :--- | :--- |
| **`aarch64_cortex-a53` / `aarch64_generic`** | **Raspberry Pi：** 3B、3B+、4B<br>**FriendlyELEC：** NanoPi R2S、R4S、R5S<br>**GL.iNet：** Flint（GL-AX1800）、Slate AX（GL-AXT1800）<br>**Xiaomi：** AX3000T、AX6000 |
| **`aarch64_cortex-a72` / `aarch64_cortex-a76`** | **Raspberry Pi：** 4B、5<br>**SBC：** Rockchip RK3399、RK3588（NanoPi R6S、Orange Pi 5） |
| **`arm_cortex-a7_neon-vfpv4` / `arm_cortex-a9`** | **Linksys：** EA8300、MR8300<br>**Netgear：** R7000、R7800、R8000<br>**ASUS：** RT-AC68U、RT-AC87U<br>**GL.iNet：** B1300（ConnextDrive） |
| **`mipsel_24kc`** | **Xiaomi：** Mi Router 3G、4A Gigabit<br>**TP-Link：** Archer C50、C6、C7、TL-WR841N<br>**Ubiquiti：** EdgeRouter X（ER-X）<br>**GL.iNet：** Mango（GL-MT300N-V2）、Shadow（GL-AR300M） |
| **`x86_64` / `i386_pentium4`** | **迷你电脑与迷你服务器：** Intel N100、N5105、J4125<br>**工业硬件：** Protectli Vault、Qotom、Topton（配备 Intel i225/i226 网口）<br>**虚拟机：** VMware、Proxmox VE、KVM、VirtualBox |

清单中的九个架构名：`aarch64_cortex-a53`、`aarch64_cortex-a72`、`aarch64_cortex-a76`、`aarch64_generic`、`arm_cortex-a7_neon-vfpv4`、`arm_cortex-a9_vfpv3-d16`、`mipsel_24kc`、`i386_pentium4`、`x86_64`。

---

## 🚀 安装

- **稳定版（`main`）** — `https://chamroosh98.github.io/DayPass/`
- **测试版（`beta`）** — 含较新菜单（含 DNS 管理器）— `.../DayPass/beta/`

> **‼️ 注意：** 测试版适合能自行救砖并反馈问题的用户。

### 🟢 稳定版

```bash
wget -qO- https://chamroosh98.github.io/DayPass/install.sh | sh
```

```bash
curl -sSL https://chamroosh98.github.io/DayPass/install.sh | sh
```

### 🟠 测试版

```bash
wget -qO- https://chamroosh98.github.io/DayPass/beta/install.sh | sh
```

```bash
curl -sSL https://chamroosh98.github.io/DayPass/beta/install.sh | sh
```

脚本会检查网络、识别架构、安装核心依赖、尽量备份 Passwall/Xray/Sing-box 的 UCI，然后进入主菜单。再次执行同一命令可回到菜单并更新软件包。

---

## 🧭 交互菜单

1. 安装软件包配置  
2. 检查并更新软件包  
3. 网络设置（AP、访客、LAN、Multi-WAN、DNS）  
4. 代理与路由  
5. 系统资源  
6. 维护与恢复  

---

## 📦 软件包配置

| 模式 | 内容 |
| :--- | :--- |
| **推荐** | Passwall 2 + `xray-core` + 官方 Geo + LuCI **fa** |
| **自定义** | Xray / Sing-box / 自动，Passwall 2 语言，跳过 / 官方 / 伊朗完整 / 精简 Geo |

自定义快捷键：数字开关包、`n`/`p` 翻页、`d` 完成、`q` 退出。ARM64 / x86 可同时装 Xray 与 Sing-box；弱 MIPS 不建议。

---

## 🌐 网络设置

### 🔀 Multi-WAN 与负载均衡

* **🌐 有线 WAN** — 从调制解调器/光纤接入 WAN 口。  
* **📱 USB WAN** — 接口 `wan_usb`（CDC-Ethernet / RNDIS）。请先在手机上打开 USB 共享。  
* **📡 WWAN** — 作为客户端接入其他热点，接口 `wwan`。

> **WAN** 是互联网入口，**LAN** 是向内部分发。

`mwan3` 成员：`wan`（metric 1）、`wan_usb`（2）、`wwan`（3）。策略：**balanced** 与 **failover**。负载均衡**不会**把单条 TCP 下载叠成所有链路之和。

### 🔌 带 USB 的路由器

| 处理器架构 | 带 USB 接口的型号 | USB 接口数量与类型 |
| :--- | :--- | :--- |
| **`aarch64_cortex-a53`** | **Raspberry Pi：** 3B、3B+、4B<br>**FriendlyELEC：** NanoPi R2S、R4S、R5S<br>**GL.iNet：** Flint（GL-AX1800）、Slate AX（GL-AXT1800）<br>**Xiaomi：** AX6000 | **Raspberry Pi：** 4× USB<br>**NanoPi：** 1–2× USB<br>**GL.iNet：** 1× USB 3.0<br>**Xiaomi：** 1× USB 3.0 |
| **`aarch64_cortex-a72/a76`** | **Raspberry Pi：** 4B、5<br>**SBC：** Rockchip RK3399、RK3588（NanoPi R6S、Orange Pi 5） | **Raspberry Pi：** 2× USB 3.0 + 2× USB 2.0<br>**Orange Pi / NanoPi：** 2–3× USB |
| **`arm_cortex-a7_neon-vfpv4` / `arm_cortex-a9`** | **Linksys：** EA8300、MR8300<br>**Netgear：** R7000、R7800、R8000<br>**ASUS：** RT-AC68U、RT-AC87U<br>**GL.iNet：** B1300 | **Linksys：** 1× USB 3.0 / 2.0<br>**Netgear / ASUS：** 1× USB 3.0 + 1× USB 2.0<br>**GL.iNet B1300：** 1× USB 3.0 |
| **`mipsel_24kc`** | **Xiaomi：** Mi Router 3G<br>**TP-Link：** Archer C7<br>**GL.iNet：** Mango（GL-MT300N-V2）、Shadow（GL-AR300M） | **Xiaomi 3G：** 1× USB 3.0<br>**Archer C7：** 2× USB 2.0<br>**GL.iNet Mango/Shadow：** 1× USB 2.0 |
| **`x86_64` / `i386`** | **迷你电脑与迷你服务器：** Intel N100、N5105、Protectli、Topton<br>**虚拟环境：** VMware、Proxmox（通过 USB 直通） | **大多数具备 2 到 4 个 USB 3.0/2.0 接口** |

### 🌐 Wi-Fi 管理与隔离

2.4 / 5 GHz 家庭 AP 与 WWAN 客户端配置分开，避免互相覆盖。

### 👥 访客网络与 QoS

独立接口与防火墙、可选访客 SSID、`tc` 或 SQM（`cake` / `piece_of_cake.qos`）限速。

### 🧭 DNS 管理器

路由器持久 DNS（不是 Network Checker 里给 `opkg` 用的临时修复）。

| 模式 | 行为 |
| :--- | :--- |
| **系统** | 使用运营商 DNS；关闭 Passwall DNS 劫持 |
| **安全** | Stubby → https-dns-proxy → Passwall DoH → 公共 DNS |
| **隧道** | 需要 Passwall；dnsmasq 转发到 Passwall 本地 DNS 端口 |
| **混合** | 先 Passwall/DoH，再按严格顺序回落到 Cloudflare / Google |

状态文件：`/etc/daypass/dns/mode`。

### 🏠 LAN IP 与诊断

修改 LAN、DHCP、清理 `/tmp/dhcp.leases`。临时 DNS 恢复（`1.1.1.1` / `8.8.8.8` / `9.9.9.9`）与 DNS 管理器分开。

---

## 🛡️ 代理与路由

配置管理、分流、节点均衡、健康检查（有则用 `tcping`）、配置文件：均衡 / 游戏 / 流媒体 / 全局 / 仅直连。数据目录：`/etc/daypass/proxy/`。

---

## 🧼 Cloudflare Clean IP

针对位于 Worker/CDN 后的配置：从分享链接取端口、在同端口探测候选 IP、只改 **Address**、保留 `SNI` / `Host` / `Path`，可选择导入 Passwall。

---

## 🛠️ 维护与恢复

按 `/etc/daypass/install.log` 卸载、清理 `.ipk`/`.apk`、`sysupgrade -b` 备份、`firstboot -y`（需输入 `RESET`）。启动时 UCI 备份在 `/tmp/daypass/backups`。

---

## ⚙️ 每日软件包更新

1. 从 SourceForge `openwrt-passwall-build` 下载  
2. 为 9 种架构和 OpenWrt 24+25 生成 zip 与 `manifest.json`  
3. 发布到 GitHub Pages 并刷新 jsDelivr  

路由器上按清单比对版本/哈希后再安装。

---

## 🗂️ 项目结构

`config/`、`docs/`、`installer/`、`modules/network|proxy|system|service`、`ui/`、`.github/actions/`（Go 生成 `install.sh`）。

---

## 💾 路由器上的数据

| 路径 | 用途 |
| :--- | :--- |
| `/etc/daypass/` | 状态、安装日志、下载的包 |
| `/etc/daypass/dns/` | DNS 模式 |
| `/etc/daypass/proxy/` | 节点、订阅、路由、Clean IP |
| `/tmp/daypass/` | 事务日志与配置备份 |
