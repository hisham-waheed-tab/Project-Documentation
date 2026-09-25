# نشر نسخة ديسكتوب POS للتجربة (بيئة Dev)

المشروع: `Tab-MS-POS-Desktop` (Electron + React).
الناتج: مثبّت واحد `release\TABMS-POS-Setup-<version>.exe` يُرسل للمختبر ويعمل على سيرفرات **dev** (وليس localhost).

---

## خطوات إخراج نسخة جديدة (كل مرة)

1. **أغلق البرنامج** إن كان مفتوحًا (النسخة المثبّتة أو `electron:dev`) — وإلا يتعطل البناء بسبب ملفات مقفولة.
2. **ارفع رقم الإصدار** في `package.json`:
   ```json
   "version": "0.1.1"
   ```
   بدون رفع الرقم لن يُحدّث المثبّت النسخة القديمة عند المختبر.
3. **ابنِ المثبّت**:
   ```powershell
   cd D:\Projects\Tab-MS\Tab-MS-POS-Desktop
   npm run publish:dev
   ```
   يستغرق ~2 دقيقة. الناتج في `release\TABMS-POS-Setup-<version>.exe` (~93 MB).
4. **أرسل ملف الـ `.exe` فقط** (Drive / Teams / WhatsApp). باقي ملفات `release` غير مطلوبة.

> قبل الإرسال: تأكد أن **POS Backend منشور على dev** بآخر تعديلات، وإلا سيجرب الزميل على سيرفر أقدم من الديسكتوب.

---

## عند المختبر

1. دبل كليك على المثبّت → يُثبَّت ويفتح تلقائيًا + اختصار على سطح المكتب (بدون صلاحيات Admin).
2. تحذير SmartScreen (البرنامج غير موقّع): **More info ← Run anyway**.
3. تسجيل الدخول بحسابه على dev. شاشة الدخول تعرض `dev · dev-pos-api.tab-erp.com` للتأكد من البيئة.
4. النسخة الجديدة تُثبّت فوق القديمة مباشرة، والبيانات المحلية تبقى.

### يحتاج حساب المختبر (على dev)

- مستخدم في نفس الشركة، **مربوط بالفرع**.
- صلاحية **«كاشير نقطة البيع»**.
- **نقطة بيع + خزنة** على هذا الفرع.
- لتجربة الاعتمادات: صلاحية **«مشرف نقطة البيع»** (إدراج) + رمز PIN من شاشة **«رموز PIN للمشرفين»**.

---

## كيف تعمل البيئات

| الملف | الاستخدام | السيرفر |
|---|---|---|
| `src/config/environment.local.ts` | `npm run electron:dev` / `electron:build` | POS API محلي `localhost:44349` |
| `src/config/environment.dev.ts` | `npm run publish:dev` | `dev-pos-api.tab-erp.com` — **ممنوع أي localhost** |

الاختيار يتم وقت البناء (`vite build --mode dev`) في `src/config/environment.ts`، فنسخة المختبر لا تحتوي أي عنوان محلي.

---

## الأيقونة

- المصدر: `build/icon.svg` (أحمر البراند `#C8102E` + شنطة تسوق بباركود + تيكت خصم — نشاط البيع القطاعي).
- بعد تعديل الـ SVG: `npm run icon` → يولّد `build/icon.png` (للمثبّت والـ exe) و`public/app-icon.png` (النافذة وشاشة الدخول).

---

## مشاكل معروفة

| المشكلة | الحل |
|---|---|
| البناء يقف طويلًا عند `packaging` | البرنامج مفتوح — أغلقه، احذف مجلد `release` وأعد التشغيل |
| `Cannot create symbolic link : A required privilege is not held` (winCodeSign) | فعّل **Developer Mode** في ويندوز، أو فك الأرشيف يدويًا (مرة واحدة لكل جهاز): |

```powershell
cd D:\Projects\Tab-MS\Tab-MS-POS-Desktop
$cache = "$env:LOCALAPPDATA\electron-builder\Cache\winCodeSign"
$archive = Get-ChildItem $cache -Filter *.7z | Select-Object -First 1
.\node_modules\7zip-bin\win\x64\7za.exe x -snld -y $archive.FullName "-o$cache\winCodeSign-2.6.0"
```

(أخطاء ملفات `darwin/*.dylib` أثناء الفك طبيعية ولا تؤثر.)

---

## لماذا تبويب Network فارغ في DevTools؟

الطلبات تمر عبر العملية الرئيسية في Electron (`window.posDesktop.apiFetch`) لتجنب CORS، فلا تظهر في Network.
البديل: الـ Console يعرض `[API] METHOD STATUS ms url` لكل طلب، وسجل الطلبات في
`%APPDATA%\tabms-pos-desktop\pos-auth.log` (نفس المسار للنسخة المثبّتة والتطوير). اضغط F12 داخل البرنامج لفتح DevTools.
