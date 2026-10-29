# دليل endpoints إدارة OpenIddict (الـ Scopes والـ Clients)

بديل آمن للتعديل اليدوي بـ SQL على جداول `OpenIddictApplications` و`OpenIddictScopes`.

**الفرق:** التعديل بـ SQL مش بيبان غير بعد ريستارت للـ AuthServer، لأنه بيحتفظ بنسخة من الـ clients والـ scopes في الذاكرة.
الـ endpoints دي بتعدّل من خلال OpenIddict نفسه جوه الـ AuthServer، فالتعديل **بيشتغل فوراً من غير ريستارت ولا نشر**.

- **الكود:** `Administration/src/TABMS.Adminstration.AuthServer/OpenIddictManagement/OpenIddictManagementController.cs`
- **مكانها:** على دومين الـ **AuthServer** (مش الـ Admin API):

| البيئة | الدومين |
|---|---|
| dev | `https://dev-auth.tab-erp.com` |
| staging | `https://staging-auth.tab-erp.com` |
| prod | `https://auth.tab-erp.com` |

> لو الـ endpoint رجّع 404، يبقى نسخة الـ AuthServer اللي عليها الكود ده لسه ما اتنشرتش على البيئة دي.

---

## 0. الشاشة (الطريقة المعتادة)

**تاب أدمن ← إدارة الدعم الفنى ← إدارة تطبيقات الدخول (OpenIddict)**
(الرابط `tab-admin/openiddict-management/{menuId}`، والكود في `Tab-MS-Front/.../technical-support-admin/openiddict-management/`).

فيها 3 تابات:

| التاب | بتعمل إيه |
|---|---|
| **التطبيقات** | عرض كل الـ clients، وإضافة تطبيق، وتعديله (الروابط، طرق الدخول، الـ scopes، الـ secret، PKCE)، و"تطبيق جديد بنفس الإعدادات" |
| **الـ Scopes** | عرض الـ scopes والـ resources والتطبيقات المربوطة، وإنشاء وتعديل scope، و"ربط بالتطبيقات" لأكتر من تطبيق مرة واحدة |
| **مصفوفة الربط** | جدول تطبيقات × scopes: تعليم خانة يضيف الـ scope فوراً، وشيل العلامة يطلب تأكيد |

- بعد إنشاء scope جديد، شاشة الربط بتفتح لوحدها، لأن الـ scope ما يتستخدمش غير بعد ربطه بتطبيق.
- مفيش حذف لتطبيق أو scope من الشاشة، عن قصد.
- الشاشة بتكلم الـ AuthServer مباشرة (`environment.issuer`)، فالتعديل يسري فوراً.

---

## 1. مين يقدر يستخدمها؟

- **يوزر هوست بس** (من غير tenant). أي يوزر تينانت هياخد **403**.
- وكمان واحد من دول:
  - في role اسمه `admin` (له كل الصلاحيات)، **أو**
  - عنده صلاحية على شاشة `OpenIddictManagement` في تاب أدمن (من شاشة صلاحيات المستخدمين): **دخول** = عرض، **إضافة** = إنشاء تطبيق أو scope، **تعديل** = تعديل وربط وشيل scopes.
- لموظف دعم جديد: اديله الصلاحية على الشاشة من صلاحيات المستخدمين، من غير role `admin`.
- لو هتستخدم الـ API من غير الشاشة، لازم **Bearer token**. الكوكي بتاع صفحة الـ login مش كفاية.

---

## 2. إزاي تجيب التوكن

1. سجّل دخول على الفرونت (مثلاً `dev-app.tab-erp.com`) بيوزر الهوست أدمن.
2. افتح **F12 ← Network**، واختار أي طلب رايح للـ API (مثلاً `GetSystemData`).
3. من **Request Headers** انسخ قيمة `Authorization` (اللي بتبدأ بـ `Bearer eyJ...`).
4. التوكن صالح ساعة. لو رجعلك 401، هات توكن جديد.

> متحطش التوكن في أي ملف داخل الريبو ولا تبعته في شات.

