<br>

<div align="center">
  <img src="../../ui/ico/dp.svg" alt="DayPass Logo" width="77" height="77" style="vertical-align: middle; margin-right: 8px;">
  <h1>
    <span style="vertical-align: middle;">DayPass</span>
  </h1>
</div>

<p align="center">
  <strong>🕊️ یادبود کشتار فجیعانه ایران در ۱۸-۱۹ دی ماه خونین ۱۴۰۴</strong>
</p>

---

<p align="center">
  <a href="https://github.com/Chamroosh98/DayPass/releases"><img src="https://img.shields.io/github/v/release/Chamroosh98/DayPass?style=for-the-badge&label=&color=1D63ED&logo=github&logoColor=white" alt="Release"></a>
  <a href="https://openwrt.org"><img src="https://img.shields.io/badge/POSIX_ash-4E9A06?style=for-the-badge&logo=gnu-bash&logoColor=white" alt="POSIX ash"></a>
  <a href="https://openwrt.org"><img src="https://img.shields.io/badge/OpenWrt-0066CC?style=for-the-badge&logo=openwrt&logoColor=white" alt="OpenWrt"></a>
  <a href="https://github.com/Chamroosh98/DayPass/blob/main/LICENSE"><img src="https://img.shields.io/badge/MIT-4C1D95?style=for-the-badge" alt="MIT License"></a>
</p>

<p align="center">
  <a href="../../README_FA.md"><strong>English Guide</strong></a>
</p>

---


</div>

<div dir="rtl">

-
  - [🚀  ابزار DayPass چیست؟](#-ابزار-DayPass-چیست)
  - [✨ ویژگی ها](#ویژگی-ها)
  - [⚡ استارت فوری](#استارت-فوری)
    - [🟢 ورژن پایدار](#-ورژن-پایدار)
    - [🟠 ورژن آزمایشی](#-ورژن-آزمایشی)
---

## 🚀 ابزار DayPass چیست؟

ابزار **DayPass** یک رابط ترمینال سبک و پاسخ‌گوست که اختصاصاً برای روترهای OpenWrt و سیستم‌های لینوکس تعبیه‌شده طراحی شده. این ابزار عیب‌یابی زمان‌واقعی سیستم، جزئیات شبکه ISP، بررسی سلامت DNS/تأخیر و مانیتورینگ زنده سرعت را ارائه می‌ده —همه در یک رابط ترمینالی تمیز و هم‌تراز شده با ANSI، بدون وابستگی‌های سنگین خارجی.

---

## ✨ ویژگی ها

* **🖥 بررسی اجمالی سیستم:** مشاهده آنی معماری، نسخه OpenWrt، میزان مصرف RAM و حافظه overlay همراه با پروگرس‌بارهای بصری.
* **🌐 عیب‌یابی شبکه:** کشف دقیق IP عمومی، موقعیت مکانی، نام ISP و شناسه ASN با استفاده از APIهای سریع با قابلیت پشتیبان.
* **🔎 بررسی‌کننده سلامت:** حل هم‌زمان DNS، ارزیابی افت پکت‌های Ping و تست تأخیر HTTPS روی نودهای اصلی شبکه (`google.com`, `cloudflare.com` و...).
* **📊 مانیتورینگ زنده سرعت:** مانیتورینگ زمان‌واقعی پهنای باند اینترفیس WAN (`KB/s` / `MB/s`) بدون هیچ‌گونه لرزش در ترمینال.
* **🧰 یکپارچگی با مدیر پکیج:** منوی CLI تعاملی برای ساده‌سازی نصب پکیج‌های دلخواه.

---

## ⚡ استارت فوری

> 📌 **نکته:** اگه `curl` از پیش، روی روترت نصب شده، دستور `curl` پیشنهاد میشه! وگرنه، `wget` رو بزن تو کار!

### 🟢 ورژن پایدار 

**curl :**
```bash
curl -sSL https://chamroosh98.github.io/DayPass/install.sh | sh
```

**wget :**
```bash
wget -qO- https://chamroosh98.github.io/DayPass/install.sh | sh
```

### 🟠 ورژن آزمایشی
**curl :**
```bash
curl -sSL https://chamroosh98.github.io/DayPass/beta/install.sh | sh
```

**wget :**
```bash
wget -qO- https://chamroosh98.github.io/DayPass/beta/install.sh | sh
```