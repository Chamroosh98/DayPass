
<div align="center">

  <img src="../../ui/ico/dp.svg" alt="DayPass Logo" width="77" height="77" style="vertical-align: middle; margin-right: 8px;">
  <h1>
    <span style="vertical-align: middle;">DayPass</span>
  </h1>

</div>

<p align="center">
  <strong>🕊️ به یاد کشتار فجیعانه ایران در ۱۸–۱۹ دی‌ماه ۱۴۰۴ ...</strong>
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
  <a href="README_Ru.md"><strong>Русский</strong></a> |
  <a href="README_Zh.md"><strong>中文</strong></a>
</p>

---

- [🚀 ابزار DayPass چیه؟](#-ابزار-daypass-چیه)
- [✨ ویژگی‌ها](#-ویژگیها)
- [📋 پیش‌نیازها](#-پیشنیازها)
- [📦 وابستگی‌ها](#-وابستگیها)
  - [شروع نصب روی روتر](#شروع-نصب-روی-روتر)
  - [نصب خودکار در اجرای اول](#نصب-خودکار-در-اجرای-اول)
  - [بسته‌های پروفایل Passwall](#بستههای-پروفایل-passwall)
  - [بسته‌های وابسته به قابلیت](#بستههای-وابسته-به-قابلیت)
  - [ابزارهای CI و نگهداری پروژه](#ابزارهای-ci-و-نگهداری-پروژه)
- [🖥️ سخت‌افزارهای سازگار](#️-سختافزارهای-سازگار)
- [🚀 راه‌اندازی](#-راهاندازی)
  - [🟢 ورژن پایدار](#-ورژن-پایدار)
  - [🟠 ورژن آزمایشی](#-ورژن-آزمایشی)
- [🧭 منوهای تعاملی](#-منوهای-تعاملی)
- [📦 پروفایل نصب بسته](#-پروفایل-نصب-بسته)
- [🌐 تنظیمات شبکه](#-تنظیمات-شبکه)
  - [🔀 Multi-WAN و Load Balancing](#-multi-wan-و-load-balancing)
  - [🔌 روترهای دارای پورت USB](#-روترهای-دارای-پورت-usb)
  - [🌐 مدیریت و جداسازی وای‌فای](#-مدیریت-و-جداسازی-وایفای)
  - [👥 شبکه مهمان و QoS](#-شبکه-مهمان-و-qos)
  - [🧭 مدیر DNS](#-مدیر-dns)
  - [🏠 آی‌پی LAN و عیب‌یابی](#-آیپی-lan-و-عیبیابی)
- [🛡️ پروکسی و مسیریابی](#️-پروکسی-و-مسیریابی)
- [🧼 مدیریت Clean IP برای Cloudflare](#-مدیریت-clean-ip-برای-cloudflare)
- [🛠️ نگهداری و بازیابی](#️-نگهداری-و-بازیابی)
- [⚙️ به‌روزرسانی روزانه بسته‌ها](#️-بهروزرسانی-روزانه-بستهها)
- [🗂️ ساختار پروژه](#️-ساختار-پروژه)
- [💾 داده روی روتر](#-داده-روی-روتر)

---

## 🚀 ابزار DayPass چیه؟

**DayPass** یه چارچوب سبک، خودکار و ماژولار برای روترهای **OpenWrt** هس که مدیریت شبکه، پروکسی، DNS و مسیریابی هوشمند رو یکجا تو یه منوی شِل پوزیکس جمع می‌کنه.

با پشتیبانی از **Passwall / Passwall2**، **Multi-WAN**، **شبکه مهمان**، **مدیر DNS** و **Clean IP** کمک می‌کنه حتی تو فیلترینگ شدید، دسترسی پایدارتری داشته باشی. از انتخاب نود و شانت ترافیک تا جایگزینی IP کلودفلر و پروفایل‌های آماده مسیریابی، کل مسیر کار رو پوشش می‌ده.

با هر دو پکیج‌منیجر نسخه‌های جدید OpenWrt سازگاره:

- **OpenWrt 24.x** (فید `24.10`) → `opkg`
- **OpenWrt 25.x** (فید `25.12`) → `apk`

بسته‌ها از بیلدهای Passwall روی **SourceForge** میان (نه از فید رسمی OpenWrt که تو خیلی از کشورها در دسترس نیست) و بر اساس نسخه OpenWrt و معماری CPU نصب می‌شن.

روی روتر همه چیز داخل یه فایل تولیدشدهٔ `install.sh`ه. موتور Go تو CI ماژول‌های شِل رو به هم وصل می‌کنه، زیپ معماری‌ها رو می‌سازه و مانیفست رو روی GitHub Pages / jsDelivr منتشر می‌کنه.

---

## ✨ ویژگی‌ها

- 📦 **همگام‌سازی روزانه بسته‌ها** — بسته‌های Passwall برای ۹ معماری × دو خط OpenWrt، از GitHub Pages و jsDelivr.
- 🔒 **Passwall ۱ و ۲** — حالت پیشنهادی (Xray + ترجمه فارسی) یا انتخاب سفارشی موتور / زبان / Geo.
- 🧶 **مدیر کانفیگ** — ذخیره نود، سابسکریپشن، روشن/خاموش، ارسال به Passwall.
- 🚦 **شانت ترافیک** — ایران مستقیم + خارج از پروکسی، پروکسی سراسری، یا فقط مستقیم.
- ⚖️ **بالانسر نود و سلامت** — انتخاب نود، تأخیر، اعمال روی Passwall.
- 🧼 **Clean IP کلودفلر** — تست IP کاندید روی همان پورت و فقط عوض کردن Address.
- 🔀 **Multi-WAN** — WAN سیمی، USB تترینگ (`wan_usb`)، کلاینت وای‌فای (`wwan`) با `mwan3`.
- 📡 **جداسازی وای‌فای** — AP خانگی جدا از حالت WWAN.
- 👥 **شبکه مهمان** — اینترفیس و فایروال جدا، وای‌فای مهمان، محدودیت پهنای باند (`tc` یا SQM/CAKE).
- 🧭 **مدیر DNS** — سیستم، امن (DoT/DoH در صورت وجود)، تونل Passwall، یا هیبرید.
- 🏠 **تغییر IP داخلی** — LAN، DHCP و پاک‌سازی leaseهای قدیمی.
- 🖥️ **منابع سیستم** — معماری، نسخه OpenWrt، RAM و فلش overlay.
- 🛠️ **نگهداری** — حذف بسته‌های DayPass، کش، بکاپ `sysupgrade`، ریست کارخانه.

---

## 📋 پیش‌نیازها

| مورد | توضیح |
| :--- | :--- |
| **سیستم‌عامل** | OpenWrt **۲۴.x** یا **۲۵.x** (فورک‌های دیگر اگر `opkg`/`apk` و UCI داشته باشن ممکنه کار کنن) |
| **شل** | `sh` پوزیکس (BusyBox ash) |
| **دسترسی** | root روی روتر |
| **شبکه** | WAN فعال برای دانلود `install.sh` و زیپ بسته‌ها |
| **فلش / رم** | فضای overlay کافی برای Passwall + Xray یا Sing-box. Sing-box سنگین‌تره؛ روی بردهای ضعیف MIPS هر دو موتور رو با هم نذار |
| **ابزار شروع** | `wget` **یا** `curl` روی ایمیج (بقیه رو خود اسکریپت نصب می‌کنه) |

روی روتر به Go، Git یا GitHub Actions نیاز نداری؛ اینا فقط برای ساخت ریلیز هستن.

---

## 📦 وابستگی‌ها

### شروع نصب روی روتر

| ابزار | نقش |
| :--- | :--- |
| `wget` یا `curl` | دانلود `install.sh` و آرتیفکت‌ها |
| `sh` | اجرای نصب‌کننده |
| `uci` | پیکربندی OpenWrt |

### نصب خودکار در اجرای اول

`deploy_system_dependencies` کمبودها رو پر می‌کنه و `dnsmasq` ساده رو با **`dnsmasq-full`** عوض می‌کنه.

**همه نسخه‌ها:** `ca-bundle`، `ca-certificates`، `curl`، `jq`، `libnetfilter-conntrack`، `dnsmasq-full`

**اضافه OpenWrt 24.x (`opkg`):** `coreutils`، `coreutils-base64`، `coreutils-nohup`، `coreutils-timeout`، `ip-full`، `unzip`، `resolveip`، `lua`، `libuci-lua`، `luci-compat`، `luci-lib-jsonc`، `luci-lua-runtime`، `lyaml`

روی ۲۵.x معمولاً بسته‌های LuCI/Lua از قبل روی ایمیج هستن.

### بسته‌های پروفایل Passwall

از مانیفست DayPass نصب می‌شن (نه فید زنده OpenWrt):

| بسته | زمان |
| :--- | :--- |
| `luci-app-passwall` | پروفایل Passwall ۱ |
| `luci-app-passwall2` | پروفایل Passwall ۲ (پیشنهادی) |
| `luci-i18n-passwall2-fa` / `-zh-cn` / `-ru` | زبان LuCI برای Passwall ۲ (انگلیسی بسته اضافه نمی‌خواد) |
| `xray-core` | موتور پیش‌فرض / پیشنهادی |
| `sing-box` | انتخاب سفارشی (رم بیشتر) |
| `tcping` | تست TCP / سلامت |
| `geoview` | مشاهده دیتابیس Geo |
| `v2ray-geoip` / `v2ray-geosite` | Geo رسمی (روی بعضی فیدهای apk اسم `geoip` / `geosite`) |

**Geo ایران (حالت سفارشی)** فایل `geoip.dat` / `geosite.dat` (کامل یا لایت) رو از [Chocolate4U/Iran-v2ray-rules](https://github.com/Chocolate4U/Iran-v2ray-rules) می‌گیره.

**حالت پیشنهادی:** Passwall ۲ + **Xray** + زبان **fa** + Geo رسمی.

### بسته‌های وابسته به قابلیت

| قابلیت | بسته‌ها |
| :--- | :--- |
| Multi-WAN | `mwan3` (و در صورت تمایل `luci-app-mwan3`) |
| QoS ساده مهمان | `tc`، `kmod-sched` |
| SQM مهمان | `sqm-scripts`؛ در ۲۴.x معمولاً `luci-app-sqm` |
| تترینگ USB | ماژول‌های کرنل رایج (`kmod-usb-net-rndis`، `kmod-usb-net-cdc-ether`، …). اول تترینگ گوشی رو روشن کن |
| DNS امن (بهترین مسیر) | اختیاری: `stubby` (DoT) یا `https-dns-proxy` (DoH). اگر نباشن از DoH پاس‌وال استفاده می‌شه؛ آخر کار DNS عمومی `1.1.1.1` / `8.8.8.8` |

### ابزارهای CI و نگهداری پروژه

| ابزار | نقش |
| :--- | :--- |
| Go | دانلود فیدها (`fetch.go`) و ساخت `install.sh` + مانیفست |
| `curl` روی رانر | دریافت ایندکس و فایل از SourceForge |
| GitHub Actions | ماتریس ۲۴/۲۵ و ۹ معماری؛ استقرار `gh-pages`؛ پاکسازی کش jsDelivr |

منبع بالادستی: پروژه SourceForge با نام `openwrt-passwall-build` (فیدهای `passwall_packages`، `passwall2`، `passwall_luci`).

---

## 🖥️ سخت‌افزارهای سازگار

| معماری پردازنده | نمونه سخت‌افزارها و روترهای سازگار |
| :--- | :--- |
| **`aarch64_cortex-a53` / `aarch64_generic`** | **Raspberry Pi :** 3B, 3B+, 4B<br>**FriendlyELEC :** NanoPi R2S, R4S, R5S<br>**GL.iNet :** Flint (GL-AX1800), Slate AX (GL-AXT1800)<br>**Xiaomi :** AX3000T, AX6000 |
| **`aarch64_cortex-a72` / `aarch64_cortex-a76`** | **Raspberry Pi :** 4B, 5<br>**SBCs :** Rockchip RK3399, RK3588 (NanoPi R6S, Orange Pi 5) |
| **`arm_cortex-a7_neon-vfpv4` / `arm_cortex-a9`** | **Linksys :** EA8300, MR8300<br>**Netgear :** R7000, R7800, R8000<br>**ASUS :** RT-AC68U, RT-AC87U<br>**GL.iNet :** B1300 (ConnextDrive) |
| **`mipsel_24kc`** | **Xiaomi :** Mi Router 3G, 4A Gigabit<br>**TP-Link :** Archer C50, C6, C7, TL-WR841N<br>**Ubiquiti :** EdgeRouter X (ER-X)<br>**GL.iNet :** Mango (GL-MT300N-V2), Shadow (GL-AR300M) |
| **`x86_64` / `i386_pentium4`** | **مینی‌پی‌سی‌ها و مینی‌سرورها :** Mini PCs (Intel N100, N5105, J4125)<br>**سخت‌افزارهای صنعتی :** Protectli Vault, Qotom, Topton (با پورت‌های Intel i225/i226)<br>**ماشین‌های مجازی :** VMware, Proxmox VE, KVM, VirtualBox |

نه نام فید در مانیفست: `aarch64_cortex-a53`، `aarch64_cortex-a72`، `aarch64_cortex-a76`، `aarch64_generic`، `arm_cortex-a7_neon-vfpv4`، `arm_cortex-a9_vfpv3-d16`، `mipsel_24kc`، `i386_pentium4`، `x86_64`.

---

## 🚀 راه‌اندازی

دو کانال داریم:

- **پایدار (`main`)** — کمتر غافلگیر می‌کنه؛ آدرس `https://chamroosh98.github.io/DayPass/`
- **آزمایشی (`beta`)** — منوهای جدیدتر (از جمله مدیر DNS)؛ مسیر `.../DayPass/beta/`

> **‼️ نکته :** بتا برای کساییه که بلدن روتر رو برگردونن و باگ گزارش بدن. مبتدی‌ها از پایدار استفاده کنن.

---

### 🟢 ورژن پایدار

```bash
wget -qO- https://chamroosh98.github.io/DayPass/install.sh | sh
```

```bash
curl -sSL https://chamroosh98.github.io/DayPass/install.sh | sh
```

---

### 🟠 ورژن آزمایشی

```bash
wget -qO- https://chamroosh98.github.io/DayPass/beta/install.sh | sh
```

```bash
curl -sSL https://chamroosh98.github.io/DayPass/beta/install.sh | sh
```

اسکریپت اتصال رو چک می‌کنه، معماری رو تشخیص می‌ده، وابستگی‌های پایه رو نصب می‌کنه، در صورت وجود از کانفیگ Passwall/Xray بکاپ می‌گیره، بعد منوی اصلی باز می‌شه. دوباره همین دستور رو بزن تا برگردی منو و بسته‌ها رو آپدیت کنی.

---

## 🧭 منوهای تعاملی

1. **نصب پروفایل بسته** — Passwall ۱ یا ۲، پیشنهادی یا سفارشی، بازبینی، نصب.
2. **بررسی و به‌روزرسانی بسته‌ها** — مقایسه با مانیفست CDN.
3. **تنظیمات شبکه** — AP، مهمان، IP داخلی، Multi-WAN، اطلاعات، مدیر DNS.
4. **مدیر پروکسی و مسیریابی** — کانفیگ، شانت، بالانسر، سلامت، پروفایل، Clean IP.
5. **منابع سیستم** — معماری، نسخه، RAM، فلش.
6. **نگهداری و بازیابی** — پاک‌سازی، کش، بکاپ، ریست کارخانه.

---

## 📦 پروفایل نصب بسته

| حالت | کار |
| :--- | :--- |
| **پیشنهادی** | Passwall ۲ + `xray-core` + Geo رسمی + LuCI فارسی (`fa`) |
| **سفارشی** | Xray / Sing-box / خودکار، زبان‌های Passwall ۲، Geo رد / رسمی / ایران کامل / ایران لایت |

میانبرها: عدد برای انتخاب بسته، `n`/`p` صفحه، `d` تمام، `q` خروج. ترکیب Xray و Sing-box روی ARM64 / x86 اوکیه؛ روی MIPS ضعیف توصیه نمی‌شه.

---

## 🌐 تنظیمات شبکه

### 🔀 Multi-WAN و Load Balancing

چند آپ‌لینک با `mwan3`:

* **🌐 اینترنت کابلی (`Ethernet WAN`)** — از مودم ADSL/VDSL یا فیبر از پورت WAN.

> 💡 **تفاوت پورت WAN و LAN**  
> * **پورت `WAN` (ورودی):** اینترنت از مودم اصلی، فیبر یا آنتن.  
> * **پورت `LAN` (خروجی):** پخش اینترنت بین دستگاه‌های داخلی.

* **📱 اینترنت گوشی و مودم USB (`USB WAN`)** — اینترفیس `wan_usb` (CDC-Ethernet یا RNDIS). اول تترینگ گوشی رو روشن کن.

### 🔌 روترهای دارای پورت USB

| معماری پردازنده | مدل‌های دارای پورت USB | تعداد و نوع پورت USB |
| :--- | :--- | :--- |
| **`aarch64_cortex-a53`** | **Raspberry Pi:** 3B, 3B+, 4B<br>**FriendlyELEC:** NanoPi R2S, R4S, R5S<br>**GL.iNet:** Flint (GL-AX1800), Slate AX (GL-AXT1800)<br>**Xiaomi:** AX6000 | **Raspberry Pi:** 4x USB<br>**NanoPi:** 1x تا 2x USB<br>**GL.iNet:** 1x USB 3.0<br>**Xiaomi:** 1x USB 3.0 |
| **`aarch64_cortex-a72/a76`** | **Raspberry Pi:** 4B, 5<br>**SBCs:** Rockchip RK3399, RK3588 (NanoPi R6S, Orange Pi 5) | **Raspberry Pi:** 2x USB 3.0 + 2x USB 2.0<br>**Orange Pi / NanoPi:** 2x تا 3x USB |
| **`arm_cortex-a7_neon-vfpv4` / `arm_cortex-a9`** | **Linksys:** EA8300, MR8300<br>**Netgear:** R7000, R7800, R8000<br>**ASUS:** RT-AC68U, RT-AC87U<br>**GL.iNet:** B1300 | **Linksys:** 1x USB 3.0 / 2.0<br>**Netgear / ASUS:** 1x USB 3.0 + 1x USB 2.0<br>**GL.iNet B1300:** 1x USB 3.0 |
| **`mipsel_24kc`** | **Xiaomi:** Mi Router 3G <br>**TP-Link:** Archer C7<br>**GL.iNet:** Mango (GL-MT300N-V2), Shadow (GL-AR300M) | **Xiaomi 3G:** 1x USB 3.0<br>**Archer C7:** 2x USB 2.0<br>**GL.iNet Mango/Shadow:** 1x USB 2.0 |
| **`x86_64` / `i386`** | **مینی‌پی‌سی‌ها و مینی‌سرورها:** Intel N100, N5105, Protectli, Topton<br>**محیط مجازی:** VMware, Proxmox (از طریق USB Passthrough) | **بیشتر دارای بین ۲ تا ۴ پورت USB 3.0/2.0** |

> * **`USB WAN (Tethering)`:** اشتراک اینترنت گوشی یا مودم 4G/5G با کابل USB.  
> * **`RNDIS`:** شبیه‌سازی کارت شبکه مایکروسافت روی USB.  
> * **`CDC-Ethernet`:** استاندارد لینوکس/پوزیکس؛ پایدارتر روی آیفون و اندروید جدید.

* **📡 اینترنت وای‌فای (`WWAN`)** — کلاینت روی AP دیگر؛ اینترفیس `wwan` جدا از AP خانگی.

اعضای `mwan3`: `wan` (متریک ۱)، `wan_usb` (۲)، `wwan` (۳). سیاست‌ها: **balanced** (قانون پیش‌فرض IPv4) و **failover**.

> **توجه :** Load Balancing سرعت یک دانلود تکی رو جمع همه لینک‌ها نمی‌کنه؛ جریان‌ها بین مسیرها پخش می‌شن.

---

### 🌐 مدیریت و جداسازی وای‌فای

تو OpenWrt اگر روتر هم‌زمان AP و Client باشه، دستکاری یکی ممکنه وای‌فای رو قطع کنه. DayPass پیکربندی AP خانگی (۲.۴ و ۵ گیگاهرتز) رو از مسیر WWAN جدا نگه می‌داره.

---

### 👥 شبکه مهمان و QoS

- اینترفیس و زون فایروال جدا از LAN  
- SSID مهمان اختیاری  
- محدودیت: `tc` ساده یا SQM با `cake` / `piece_of_cake.qos`  
- امکان حذف کامل شبکه مهمان  

---

### 🧭 مدیر DNS

DNS پایدار روتر (جدا از ترمیم موقت DNS برای `opkg` در Network Checker).

| حالت | رفتار |
| :--- | :--- |
| **سیستم** | dnsmasq از DNS مودم/ISP؛ hijack DNS پاس‌وال خاموش (خود پروکسی می‌تونه روشن بمونه) |
| **امن** | اول Stubby DoT، بعد `https-dns-proxy`، بعد DoH پاس‌وال (کلودفلر). اگر هیچ‌کدام نبود: `1.1.1.1` / `8.8.8.8` |
| **تونل** | نیاز به Passwall. dnsmasq به پورت DNS محلی پاس‌وال؛ `dns_redirect`؛ DNS ریموت روی TCP از مسیر پروکسی |
| **هیبرید** | اول پاس‌وال/DoH، بعد کلودفلر و گوگل با **ترتیب سخت** |

وضعیت در `/etc/daypass/dns/mode` ذخیره می‌شه.

---

### 🏠 آی‌پی LAN و عیب‌یابی

- تغییر IPv4 داخلی، هم‌ترازی DHCP، پاک‌سازی `/tmp/dhcp.leases`  
- اطلاعات شبکه / سرعت  
- بازیابی DNS موقت (`1.1.1.1`، `8.8.8.8`، `9.9.9.9`) برای نصب بسته — جدا از مدیر DNS  

---

## 🛡️ پروکسی و مسیریابی

| ابزار | نقش |
| :--- | :--- |
| **مدیر کانفیگ** | لیست / افزودن لینک، سابسکریپشن، ارسال به Passwall |
| **مسیریابی** | ایران مستقیم + خارج پروکسی، پروکسی سراسری، فقط مستقیم |
| **بالانسر نود** | انتخاب نودهای ذخیره‌شده و اعمال روی Passwall |
| **سلامت** | دسترسی و تأخیر تقریبی (`tcping` در صورت وجود) |
| **پروفایل** | متعادل، گیمینگ، استریم (پایه ایران‌مستقیم)، پروکسی جهانی، فقط مستقیم |

مسیر داده: `/etc/daypass/proxy/`.

---

## 🧼 مدیریت Clean IP برای Cloudflare

برای کانفیگ‌هایی که پشت **Cloudflare Worker / CDN** هستن و IP یا دامنه اصلی از کار افتاده.

- کانفیگ خراب/ناپایدار رو از ذخیره‌ها انتخاب می‌کنه  
- **پورت** رو از share link درمیاره  
- لیست IP کاندید رو روی **همان پورت** تست می‌کنه  
- IPهای در دسترس و تأخیرشون رو نشون می‌ده  
- فقط **Address** رو عوض می‌کنه  
- `SNI` / `Host` / `Path` دست‌نخورده می‌مونه  
- در صورت تأیید، کانفیگ رو به Passwall می‌فرسته  

---

## 🛠️ نگهداری و بازیابی

- **حذف** بسته‌های ثبت‌شده در `/etc/daypass/install.log`  
- **پاک‌سازی کش** فایل‌های `.ipk` / `.apk` / `.part`  
- **بکاپ** با `sysupgrade -b`  
- **ریست کارخانه** با `firstboot -y` (باید `RESET` تایپ کنی)  

در شروع، از `/etc/config/passwall`، `passwall2`، `xray`، `sing-box`، `niki` در `/tmp/daypass/backups` آرشیو گرفته می‌شه.

---

## ⚙️ به‌روزرسانی روزانه بسته‌ها

CI زیپ معماری و مانیفست رو تازه می‌کنه (ریلیز: کرون روزانه + پوش به `main`؛ بتا: پوش به `beta`).

۱. 📥 دانلود فیدهای Passwall از **SourceForge** (`openwrt-passwall-build`)  
۲. 📦 ساخت زیپ و `manifest.json` برای **۹ معماری** و **OpenWrt ۲۴ و ۲۵**  
۳. 🌐 انتشار `install.sh`، زیپ و SHA-256 روی **GitHub Pages** و پاکسازی **jsDelivr**

روی روتر، «بررسی و به‌روزرسانی» نسخه/هش نصب‌شده رو با مانیفست مقایسه می‌کنه و فقط تغییرها رو نصب می‌کنه.

---

## 🗂️ ساختار پروژه

```
DayPass/
├── config/                  # architectures_24/25، providers، settings
├── docs/                    # همین README و ترجمه‌ها
├── installer/               # تشخیص معماری، zero-deps، opkg/apk، نصب
├── modules/network/...      # WAN، مهمان، DNS
├── modules/proxy/...        # کانفیگ، شانت، کلودفلر
├── modules/system/...       # منابع، بکاپ، نگهداری
├── ui/                      # منوها
└── .github/actions/         # موتور Go برای install.sh
```

---

## 💾 داده روی روتر

| مسیر | کاربرد |
| :--- | :--- |
| `/etc/daypass/` | وضعیت، لاگ نصب، بسته‌های دانلودشده |
| `/etc/daypass/dns/` | حالت DNS |
| `/etc/daypass/proxy/` | نودها، ساب، مسیریابی، بالانسر، Clean IP |
| `/tmp/daypass/` | لاگ تراکنش و بکاپ کانفیگ |
