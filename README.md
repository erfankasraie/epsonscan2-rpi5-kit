# Epson Scan 2 روی Raspberry Pi (arm64) — کیت نصب و عیب‌یابی

این کیت برای اسکنرهای USB اپسون (آزمایش‌شده با **Perfection V39 / GT-S650**) روی **رسپبری پای ۵ با Ubuntu 26.04 (arm64)** است.
وقتی با آن روبه‌رو می‌شوید که اسکنر در `epsonscan2` یا `xsane` **شناسایی می‌شود ولی اسکن نمی‌گیرد**، این کیت راه‌حل است.

> وضعیت آزمایش: روی یک رسپبری پای ۵ (Ubuntu 26.04 arm64، اسکنر V39، شناسه USB ‏04b8:013d) به همین روش اسکن موفق انجام شد.
> مرحله ساخت فایل نشانگر (بخش ۲ پایین) روی همان دستگاه دستی انجام شد؛ اسکریپت آن را خودکار می‌کند ولی خودِ اسکریپتِ نهایی هنوز روی دستگاه دومی اجرا نشده است. اگر خطایی دیدید، `debug-scanner.sh` را اجرا کنید.

## ۱. مشکل چیست؟ (علت‌ها)

| علامت | علت واقعی |
|---|---|
| پیام `Unable to communicate with the scanner` در epsonscan2، یا `Error during device I/O` در xsane/scanimage (اسکنر در فهرست هست) | **دو چیز با هم:** (آ) این مدل‌ها (شناسه USB: `013a 013b 013c 013d 013e 013f 0142 014a`، مثل V39) برای ارتباط به برنامه بسته‌ی **`es2intif`** نیاز دارند که در سورس‌کد متن‌باز Epson **نیست** و فقط در «افزونه غیرآزاد» هست؛ (ب) epsonscan2 قبل از باز کردن اسکنر وجود فایل `/usr/libexec/epsonscan2-ocr/ocr-engine-getrotate` را به‌عنوان «نشانه نصب بودن افزونه» می‌سنجد و اگر نباشد، بدون هیچ تلاشی خطای بالا را می‌دهد. |
| افزونه رسمی اپسون برای aarch64 وجود ندارد | اپسون فقط x86_64، i686 و **armv7l (۳۲بیتی)** منتشر می‌کند. پای ۵ می‌تواند باینری ۳۲بیتی اجرا کند و هسته ۶۴بیتی `es2intif` را فقط با pipe صدا می‌زند؛ پس ترکیب کار می‌کند. |
| روی لپ‌تاپ x86 کار می‌کند و روی پای نه | لپ‌تاپ بسته رسمی x86 (با افزونه) دارد؛ پای فقط هسته‌ای دارد که خودتان از سورس ساخته‌اید. |
| کمبود برق پای | **علت نبود.** آزمایش شد: برق از پای کافی است (با کابل دوشاخه جدا امتحان شد). |

## ۲. نصب سریع (۳ دستور)

۱) کیت را روی پای باز کنید (`unzip epsonscan2-rpi5-kit.zip && cd epsonscan2-rpi5-kit`).

۲) **بسته افزونه ARM اپسون** را بگیرید و داخل پوشه `plugin/` بگذارید (بخش «دریافت افزونه» پایین). اگر اینترنت پای به سایت اپسون وصل است، خود اسکریپت تلاش می‌کند دانلودش کند.

۳) اجرا (با کاربر عادی، نه root):
```bash
bash install-all.sh
```
کار این اسکریپت: ساخت هسته از سورس (۲۰ تا ۴۰ دقیقه) ← نصب افزونه ۳۲بیتی + کتابخانه‌های armhf + تنظیم منبع apt ← ساخت فایل نشانگر ← بررسی نهایی.
بعد اسکنر را یک بار جدا و وصل کنید و بزنید:
```bash
epsonscan2          # رابط گرافیکی؛ Next
bash debug-scanner.sh   # گزارش عیب‌یابی
```

## ۳. نصب مرحله‌به‌مرحله (دستی)

1. **هسته:** `cd scripts && bash 01-build-core.sh` (سورس Epson Scan 2 نسخه 6.7.93.0 داخل خود فایل است). خروجی یک بسته `epsonscan2_6.7.93.0-1_arm64.deb` است که نصب می‌شود (حذف: `sudo apt remove epsonscan2`).
   پچ‌های سازگاری که اسکریپت می‌زند: حذف تعریف قدیمی `BOOST_NO_CXX11_RVALUE_REFERENCES` (Boost جدید با آن کامپایل نمی‌شود)، `-std=gnu++14`، `-fpermissive`، تعریف `EPSON_OCR_INSTALL_PATH`، `CMAKE_POLICY_VERSION_MINIMUM=3.5`.
