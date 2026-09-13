
<div align="center">
  <img src="../../ui/ico/dp.svg" alt="DayPass Logo" width="77" height="77" style="vertical-align: middle; margin-right: 8px;">
  <h1>
    <span style="vertical-align: middle;">DayPass</span>
  </h1>
</div>

<p align="center">
  <strong>🕊️ В память о резне в Иране 8–9 января 2026 года ...</strong>
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
  <a href="README_Zh.md"><strong>中文</strong></a>
</p>

---

- [🚀 Что такое DayPass?](#-что-такое-daypass)
- [✨ Возможности](#-возможности)
- [📋 Требования](#-требования)
- [📦 Зависимости](#-зависимости)
  - [Запуск на роутере](#запуск-на-роутере)
  - [Автоустановка при первом запуске](#автоустановка-при-первом-запуске)
  - [Пакеты профиля Passwall](#пакеты-профиля-passwall)
  - [Пакеты отдельных функций](#пакеты-отдельных-функций)
  - [CI и сборка релизов](#ci-и-сборка-релизов)
- [🖥️ Совместимое оборудование](#️-совместимое-оборудование)
- [🚀 Установка](#-установка)
  - [🟢 Стабильная версия](#-стабильная-версия)
  - [🟠 Бета-версия](#-бета-версия)
- [🧭 Интерактивные меню](#-интерактивные-меню)
- [📦 Профили пакетов](#-профили-пакетов)
- [🌐 Настройки сети](#-настройки-сети)
  - [🔀 Multi-WAN и балансировка](#-multi-wan-и-балансировка)
  - [🔌 Роутеры с USB](#-роутеры-с-usb)
  - [🌐 Управление и изоляция Wi-Fi](#-управление-и-изоляция-wi-fi)
  - [👥 Гостевая сеть и QoS](#-гостевая-сеть-и-qos)
  - [🧭 DNS Manager](#-dns-manager)
  - [🏠 LAN IP и диагностика](#-lan-ip-и-диагностика)
- [🛡️ Прокси и маршрутизация](#️-прокси-и-маршрутизация)
- [🧼 Clean IP для Cloudflare](#-clean-ip-для-cloudflare)
- [🛠️ Обслуживание и восстановление](#️-обслуживание-и-восстановление)
- [⚙️ Ежедневное обновление пакетов](#️-ежедневное-обновление-пакетов)
- [🗂️ Структура проекта](#️-структура-проекта)
- [💾 Данные на роутере](#-данные-на-роутере)

---

## 🚀 Что такое DayPass?

**DayPass** — лёгкий модульный набор для роутеров **OpenWrt**: сеть, прокси, DNS и умная маршрутизация в одном POSIX-меню.

Поддерживаются **Passwall / Passwall2**, **Multi-WAN**, **гостевая сеть**, **DNS Manager** и **Clean IP**. Это помогает держать доступ в интернет даже при жёсткой цензуре: выбор нод, шунт трафика, замена Cloudflare IP, готовые профили маршрутизации.

Совместимость с менеджерами пакетов:

- **OpenWrt 24.x** (фиды `24.10`) → `opkg`
- **OpenWrt 25.x** (фиды `25.12`) → `apk`

Пакеты берутся из сборок Passwall на **SourceForge** (не из часто недоступных официальных фидов OpenWrt) и ставятся под вашу версию и архитектуру CPU.

На роутере это один сгенерированный `install.sh`. Go-движок в CI склеивает shell-модули, собирает zip по архитектурам и публикует манифесты на GitHub Pages / jsDelivr.

---

## ✨ Возможности

- 📦 Ежедневная синхронизация пакетов Passwall: 9 архитектур × две линии OpenWrt.
- 🔒 Passwall 1 и 2 — рекомендованный профиль (Xray + fa) или своя сборка.
- 🧶 Менеджер конфигов, подписки, выгрузка в Passwall.
- 🚦 Шунт: Иран напрямую + зарубежье через прокси, глобальный прокси, только direct.
- ⚖️ Балансировка нод и проверка здоровья.
- 🧼 Cloudflare Clean IP.
- 🔀 Multi-WAN: Ethernet, USB-tethering (`wan_usb`), Wi-Fi client (`wwan`) через `mwan3`.
- 📡 Изоляция домашнего AP от WWAN.
- 👥 Гостевая сеть и лимиты (`tc` или SQM/CAKE).
- 🧭 DNS: системный, Secure (DoT/DoH), туннель Passwall, гибрид.
- 🏠 Смена LAN IP, DHCP, очистка lease.
- 🖥️ Ресурсы: архитектура, версия, RAM, flash.
- 🛠️ Purge, кэш, бэкап `sysupgrade`, factory reset.

---

## 📋 Требования

| Пункт | Деталь |
| :--- | :--- |
| **ОС** | OpenWrt **24.x** или **25.x** |
| **Оболочка** | POSIX `sh` (BusyBox ash) |
| **Права** | root |
| **Сеть** | Рабочий WAN для загрузки скрипта и zip |
| **Память** | Достаточно overlay для Passwall + Xray или Sing-box. Sing-box тяжелее; не ставьте оба движка на слабый MIPS |
| **Старт** | `wget` **или** `curl` на прошивке |

Go / Git / Actions на роутере не нужны.

---

## 📦 Зависимости

### Запуск на роутере

`wget` или `curl`, `sh`, `uci`.

### Автоустановка при первом запуске

Скрипт ставит недостающее и меняет `dnsmasq` на **`dnsmasq-full`**.

**Все версии:** `ca-bundle`, `ca-certificates`, `curl`, `jq`, `libnetfilter-conntrack`, `dnsmasq-full`

**Дополнительно OpenWrt 24.x (`opkg`):** `coreutils`, `coreutils-base64`, `coreutils-nohup`, `coreutils-timeout`, `ip-full`, `unzip`, `resolveip`, `lua`, `libuci-lua`, `luci-compat`, `luci-lib-jsonc`, `luci-lua-runtime`, `lyaml`

### Пакеты профиля Passwall

| Пакет | Когда |
| :--- | :--- |
| `luci-app-passwall` | Passwall 1 |
| `luci-app-passwall2` | Passwall 2 (рекомендуется) |
| `luci-i18n-passwall2-fa` / `-zh-cn` / `-ru` | Язык LuCI Passwall 2 |
| `xray-core` | Движок по умолчанию |
| `sing-box` | Свой выбор (больше RAM) |
| `tcping`, `geoview` | Диагностика / geo |
| `v2ray-geoip` / `v2ray-geosite` | Официальные geo (на apk иногда `geoip` / `geosite`) |

Иранские geo в custom-режиме качаются с [Chocolate4U/Iran-v2ray-rules](https://github.com/Chocolate4U/Iran-v2ray-rules).

**Рекомендуемый профиль:** Passwall 2 + Xray + язык **fa** + официальные geo.

### Пакеты отдельных функций

| Функция | Пакеты |
| :--- | :--- |
| Multi-WAN | `mwan3` (при желании `luci-app-mwan3`) |
| Простой QoS гостя | `tc`, `kmod-sched` |
| SQM | `sqm-scripts`; на 24.x ещё `luci-app-sqm` |
| USB tethering | модули ядра (`kmod-usb-net-rndis`, `kmod-usb-net-cdc-ether`, …) |
| Secure DNS | опционально `stubby` или `https-dns-proxy`; иначе DoH Passwall; запасной вариант — `1.1.1.1` / `8.8.8.8` |

### CI и сборка релизов

Go (`fetch.go` + engine), `curl` на раннере, GitHub Actions (матрица 24/25 × 9 архитектур, `gh-pages`, purge jsDelivr). Источник: SourceForge `openwrt-passwall-build`.

---

## 🖥️ Совместимое оборудование

| Архитектура процессора | Примеры совместимого оборудования и роутеров |
| :--- | :--- |
| **`aarch64_cortex-a53` / `aarch64_generic`** | **Raspberry Pi:** 3B, 3B+, 4B<br>**FriendlyELEC:** NanoPi R2S, R4S, R5S<br>**GL.iNet:** Flint (GL-AX1800), Slate AX (GL-AXT1800)<br>**Xiaomi:** AX3000T, AX6000 |
| **`aarch64_cortex-a72` / `aarch64_cortex-a76`** | **Raspberry Pi:** 4B, 5<br>**SBC:** Rockchip RK3399, RK3588 (NanoPi R6S, Orange Pi 5) |
| **`arm_cortex-a7_neon-vfpv4` / `arm_cortex-a9`** | **Linksys:** EA8300, MR8300<br>**Netgear:** R7000, R7800, R8000<br>**ASUS:** RT-AC68U, RT-AC87U<br>**GL.iNet:** B1300 (ConnextDrive) |
| **`mipsel_24kc`** | **Xiaomi:** Mi Router 3G, 4A Gigabit<br>**TP-Link:** Archer C50, C6, C7, TL-WR841N<br>**Ubiquiti:** EdgeRouter X (ER-X)<br>**GL.iNet:** Mango (GL-MT300N-V2), Shadow (GL-AR300M) |
| **`x86_64` / `i386_pentium4`** | **Мини-ПК и мини-серверы:** Intel N100, N5105, J4125<br>**Промышленное оборудование:** Protectli Vault, Qotom, Topton (с портами Intel i225/i226)<br>**Виртуальные машины:** VMware, Proxmox VE, KVM, VirtualBox |

В манифесте девять имён: `aarch64_cortex-a53`, `aarch64_cortex-a72`, `aarch64_cortex-a76`, `aarch64_generic`, `arm_cortex-a7_neon-vfpv4`, `arm_cortex-a9_vfpv3-d16`, `mipsel_24kc`, `i386_pentium4`, `x86_64`.

---

## 🚀 Установка

- **Стабильная (`main`)** — `https://chamroosh98.github.io/DayPass/`
- **Бета (`beta`)** — новые меню (включая DNS Manager) — `.../DayPass/beta/`

> **‼️ Важно:** бета — для тех, кто умеет восстанавливать роутер и писать отчёты.

### 🟢 Стабильная версия

```bash
wget -qO- https://chamroosh98.github.io/DayPass/install.sh | sh
```

```bash
curl -sSL https://chamroosh98.github.io/DayPass/install.sh | sh
```

### 🟠 Бета-версия

```bash
wget -qO- https://chamroosh98.github.io/DayPass/beta/install.sh | sh
```

```bash
curl -sSL https://chamroosh98.github.io/DayPass/beta/install.sh | sh
```

Скрипт проверяет сеть, определяет архитектуру, ставит базовые пакеты, при возможности бэкапит UCI Passwall/Xray/Sing-box и открывает меню. Повторный запуск возвращает в меню и обновляет пакеты.

---

## 🧭 Интерактивные меню

1. Установка профиля пакетов  
2. Проверка и обновление пакетов  
3. Сеть (AP, гость, LAN, Multi-WAN, DNS)  
4. Прокси и маршрутизация  
5. Ресурсы системы  
6. Обслуживание  

---

## 📦 Профили пакетов

| Режим | Содержание |
| :--- | :--- |
| **Recommended** | Passwall 2 + `xray-core` + официальные geo + LuCI **fa** |
| **Custom** | Xray / Sing-box / auto, языки Passwall 2, geo skip / official / Iran full / lite |

Клавиши custom: цифры — пакеты, `n`/`p` — страницы, `d` — далее, `q` — выход.

---

## 🌐 Настройки сети

### 🔀 Multi-WAN и балансировка

* **🌐 Ethernet WAN** — интернет с модема/оптики в порт WAN.  
* **📱 USB WAN** — интерфейс `wan_usb` (CDC-Ethernet / RNDIS). Сначала включите USB-модем на телефоне.  
* **📡 WWAN** — клиент к чужой точке, интерфейс `wwan`.

> Разница WAN (вход интернета) и LAN (раздача внутрь сети).

Члены `mwan3`: `wan` (метрика 1), `wan_usb` (2), `wwan` (3). Политики **balanced** и **failover**. Балансировка **не** складывает скорость одного TCP-скачивания.

### 🔌 Роутеры с USB

| Архитектура процессора | Модели с USB-портами | Количество и тип USB-портов |
| :--- | :--- | :--- |
| **`aarch64_cortex-a53`** | **Raspberry Pi:** 3B, 3B+, 4B<br>**FriendlyELEC:** NanoPi R2S, R4S, R5S<br>**GL.iNet:** Flint (GL-AX1800), Slate AX (GL-AXT1800)<br>**Xiaomi:** AX6000 | **Raspberry Pi:** 4× USB<br>**NanoPi:** 1–2× USB<br>**GL.iNet:** 1× USB 3.0<br>**Xiaomi:** 1× USB 3.0 |
| **`aarch64_cortex-a72/a76`** | **Raspberry Pi:** 4B, 5<br>**SBC:** Rockchip RK3399, RK3588 (NanoPi R6S, Orange Pi 5) | **Raspberry Pi:** 2× USB 3.0 + 2× USB 2.0<br>**Orange Pi / NanoPi:** 2–3× USB |
| **`arm_cortex-a7_neon-vfpv4` / `arm_cortex-a9`** | **Linksys:** EA8300, MR8300<br>**Netgear:** R7000, R7800, R8000<br>**ASUS:** RT-AC68U, RT-AC87U<br>**GL.iNet:** B1300 | **Linksys:** 1× USB 3.0 / 2.0<br>**Netgear / ASUS:** 1× USB 3.0 + 1× USB 2.0<br>**GL.iNet B1300:** 1× USB 3.0 |
| **`mipsel_24kc`** | **Xiaomi:** Mi Router 3G<br>**TP-Link:** Archer C7<br>**GL.iNet:** Mango (GL-MT300N-V2), Shadow (GL-AR300M) | **Xiaomi 3G:** 1× USB 3.0<br>**Archer C7:** 2× USB 2.0<br>**GL.iNet Mango/Shadow:** 1× USB 2.0 |
| **`x86_64` / `i386`** | **Мини-ПК и мини-серверы:** Intel N100, N5105, Protectli, Topton<br>**Виртуальные среды:** VMware, Proxmox (через USB Passthrough) | **Большинство имеют от 2 до 4 портов USB 3.0/2.0** |

### 🌐 Управление и изоляция Wi-Fi

AP 2,4/5 ГГц отдельно от режима клиента WWAN, чтобы не затирать SSID.

### 👥 Гостевая сеть и QoS

Отдельный интерфейс и firewall, опциональный SSID, лимит через `tc` или SQM (`cake` / `piece_of_cake.qos`).

### 🧭 DNS Manager

Постоянный DNS роутера (не временный фикс для `opkg`).

| Режим | Поведение |
| :--- | :--- |
| **System** | resolvers провайдера; hijack DNS Passwall выключен |
| **Secure** | Stubby → https-dns-proxy → DoH Passwall → публичный DNS |
| **Tunnel** | нужен Passwall; dnsmasq → локальный DNS Passwall через прокси |
| **Hybrid** | сначала Passwall/DoH, затем Cloudflare и Google (strict order) |

Файл состояния: `/etc/daypass/dns/mode`.

### 🏠 LAN IP и диагностика

Смена LAN, DHCP, `/tmp/dhcp.leases`. Временный DNS recovery (`1.1.1.1` / `8.8.8.8` / `9.9.9.9`) — отдельно от DNS Manager.

---

## 🛡️ Прокси и маршрутизация

Менеджер конфигов, шунт, балансировка нод, health (`tcping`), профили Balanced / Gaming / Streaming / Global / Direct. Данные: `/etc/daypass/proxy/`.

---

## 🧼 Clean IP для Cloudflare

Для конфигов за Worker/CDN: порт из share-ссылки, проверка IP на том же порту, замена только **Address**, сохранение `SNI` / `Host` / `Path`, опциональный импорт в Passwall.

---

## 🛠️ Обслуживание и восстановление

Purge по `/etc/daypass/install.log`, очистка `.ipk`/`.apk`, бэкап `sysupgrade -b`, `firstboot -y` (подтверждение `RESET`). Стартовый архив UCI: `/tmp/daypass/backups`.

---

## ⚙️ Ежедневное обновление пакетов

1. Загрузка с SourceForge `openwrt-passwall-build`  
2. Zip и `manifest.json` для 9 архитектур и OpenWrt 24+25  
3. GitHub Pages + purge jsDelivr  

На роутере сравнение версий/хешей с манифестом.

---

## 🗂️ Структура проекта

`config/`, `docs/`, `installer/`, `modules/network|proxy|system|service`, `ui/`, `.github/actions/` (Go → `install.sh`).

---

## 💾 Данные на роутере

| Путь | Назначение |
| :--- | :--- |
| `/etc/daypass/` | состояние, лог установки, пакеты |
| `/etc/daypass/dns/` | режим DNS |
| `/etc/daypass/proxy/` | ноды, подписки, routing, Clean IP |
| `/tmp/daypass/` | транзакции и бэкапы |
