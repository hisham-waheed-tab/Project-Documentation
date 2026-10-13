# صلاحية مشرف POS (`PosSupervisor`)

## ما الذي يجعل المستخدم مشرفًا؟

يجب أن يتحقق **الثلاثة معًا**:

1. له **رمز PIN** في جدول `PosUserPin` (قاعدة POS).
2. مرتبط بالفرع في `TABUserBranches` (قاعدة Administration) — أو يكون مدير الـ tenant.
3. له صلاحية **إنشاء** الكيان `PosSupervisor` في `AbpPermissionGrants` (قاعدة Administration).

اسم الصلاحية الحرفي (لاحظ الإملاء `Adminstration` بدون i):

```text
Adminstration.Entities.PosSupervisor.Create
```

(يقبل النظام أيضًا المكافئ `Adminstration.Menu.PosSupervisor.Create`)

---

## الجداول المعنية

| قاعدة البيانات | الجدول | الدور |
|---|---|---|
| **Administration** | `AbpPermissionGrants` | المنح الفعلي الذي يقرأه POS عند بناء قائمة المشرفين |
| **Administration** | `TABSystemMenu` | تعريف الصفحة/الكيان في القائمة (`MenuKey` = `PosSupervisor`) |
| **Administration** | `TABUserPermission` | منح للمستخدم عبر واجهة الأدوار/المستخدمين (Access / Insert / …) |
| **Administration** | `TABTenantRolePermission` | منح للدور ثم يُنسخ إلى ABP |
| **Administration** | `TABUserBranches` | يجب أن يكون المستخدم على فرع نقطة البيع |
| **POS** | `PosUserPin` | هاش الـ PIN + الاسم الظاهر |

بعد تعديل `TABUserPermission` أو صلاحيات الدور، نفّذ من Admin:

```http
POST …/api/v1/TABUserPermission/SyncAbpPermissionGrants
```

أو الإجراء المخزّن: `CALL public.sp_sync_tabuserpermission_abp_grants(false);`

---

## الطريقة 1 — من واجهة Admin (المفضلة)

عنصرا القائمة موجودان في الـ seed (`PosWebMenusDataSeedContributor`) وفي قاعدة Dev تحت «إعدادات نقطة البيع»:

| MenuKey | الاسم | النوع | الغرض |
|---|---|---|---|
| `PosSupervisor` | مشرف نقطة البيع | صلاحية فقط (بلا صفحة) — إدراج فقط | منح **إدراج** = يصبح المستخدم مشرف اعتماد |
| `PosUserPin` | رموز PIN للمشرفين | صفحة `pos-system/pos-user-pin` | إدارة رموز المستخدمين الآخرين |

1. امنح المستخدم أو الدور صلاحية **إدراج (Insert)** على «مشرف نقطة البيع».
2. شغّل **مزامنة صلاحيات ABP** (`SyncAbpPermissionGrants`).
3. تأكد أن المستخدم مربوط بفرع نقطة البيع.
4. عيّن له PIN من إحدى الطريقتين:
   - الويب: **رموز PIN للمشرفين** → «تعيين رمز» (يحتاج من يفتح الشاشة: وصول + تعديل على `PosUserPin`، وحذف لتعطيل الرموز).
   - الكاشير: أدوات الكاشير → عيّن PIN (المستخدم لنفسه).

### شاشة «رموز PIN للمشرفين»

- تعرض كل مستخدمي الشركة مع فلتر الفرع والبحث، وشارات: الرمز (مفعّل / معطّل / لا يوجد)، مقفول حتى، عدد المحاولات الخاطئة، **مشرف / ليس مشرفًا**.
- «ليس مشرفًا» تعني أن صلاحية `PosSupervisor` ناقصة؛ الرمز يُحفظ لكنه لا يظهر في قائمة الاعتماد.
- **فك القفل** يصفّر المحاولات الخاطئة على السيرفر. القفل **المحلي** على جهاز غير متصل (15 دقيقة، لكل جهاز) لا يُفك من السيرفر.
- **التعطيل** يُبقي الصف (للتدقيق) ويجعل `IsActive = false`؛ يختفي الرمز من الأجهزة مع المزامنة التالية.
- API (كنترولر `PosUserPin` في POS):