في PowerShell حطه في متغير للجلسة بس:

```powershell
$auth = "https://dev-auth.tab-erp.com/api/openiddict-management"
$h = @{ Authorization = Read-Host 'Paste "Bearer eyJ..."' }
```

---

## 3. الـ Endpoints

| الطريقة | المسار | الوظيفة |
|---|---|---|
| GET | `/clients` | كل التطبيقات بإعداداتها (من غير الـ secret) |
| GET | `/clients/{clientId}` | تطبيق واحد |
| POST | `/clients` | إنشاء تطبيق |
| PUT | `/clients/{clientId}` | تعديل تطبيق (استبدال كامل للإعدادات القابلة للتعديل) |
| GET | `/clients/{clientId}/scopes` | الـ scopes المسموحة للـ client |
| POST | `/clients/{clientId}/scopes/{scope}` | السماح للـ client بـ scope |
| DELETE | `/clients/{clientId}/scopes/{scope}` | شيل scope من الـ client |
| GET | `/scopes` | كل الـ scopes والـ resources بتاعتها |
| POST | `/scopes` | إنشاء scope أو إضافة resources لـ scope موجود |
| PUT | `/scopes/{name}` | تعديل scope (الاسم الظاهر، الوصف، واستبدال الـ resources) |

كل المسارات تبدأ بـ `/api/openiddict-management`.

### شكل جسم التطبيق (POST / PUT `/clients`)

```json
{
  "clientId": "TABMS_Front_Prod",
  "displayName": "TAB Front",
  "clientType": "public",
  "clientSecret": null,
  "consentType": "implicit",
  "clientUri": "https://app.tab-erp.com",
  "requirePkce": false,
  "redirectUris": ["https://dev-app.tab-erp.com"],
  "postLogoutRedirectUris": ["https://dev-app.tab-erp.com"],
  "grantTypes": ["authorization_code", "refresh_token"],
  "scopes": ["Adminstration", "DesktopDashboard"]
}
```

- `clientId` بيتقري في الإنشاء بس. في الـ PUT بيتاخد من المسار.
- `clientSecret` للـ `confidential` بس. في التعديل، لو سبته فاضي بيفضل الـ secret القديم.
- صلاحيات الـ endpoints والـ response types **بتتبني لوحدها** من `grantTypes`، بنفس طريقة الـ data seeder.
- الروابط بتتحفظ **زي ما هي حرفياً**. OpenIddict بيقارنها بالظبط، فـ `https://x.com` و`https://x.com/` اتنين مختلفين.

### عرض scopes الـ client

```powershell
Invoke-RestMethod "$auth/clients/TABMS_Front_Prod/scopes" -Headers $h
```

الرد:

```json
{ "clientId": "TABMS_Front_Prod", "scopes": ["Adminstration", "DesktopDashboard", "GL", "..."] }
```

### السماح للـ client بـ scope

```powershell
Invoke-RestMethod "$auth/clients/TABMS_Front_Prod/scopes/DesktopDashboard" -Method Post -Headers $h
```

- لازم الـ scope يكون موجود الأول، وإلا هيرجع خطأ: `Scope 'X' does not exist. Create it first.`
- لو الـ scope مسموح أصلاً، مفيش حاجة بتتغير (آمن تكرره).

### شيل scope من الـ client

```powershell
Invoke-RestMethod "$auth/clients/TABMS_Front_Prod/scopes/DesktopDashboard" -Method Delete -Headers $h
```

> **خطير:** لو الفرونت لسه بيطلب الـ scope ده في `environment.*.ts`، الـ login هيفشل لكل المستخدمين بـ `invalid_scope`. شيل الـ scope من الفرونت وانشره **الأول**.

### عرض كل الـ scopes

```powershell
Invoke-RestMethod "$auth/scopes" -Headers $h | Format-Table name, displayName, resources
```

### إنشاء scope جديد (أو إضافة resource)

