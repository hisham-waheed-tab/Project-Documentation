# دليل قراءة اللوج على سيرفر Hetzner

السيرفيسات بقت شغالة على سيرفر Hetzner كـ Docker containers (مفيش IIS ولا Cloud Run)، واللوج كله بيتجمع في **Grafana / Loki**.
الدليل ده للقراءة فقط. الباسوردات في ورقة الوصول الخاصة بيك، **متكتبهاش في أي ملف داخل الريبو**.

---

## 1. التجهيز (مرة واحدة)

1. نزّل **WireGuard** من [wireguard.com/install](https://www.wireguard.com/install/).
2. **Add Tunnel → Import tunnel(s) from file** واختار ملف الـ `.conf` الخاص بيك، وبعدين **Activate**.
3. اتأكد إن الاتصال شغال من PowerShell:

```powershell
Test-NetConnection 10.8.0.1 -Port 3000
```

لازم يطلع `TcpTestSucceeded : True`.

> لو الشبكة بتقفل UDP (بعض شبكات الشركات)، شغّل `wstunnel` الموجود مع ملفات الوصول، واستخدم بروفايل `TAB-TLS.conf`.

---

## 2. فتح اللوج من المتصفح (الطريقة الأسهل)

1. افتح [http://10.8.0.1:3000](http://10.8.0.1:3000) (لازم `http` مش `https`).
2. سجّل دخول بيوزر وباسورد **Grafana** (مش باسورد السيستم).
3. من القائمة: **Explore** ← اختار **Loki** فوق.
4. اكتب الاستعلام في خانة الـ query (اضغط **Code** لو ظاهر Builder) وبعدين **Run query**.
5. حدد الفترة من فوق يمين (مثلاً Last 1 hour).

### أسماء الـ containers

الاسم = `البيئة-السيرفيس-رقم`، والرقم بيزيد مع كل نشر جديد.

| الدومين | الـ container |
|---|---|
| dev-auth.tab-erp.com | `dev-admin-auth-*` |
| dev-host (Administration API) | `dev-admin-api-*` |
| dev-app.tab-erp.com (الفرونت) | `dev-tabms-web-*` |
| HR | `dev-hr-api-*` |
| Caddy (البوابة اللي قدام كل الدومينات) | `caddy` |

- بدّل `dev` بـ `staging` أو `prod` حسب البيئة.
- استخدم `=~` مع `.*` عشان تجيب كل الأرقام، لأن ممكن يكون فيه container قديم وجديد مع بعض وقت النشر.

---

## 3. استعلامات جاهزة

**كل أخطاء الـ AuthServer في dev:**

```
{container=~"dev-admin-auth.*"} |~ "ERR|Exception"
```

**ليه الـ login اترفض؟ (scope / client / redirect):**

```
{container=~"dev-admin-auth.*"} |~ "rejected|invalid_scope|invalid_client|redirect_uri"
```

مثال لرسالة بتشرح المشكلة على طول:
`The authorization request was rejected because the application 'TABMS_Front_Prod' was not allowed to use the 'DesktopDashboard' scope.`

**أخطاء الـ API:**

```
{container=~"dev-admin-api.*"} |= "ERR"
```

**طلبات endpoint معين:**

```
{container=~"dev-admin-api.*"} |= "GetSystemData"
```

**الـ container اشتغل امتى؟ (آخر نشر أو ريستارت):**

```
{container=~"dev-admin-auth.*"} |= "Now listening"
```

**كل لوج بيئة كاملة:**

```
{env="dev"} |= "ERR"
```

### تقليل الضوضاء

- استبعد سطور معينة بـ `!=` أو `!~`، مثلاً:

```
{container=~"dev-admin-api.*"} |= "ERR" != "Volo.Abp"
```

- `|=` = يحتوي النص بالظبط، و`|~` = regex (مثلاً `"ERR|WRN"`).

---

## 4. الوقت

- Grafana بيعرض الوقت بتوقيتك المحلي.
- لكن داخل سطر اللوج نفسه، الوقت بالـ **UTC** = توقيت القاهرة/السعودية **ناقص 3 ساعات**.
- مثال: `[07:26:22 INF]` جوه السطر = الساعة 10:26 عندك.

---

## 5. من PowerShell (بدون متصفح)

مفيد لو عايز تنسخ النتيجة أو تدوّر بسرعة. الباسورد بيتحط في متغير في الجلسة بس:

```powershell
$env:GRAFANA_PWD = Read-Host 'Grafana password'
$h = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("YOUR_USER:$env:GRAFANA_PWD")) }
$q = [Uri]::EscapeDataString('{container=~"dev-admin-auth.*"} |~ "rejected|ERR"')
$end = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() * 1000000
$start = $end - 60 * 60 * 1000000000   # آخر ساعة
$r = Invoke-RestMethod "http://10.8.0.1:3000/api/datasources/proxy/uid/loki/loki/api/v1/query_range?query=$q&start=$start&end=$end&limit=50" -Headers $h
$r.data.result | ForEach-Object { $_.values | ForEach-Object { $_[1] } }
```

---

## 6. التحديث / الريستارت (بدل IIS Recycle)

مفيش وصول مباشر للسيرفر، والنشر كله من **GitHub Actions**:

- **أي push على فرع `development`** في ريبو السيرفيس ← بيتنشر على dev تلقائياً.
- **ريستارت من غير كود جديد:** GitHub ← الريبو (مثلاً `TAB-ERP/Administration`) ← **Actions** ← **Deploy dev to Hetzner** ← **Run workflow** ← فرع `development` ← **Run workflow**.
  ده بيعيد نشر نفس آخر كود، يعني عملياً ريستارت للـ containers (`admin-api` و`admin-auth`).
- بعد ما يخلص، اتأكد من الاستعلام `|= "Now listening"` إن فيه container جديد اشتغل.

### متى تحتاج ريستارت؟

أي تعديل **يدوي بـ SQL** على جداول OpenIddict (مثل `OpenIddictApplications.Permissions` أو `OpenIddictScopes`) **مش هيبان** غير بعد ريستارت للـ `admin-auth`، لأن السيرفر بيحتفظ بنسخة من الـ clients والـ scopes في الذاكرة.
بعد الريستارت: **تسجيل خروج ودخول** في الفرونت عشان توكن جديد.