| الإجراء | HTTP | الصلاحية |
|---|---|---|
| `GetList?branchId=&filter=` | GET | وصول |
| `SetPin` `{userid, pin, displayname}` | PUT | تعديل |
| `Unlock` `{userid}` | PUT | تعديل |
| `Disable?userId=` | DELETE | حذف |
| `DisableOfflinePin?userId=` | DELETE | حذف (رمز الدخول بدون اتصال؛ المستخدم يعيّن رمزًا جديدًا بعدها) |

قواعد الرمز (نفسها في الويب والسيرفر والكاشير): أرقام فقط 6–8، ليس رقمًا مكررًا، ليس متتاليًا (123456 / 654321).

> مدير الـ tenant (البريد في خاصية `AdminMail` للمستأجر) يُعتبر مشرفًا تلقائيًا بعد تعيين PIN، دون صف في `AbpPermissionGrants`.

---

## الطريقة 2 — SQL مباشر على Administration

استبدل `:user_id` و `:tenant_id` بقيم حقيقية.

```sql
-- منح Create لمستخدم (ProviderName = 'U', ProviderKey = IdentityUserId)
INSERT INTO "AbpPermissionGrants" ("Id", "TenantId", "Name", "ProviderName", "ProviderKey")
SELECT gen_random_uuid(), :tenant_id::uuid,
       'Adminstration.Entities.PosSupervisor.Create',
       'U',
       :user_id::text
WHERE NOT EXISTS (
  SELECT 1 FROM "AbpPermissionGrants" g
  WHERE g."Name" = 'Adminstration.Entities.PosSupervisor.Create'
    AND g."ProviderName" = 'U'
    AND g."ProviderKey" = :user_id::text
    AND (g."TenantId" IS NOT DISTINCT FROM :tenant_id::uuid)
);
```

منح لدور (مفتاح الدور غالبًا `TABTenantRole.Id` كنص، أو اسم دور ABP حسب إعدادكم):

```sql
INSERT INTO "AbpPermissionGrants" ("Id", "TenantId", "Name", "ProviderName", "ProviderKey")
SELECT gen_random_uuid(), :tenant_id::uuid,
       'Adminstration.Entities.PosSupervisor.Create',
       'R',
       :role_key::text
WHERE NOT EXISTS (
  SELECT 1 FROM "AbpPermissionGrants" g
  WHERE g."Name" = 'Adminstration.Entities.PosSupervisor.Create'
    AND g."ProviderName" = 'R'
    AND g."ProviderKey" = :role_key::text
    AND (g."TenantId" IS NOT DISTINCT FROM :tenant_id::uuid)
);
```

التحقق:

```sql
SELECT * FROM "AbpPermissionGrants"
WHERE "Name" ILIKE '%PosSupervisor%';
```

ثم من الكاشير: عيّن PIN → أعد فتح شاشة الاعتماد / انتظر مزامنة قائمة المشرفين.

---

## نقاط الاعتماد (API) وصلاحية الكاشير

كنترولر مستقل `PosApproval` (`PosApprovalAppService`) بدل `PosCheckout`، كلها POST:

| الإجراء | الوظيفة |
|---|---|
| `PosApproval/GetApprovers` | قائمة مشرفي فرع نقطة البيع (مع hash الرمز للتحقق أوفلاين) |
| `PosApproval/VerifyApproval` | التحقق من رمز المشرف وتسجيل الموافقة |
| `PosApproval/LogOfflineApprovals` | رفع الموافقات التي تمت بدون اتصال (من الـ outbox) |

- الفلتر العام (`TabEntityAuthorizationFilter`) أصبح مطابقًا لـ HR تمامًا (بلا قوائم استثناء). الاستثناء يتم بالـ attribute `[TabSkipEntityAuthorization]` على الخدمة نفسها (موجود في `TABMS.POS.Application.Contracts/Authorization`):
  - `PosApprovalAppService` على مستوى الكلاس (لا يُطلب `PosApproval.Create`).
  - `PosSupervisorAppService`: `SetMyPin` و`GetMyPinStatus` و`SetMyOfflinePin` و`GetMyOfflinePinStatus` و`GetMyOfflineCredential`.
  - `PosPolicyAppService.GetEffective`.
  - الدخول ما زال مطلوبًا لهذه الأكشنات (`[Authorize]` على `BaseAppService`)؛ الـ attribute يتجاوز فحص صلاحية الكيان فقط.