```powershell
$body = @{ name = "Marketing"; displayName = "Marketing API"; resources = @("Marketing") } | ConvertTo-Json
Invoke-RestMethod "$auth/scopes" -Method Post -Headers $h -ContentType "application/json" -Body $body
```

- `resources` = الـ audience اللي الـ API بيتحقق منه (غالباً نفس اسم الـ scope). لو سبتها فاضية، بيتحط اسم الـ scope.
- لو الـ scope موجود، الـ resources الجديدة **بتتضاف** والقديمة **بتفضل**. مفيش مسح، لأن مسح resource يكسر أي API بيعتمد عليه.

### نفس الأوامر بـ curl

```bash
curl -H "Authorization: Bearer eyJ..." https://dev-auth.tab-erp.com/api/openiddict-management/clients/TABMS_Front_Prod/scopes
curl -X POST -H "Authorization: Bearer eyJ..." https://dev-auth.tab-erp.com/api/openiddict-management/clients/TABMS_Front_Prod/scopes/DesktopDashboard
```

---

## 4. سيناريو كامل: إضافة سيستم/API جديد للفرونت

مثال: سيستم جديد اسمه `Marketing`.

1. **أنشئ الـ scope** (لو مش موجود):

   ```powershell
   $body = @{ name = "Marketing"; resources = @("Marketing") } | ConvertTo-Json
   Invoke-RestMethod "$auth/scopes" -Method Post -Headers $h -ContentType "application/json" -Body $body
   ```

2. **اسمح للـ clients بيه:** `TABMS_Front_Prod` (dev / staging / prod) و`TABMS_Front` (اللوكال).

   ```powershell
   foreach ($c in "TABMS_Front_Prod", "TABMS_Front") {
     Invoke-RestMethod "$auth/clients/$c/scopes/Marketing" -Method Post -Headers $h
   }
   ```

3. **اتأكد:**

   ```powershell
   (Invoke-RestMethod "$auth/clients/TABMS_Front_Prod/scopes" -Headers $h).scopes -contains "Marketing"
   ```

4. **بعدها بس** ضيف `Marketing` لـ `scope` في `environment.*.ts` بتاع البيئة وانشر الفرونت.
5. المستخدمين يعملوا **تسجيل خروج ودخول** عشان ياخدوا توكن فيه الـ scope الجديد.

> **الترتيب مهم:** الـ AuthServer الأول، بعدين الفرونت. لو الفرونت طلب scope الـ AuthServer مش عارفه، الـ login بيقع للكل.

---

## 5. الأخطاء المتوقعة

| الرد | السبب |
|---|---|
| 401 | مفيش توكن، أو التوكن انتهى (صلاحيته ساعة) |
| 403 / `Only host users...` | اليوزر تبع تينانت |
| 403 / `You do not have permission...` | اليوزر هوست، بس مش في role `admin` وما عندوش الصلاحية المطلوبة على شاشة `OpenIddictManagement` |
| 404 | الـ AuthServer على البيئة دي لسه ما اتنشرش بالنسخة اللي فيها الـ endpoints، أو المسار غلط |
| `Client 'X' was not found.` | اسم الـ client غلط (حساس للحروف: `TABMS_Front_Prod`) |
| `Scope 'X' does not exist. Create it first.` | أنشئ الـ scope بـ `POST /scopes` الأول |

---

## 6. ملاحظات

- **وقت النشر** ممكن يبقى فيه نسختين AuthServer شغالين لثواني (مثلاً `dev-admin-auth-12` و`-13`). اعمل التعديل بعد ما النشر يخلص، عشان ما يروحش للنسخة القديمة.
- **كل تعديل بيتسجل في اللوج** باسم اليوزر اللي عمله. تقدر تراجعه من Grafana (راجع `LOGS-GUIDE-HETZNER.md`):

  ```
  {container=~"dev-admin-auth.*"} |= "OpenIddict"
  ```

- **التعديل اليدوي بـ SQL** لسه ممكن، بس لازم بعده ريستارت للـ AuthServer (GitHub Actions ← Run workflow).
