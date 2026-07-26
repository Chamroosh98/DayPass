
<div align="center" dir="rtl">

# DayPass

**🕊️ یادبود کشتار فجیعانه ایران در ۱۸-۱۹ دی ماه خونین ۱۴۰۴**

*ابزار مدیریت و عیب‌یابی شبکه و سیستم برای OpenWrt با کارایی بالا و مینیمال*

[![release](https://img.shields.io/badge/release-latest-purple?style=flat-square)](https://github.com/Chamroosh98/DayPass/releases)
[![shell](https://img.shields.io/badge/shell-POSIX%20ash-blue?style=flat-square&logo=gnu-bash)](https://www.openwrt.org)
[![platform](https://img.shields.io/badge/platform-OpenWrt-darkgreen?style=flat-square&logo=openwrt)](https://openwrt.org)

---

</div>

<div dir="rtl">
    
> [**English Guide**](./README.md)

-
  - [🚀 daypass](#-daypass)
  - [✨ ویژگی ها](#ویژگی-ها)
  - [⚡ استارت فوری](#استارت-فوری)
    - [🟢 ورژن پایدار](#-ورژن-پایدار)
    - [🟠 ورژن آزمایشی](#-ورژن-آزمایشی)
---

## 🚀 daypass

**DayPass** یک رابط ترمینال سبک و پاسخ‌گوست که اختصاصاً برای روترهای OpenWrt و سیستم‌های لینوکس تعبیه‌شده طراحی شده. این ابزار عیب‌یابی زمان‌واقعی سیستم، جزئیات شبکه ISP، بررسی سلامت DNS/تأخیر و مانیتورینگ زنده سرعت را ارائه می‌ده —همه در یک رابط ترمینالی تمیز و هم‌تراز شده با ANSI، بدون وابستگی‌های سنگین خارجی.

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
curl -sSL https://chamroosh98.github.io/DayPass/dev/install.sh | sh
```

**wget :**
```bash
wget -qO- https://chamroosh98.github.io/DayPass/dev/install.sh | sh
```