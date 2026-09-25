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

## ملاحظات

- تعيين PIN (`SetMyPin`) أصبح متاحًا لأي مستخدم مسجّل دخولًا؛ **الظهور في قائمة الاعتماد** ما زال يتطلب الصلاحية أعلاه.
- جدول `PosUserPin` في **POS** وليس Administration — لا تخلط القاعدتين.
