
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
</p>

<p align="center">
  <a href="../README.md"><strong>English</strong></a>
</p>

---

- [🚀 ابزار DayPass چیه؟](#-ابزار-daypass-چیه)
- [✨ ویژگی‌ها](#-ویژگیها)
- [🖥️ سخت‌افزارهای سازگار (Hardware Compatibility)](#️-سختافزارهای-سازگار-hardware-compatibility)
- [🚀 راه‌اندازی](#-راهاندازی)
  - [🟢 ورژن پایدار](#-ورژن-پایدار)
  - [🟠 ورژن آزمایشی](#-ورژن-آزمایشی)
- [🔀 راه‌اندازی Multi-WAN و Load Balancing](#-راهاندازی-multi-wan-و-load-balancing)
  - [🔌 روترهای دارای پورت USB (سازگار با USB WAN)](#-روترهای-دارای-پورت-usb-سازگار-با-usb-wan)
- [🌐 مدیریت و جداسازی وای‌فای](#-مدیریت-و-جداسازی-وایفای)
- [🧼 مدیریت Clean IP برای Cloudflare](#-مدیریت-clean-ip-برای-cloudflare)
- [⚙️ به‌روزرسانی روزانه بسته‌ها](#️-بهروزرسانی-روزانه-بستهها)

---

## 🚀 ابزار DayPass چیه؟

ابزار **DayPass** یه چارچوب سبک، خودکار و ماژولار برای روترهای **OpenWrt** هس که مدیریت شبکه، پروکسی و مسیریابی رو یکجا براتون ساده می‌کنه!

با پشتیبانی از **Passwall**، **Multi-WAN**، **Guest Network** و **Clean IP**، کمک می‌کنه حتی تو شرایط فیلترینگ شدید، دسترسی پایدارتر و هوشمندتری به اینترنت داشته باشی. از انتخاب نود و شانت کردن ترافیک گرفته تا جایگزینی IPهای کلودفلر و پروفایل‌های آماده مسیریابی، همه چیز رو پوشش می‌ده.

ابزار DayPass با هر دو پکیج‌منیجر ورژن های OpenWrt کاملاً سازگاره :

- **OpenWrt 24.x** با `opkg`
- **OpenWrt 25.x** با `apk`

بسته‌ها بر اساس نسخه OpenWrt و معماری سخت‌افزار روترتون دریافت و نصب می‌شن.

---

## ✨ ویژگی‌ها

- 📦 **به‌روزرسانی روزانه بسته‌ها (Daily Sync)**  
  دریافت خودکار آپدیت بسته‌های موردنیاز، بدون وابستگی به مخزن‌های رسمی SourceForge (که معمولاً در کشورهای تحریم در دسترس نیستن) .

- 🔀 **مدیریت هوشمند Multi-WAN**  
  امکان ترکیب و مدیریت هم‌زمان چند مسیر اینترنتی؛ از اینترنت کابلی و فیبر (`WAN`) گرفته تا اینترنت گوشی، مودم USB (`USB WAN`) و وای‌فای دیگران (`WWAN`) با کمک `mwan3` .

- 📡 **جداسازی و مدیریت وای‌فای**  
  جدا نگه‌داشتن بخش Access Point روتر از حالت Client/Station تا پیکربندی این دو بخش با هم تداخل نکنن و کانکشن وای‌فای بی‌دلیل قطع نشه .

- 🔄 **هماهنگ‌سازی خودکار شبکه داخلی**  
  تغییر خودکار IP شبکه داخلی، هماهنگ کردن بازه DHCP و پاک‌سازی لیست IP های قدیمی از فایل `dhcp.leases` .

- 🌐 **سازگاری با ورژن‌های مختلف OpenWrt**  
  پشتیبانی از OpenWrt 24.x (`opkg`) و OpenWrt 25.x (`apk`) روی بیش از ۹ معماری سخت‌افزاری .

---

## 🖥️ سخت‌افزارهای سازگار (Hardware Compatibility)

| معماری پردازنده | نمونه سخت‌افزارها و روترهای سازگار |
| :--- | :--- |
| **`aarch64_cortex-a53` / `aarch64_generic`** | **Raspberry Pi :** 3B, 3B+, 4B<br>**FriendlyELEC :** NanoPi R2S, R4S, R5S<br>**GL.iNet :** Flint (GL-AX1800), Slate AX (GL-AXT1800)<br>**Xiaomi :** AX3000T, AX6000 |
| **`aarch64_cortex-a72` / `aarch64_cortex-a76`** | **Raspberry Pi :** 4B, 5<br>**SBCs :** Rockchip RK3399, RK3588 (NanoPi R6S, Orange Pi 5) |
| **`arm_cortex-a7_neon-vfpv4` / `arm_cortex-a9`** | **Linksys :** EA8300, MR8300<br>**Netgear :** R7000, R7800, R8000<br>**ASUS :** RT-AC68U, RT-AC87U<br>**GL.iNet :** B1300 (ConnextDrive) |
| **`mipsel_24kc`** | **Xiaomi :** Mi Router 3G, 4A Gigabit<br>**TP-Link :** Archer C50, C6, C7, TL-WR841N<br>**Ubiquiti :** EdgeRouter X (ER-X)<br>**GL.iNet :** Mango (GL-MT300N-V2), Shadow (GL-AR300M) |
| **`x86_64` / `i386_pentium4`** | **مینی‌پی‌سی‌ها و مینی‌سرورها :** Mini PCs (Intel N100, N5105, J4125)<br>**سخت‌افزارهای صنعتی :** Protectli Vault, Qotom, Topton (با پورت‌های Intel i225/i226)<br>**ماشین‌های مجازی :** VMware, Proxmox VE, KVM, VirtualBox |

---

## 🚀 راه‌اندازی

چون DayPass به‌صورت پیوسته در حال به روزرسانی و افزودن ویژگی های جدید برای معماری‌های گوناگونه، پس دو ورژن پایدار و آزمایشی داریم! ورژن پایدار امکانات کمتری داره ولی کاملاً پایداره. ورژن آزمایشی تقریباً هر روز آپدیت می‌شه و ویژگی های بیشتری داره، ولی ممکنه باگ داشته باشه!

> **‼️ نکته :** ورژن آزمایشی تنها برای کسانی پیشنهاد می‌شه که حداقل آشنایی اولیه با این فیلد رو دارن و می‌تونن دیباگ کنن و در نهایت گزارش بدن. افراد مبتدی بهتره از ورژن پایدار استفاده کنن .

---

### 🟢 ورژن پایدار

این دستور رو در ترمینال روتر اجرا کن :

```bash
wget -qO- https://chamroosh98.github.io/DayPass/install.sh | sh
```

اگه دستور `curl` از پیش روی روتر نصب کردی می‌تونی از دستور زیر استفاده کنی :

```bash
curl -sSL https://chamroosh98.github.io/DayPass/install.sh | sh
```

---

### 🟠 ورژن آزمایشی

دستور نصب ورژن آزمایشی:

```bash
wget -qO- https://chamroosh98.github.io/DayPass/beta/install.sh | sh
```

یا:

```bash
curl -sSL https://chamroosh98.github.io/DayPass/beta/install.sh | sh
```

> ⚠️ **یادآوری :** ورژن آزمایشی (Beta) ممکنه باگ داشته باشه؛ بنابراین تنها برای افراد با تجربه یا ماجراجو پیشنهاد می‌شه.

---

## 🔀 راه‌اندازی Multi-WAN و Load Balancing

با DayPass می‌تونی چند مسیر اینترنتی رو هم‌زمان روی روتر راه‌اندازی و مدیریت کنی.

* **🌐 اینترنت کابلی (`Ethernet WAN`)**  
  ارتباط ورودی روتر از مودم ADSL/VDSL یا فیبر نوری (دریافت اینترنت از طریق پورت WAN با کابل LAN).

> 💡 **تفاوت پورت WAN و LAN**  
> * **پورت `WAN` (ورودی اینترنت):** روتر اینترنت رو از مودم اصلی، فیبر نوری یا آنتن بیرونی دریافت می‌کنه.  
> * **پورت `LAN` (خروجی اینترنت):** روتر اینترنت دریافتی رو بین دستگاه‌های داخلی (کامپیوتر، تلویزیون، روتر یا مودم دوم و سوییچ) پخش می‌کنه.

* **📱 اینترنت گوشی و مودم USB (`USB WAN`)**  
  کانکشن گوشی‌های اندرویدی، آیفون یا مودم‌های 4G/5G به پورت USB روتر. DayPass از حالت‌های CDC-Ethernet و RNDIS پشتیبانی می‌کنه.

### 🔌 روترهای دارای پورت USB (سازگار با USB WAN)

| معماری پردازنده | مدل‌های دارای پورت USB | تعداد و نوع پورت USB |
| :--- | :--- | :--- |
| **`aarch64_cortex-a53`** | **Raspberry Pi:** 3B, 3B+, 4B<br>**FriendlyELEC:** NanoPi R2S, R4S, R5S<br>**GL.iNet:** Flint (GL-AX1800), Slate AX (GL-AXT1800)<br>**Xiaomi:** AX6000 | **Raspberry Pi:** 4x USB<br>**NanoPi:** 1x تا 2x USB<br>**GL.iNet:** 1x USB 3.0<br>**Xiaomi:** 1x USB 3.0 |
| **`aarch64_cortex-a72/a76`** | **Raspberry Pi:** 4B, 5<br>**SBCs:** Rockchip RK3399, RK3588 (NanoPi R6S, Orange Pi 5) | **Raspberry Pi:** 2x USB 3.0 + 2x USB 2.0<br>**Orange Pi / NanoPi:** 2x تا 3x USB |
| **`arm_cortex-a7_neon-vfpv4` / `arm_cortex-a9`** | **Linksys:** EA8300, MR8300<br>**Netgear:** R7000, R7800, R8000<br>**ASUS:** RT-AC68U, RT-AC87U<br>**GL.iNet:** B1300 | **Linksys:** 1x USB 3.0 / 2.0<br>**Netgear / ASUS:** 1x USB 3.0 + 1x USB 2.0<br>**GL.iNet B1300:** 1x USB 3.0 |
| **`mipsel_24kc`** | **Xiaomi:** Mi Router 3G <br>**TP-Link:** Archer C7<br>**GL.iNet:** Mango (GL-MT300N-V2), Shadow (GL-AR300M) | **Xiaomi 3G:** 1x USB 3.0<br>**Archer C7:** 2x USB 2.0<br>**GL.iNet Mango/Shadow:** 1x USB 2.0 |
| **`x86_64` / `i386`** | **مینی‌پی‌سی‌ها و مینی‌سرورها:** Intel N100, N5105, Protectli, Topton<br>**محیط مجازی:** VMware, Proxmox (از طریق USB Passthrough) | **بیشتر دارای بین ۲ تا ۴ پورت USB 3.0/2.0** |

> * **`USB WAN (Tethering)`:**
> 
>  اشتراک‌گذاری اینترنت گوشی یا مودم‌های 4G/5G با روتر، به وسیله کابل USB.  
> * **`RNDIS`:**
> 
>  استاندارد مایکروسافت برای شبیه‌سازی کارت شبکه روی USB؛ بیشتر در گوشی‌های اندرویدی قدیمی و برخی مودم‌های دانگل بهره وری می‌شه.  
> 
> * **`CDC-Ethernet`:**
> 
>  استاندارد جهانی و متن‌باز لینوکس/پوزیکس؛ سرعت بالاتر، latency کمتر و پایداری بهتر در آیفون، اندرویدهای جدید و مودم‌های مدرن.

* **📡 اینترنت وای‌فای (`WWAN`)**  
  گرفتن اینترنت از یک روتر، مودم یا هات‌اسپات دیگه و رسوندن آن به شبکه داخلی روتر.

این کانکشن‌ها به‌صورت خودکار در `mwan3` ثبت می‌شن و دو قابلیت اصلی رو در اختیارت می‌ذارن:

* **Failover :**

   اگر یکی از کانکشن‌ها قطع بشه، ترافیک به‌صورت خودکار از مسیر دیگه عبور می‌کنه.  
* **Load Balancing :**

  ترافیک بین چند کانکشن پخش می‌شه تا از چند مسیر اینترنتی به‌صورت هم‌زمان بهره وری بشه.

> **توجه :** Load Balancing به این معنی نیس که سرعت یک دانلود تکی دقیقاً برابر با جمع سرعت همهٔ کانکشن‌ها بشه! بلکه ترافیک بین مسیرهای مختلف پخش می‌شه و میزان بهره‌وری نهایی به نوع کانکشن‌ها و پیکربندی `mwan3` بستگی داره.

---

## 🌐 مدیریت و جداسازی وای‌فای

یکی از مشکلات رایج در OpenWrt زمانی پیش میاد که روتر هم‌زمان به‌عنوان **Access Point** و **Client** وای‌فای کار کنه. دستکاری پیکربندی یک بخش ممکنه روی بخش دیگه افکت بذاره و حتی باعث قطع شدن وای‌فای بشه.

ابزار **DayPass** برای جلوگیری از این مشکل، پیکربندی این دو بخش رو از هم جدا نگه می‌داره :

* مدیریت Access Point روتر برای شبکه خانگی روی باندهای ۲.۴ گیگاهرتز و ۵ گیگاهرتز  
* مدیریت دریافت اینترنت از وای‌فای (`WWAN` / حالت Client) بدون دستکاری پیکربندی Access Point

---

## 🧼 مدیریت Clean IP برای Cloudflare

این بخش برای کانفیگایی طراحی شده که پشت **Cloudflare Worker / CDN** هسن و به‌خاطر فیلترینگ شدید ممکن است IP یا دامنه اصلی‌شان از کار بیفته!

❓ چکار میکنه؟
- کانفیگ خراب/ناپایدار را از بین کانفیگ‌های ذخیره‌شده انتخاب میکنه .
- **پورت** را مستقیم از خودِ share link بیرون میکشه .
- لیست IPهای کاندید را روی **همان پورت** تست میکنه .
- و IP های در دسترس را همراه با تأخیرشون نشون میده
- تنها بخش **Address** را با Clean IP جایگزین میکنه .
- پارامترهای مهم مانند `SNI` / `Host` / `Path` رو دست‌نخورده نگه میداره .
- در صورت خواستن کاربر، کانفیگ آپدیت‌شده را به Passwall وارد میکنه .

---

## ⚙️ به‌روزرسانی روزانه بسته‌ها

ابزار **DayPass** به شکل خودکار و روزانه تموم پکیج‌های موردنیاز رو به‌روزرسانی می‌کنه! فرایند به این شکله ک :

۱. 📥 دریافت پکیج‌ها از **SourceForge** .

۲. 📦 دسته‌بندی و آماده‌سازی پکیج‌ها بر اساس **۹ معماری سخت‌افزاری و ۲ ورژن OpenWrt** .

۳. 🌐 انتشار فایل‌ها روی **CDN سرویس jsDelivr**