- الكاشير (صاحب التوكن) يحتاج صلاحية **العملية نفسها** حسب نوع الاعتماد:

| نوع الاعتماد | الصلاحية المطلوبة من الكاشير (أي واحدة) |
|---|---|
| CashOut (10) | `PosCashDrawer.Create` |
| CashDifference (6) | `PosCashDrawer.Create` أو `PosShift.Create` |
| ReturnOverride (5) | `PosReturnCheckout.Create` |
| Other (99) — يُستخدم للإيداع النقدي | `PosCheckout.Create` أو `PosCashDrawer.Create` |
| باقي الأنواع (خصم، سعر، إلغاء، حذف/تعديل سطر، إعادة طباعة، حذف معلّقة، رصيد سالب) | `PosCheckout.Create` |

- `GetApprovers` يكفيه أي صلاحية من الجدول. `LogOfflineApprovals` يفحص كل الأنواع في الدفعة قبل الحفظ.
- الرفض: HTTP 403 برسالة «حسابك ليس لديه صلاحية تنفيذ هذه العملية (اسم الصلاحية)» وكود `POS:PermissionRequired`.
- التحقق من **المشرف** لم يتغير: PIN + الفرع + `PosSupervisor.Create` + القفل بعد 5 محاولات + السجل.
- الأسماء الكاملة تبدأ بـ `Adminstration.Entities.` (مثل `Adminstration.Entities.PosCashDrawer.Create`). تُمنح بإضافة الكيان إلى `RelatedEntities` لقائمة `PosCashier` في Pages-Settings ثم إعادة حفظ صلاحية الدور (Access + Insert).
- الديسكتوب: عند 403 من `GetApprovers` تُمسح قائمة المشرفين المحفوظة وتظهر رسالة في نافذة الاعتماد، وعند 401 تبقى القائمة مع تنبيه أنها غير مؤكدة.

---

## ملاحظات

- تعيين PIN (`SetMyPin`) أصبح متاحًا لأي مستخدم مسجّل دخولًا؛ **الظهور في قائمة الاعتماد** ما زال يتطلب الصلاحية أعلاه.
- جدول `PosUserPin` فيه نوعان (`Purpose`): 1 مشرف و2 دخول بدون اتصال. الاعتماد ومزامنة الرموز للأجهزة تستخدم النوع 1 فقط. ([الدخول بدون اتصال](POS-DESKTOP-SECURITY.md))
- جدول `PosUserPin` في **POS** وليس Administration — لا تخلط القاعدتين.

---

## صلاحية مزامنة الجهاز (`PosDeviceSync`)

- عنصر صلاحية فقط (بدون صفحة) تحت «إعدادات نقطة البيع»: **مزامنة جهاز نقطة البيع** (`MenuKey = PosDeviceSync`).
- الاسم الحرفي: `Adminstration.Entities.PosDeviceSync.Create` (أو المكافئ `Adminstration.Menu.PosDeviceSync.Create`).
- من يملكها (مثل المدير) يستطيع رفع عمليات الجهاز المسجّلة باسم مستخدم آخر. التفاصيل في [POS-DESKTOP-SECURITY.md](POS-DESKTOP-SECURITY.md).
- المنح والتحقق بنفس طريقة `PosSupervisor` أعلاه (استبدل الاسم في SQL)، ومدير الـ tenant يملكها تلقائيًا.
- عنصر القائمة عام على مستوى الـ Host (`TenantId = null`) ويأتي من `PosWebMenusDataSeedContributor`، لذلك لا تضيفه `PosTenantSetup/SyncMissing` (هي خاصة ببيانات التينانت الحالي فقط). مدير الـ tenant لا يحتاج منحًا.