2. **افزونه:** `sudo bash scripts/02-install-plugin.sh plugin/epsonscan2-bundle-...armv7l.deb.tar.gz`
   - در Ubuntu 26.04 بسته‌های armhf روی `archive.ubuntu.com` نیستند؛ اسکریپت منابع apt را به arm64 محدود می‌کند و `ports.ubuntu.com` را برای armhf اضافه می‌کند (پشتیبان: `*.bak-armhf`).
   - فایل‌ها در `/usr/lib/arm-linux-gnueabihf/epsonscan2/` نصب و از مسیر arm64 به آن لینک می‌شوند.
   - فایل نشانگر `/usr/libexec/epsonscan2-ocr/ocr-engine-getrotate` اگر نبود، به‌صورت جایگزین ساخته می‌شود (فقط چرخش خودکار با OCR کار نمی‌کند).
3. **آزمایش:** `epsonscan2 --list` و `epsonscan2` (Next).

## ۴. دریافت افزونه (Plugin)

بسته‌های رسمی (از مخزن پورت‌های FreeBSD؛ من مستقیم از شبکه خودم باز نکردم):

- `epsonscan2-bundle-raspbian-6.7.70.0.armv7l.deb.tar.gz` — SHA256: `780e0862d9e3bd885d3de9b282ed1f40bdef09a465104e6f29ad9a90f08da377`
- نسخه 6.7.80.0 همین بسته هم روی دستگاه تست‌شده کار کرد.

```bash
bash scripts/download-plugin.sh      # تلاش برای دانلود خودکار + بررسی SHA256
```
اگر از ایران دانلود نشد: روی یک سیستم دیگر (یا با VPN) از صفحه دانلود لینوکس Epson Scan 2 بخش **ARM (Raspbian armv7l)** را بگیرید و با `scp` به `plugin/` ببرید.
> لایسنس: افزونه محصول اپسون است و داخل این کیت **گنجانده نشده**؛ باید خودتان از اپسون بگیرید.

## ۵. عیب‌یابی

اول همیشه: `bash debug-scanner.sh` (گزارش در `~/epson-debug-report.txt`). موارد `[FAIL]` را از بالا به پایین رفع کنید.

| پیام | کار |
|---|---|
| `Unable to communicate with the scanner` | معمولاً فایل نشانگر یا `es2intif` نیست (دو مورد `[FAIL]` در گزارش). اجرای دوباره `02-install-plugin.sh`. |
| `apt ... armhf ... 404 Not Found` | اسکریپت افزونه آن را خودش درست می‌کند؛ اگر دستی خواستید: منبع `ports.ubuntu.com/ubuntu-ports` با `Architectures: armhf` و محدود کردن منابع اصلی به `arm64`. |
| `libusb`/`libc6:armhf` پیدا نمی‌شود | `sudo apt install libc6:armhf libstdc++6:armhf libusb-1.0-0:armhf` |
| بیلد با خطای Boost.Optional | از `scripts/01-build-core.sh` این کیت استفاده کنید (پچ شده است). |
| اسکنر در `lsusb` نیست | کابل/کلید برق؛ جدا و وصل کردن. |
| `scanimage` اسکن نمی‌گیرد ولی epsonscan2 می‌گیرد | روی همان لپ‌تاپ سالم هم دیده شد؛ برای اسکریپت‌نویسی از `epsonscan2 --scan` استفاده کنید. |
| لاگ دقیق Epson | `rm -rf /tmp/epson; mkdir /tmp/epson; epsonscan2` سپس `/tmp/epson/epsonscan2/epsonscan2.log` (نویز `ModelInfo` را با `grep -v` حذف کنید). |

## ۶. استفاده در کیوسک (خط فرمان)

```bash
epsonscan2 --list                       # فهرست اسکنرها
epsonscan2 --create                     # ساخت DefaultSettings.SF2 در پوشه فعلی
epsonscan2 --scan DefaultSettings.SF2   # اسکن بدون پنجره
epsonscan2 --get-status
bash kiosk-scan.sh /home/kiosk/out.jpg  # نمونه (آزمایش‌نشده روی کیوسک واقعی)
```
فرمت و پوشه خروجی در فایل SF2 است (پیش‌فرض: پوشه Pictures).

## ۷. محتویات کیت

```
install-all.sh          نصب یک‌مرحله‌ای
debug-scanner.sh        گزارش عیب‌یابی
kiosk-scan.sh           نمونه اسکریپت کیوسک (آزمایش‌نشده)
scripts/01-build-core.sh        هسته از سورس (سورس داخل فایل)
scripts/02-install-plugin.sh    افزونه ARM + armhf + نشانگر
scripts/download-plugin.sh      دانلود افزونه با SHA256
plugin/                 بسته افزونه را اینجا بگذارید
```
# Install-epsonscan2-driver-perfection-v39-scanner-for-raspberry-pi
