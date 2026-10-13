# خطة المرحلة 2 — صلاحيات طاقم نقطة البيع (PosStaff)

> الحالة: **خطة فقط، لم تُنفَّذ**. المرحلة 1 (منفّذة): نقل الاعتماد إلى كنترولر `PosApproval` وفحص صلاحية الكاشير حسب نوع الاعتماد ([POS-SUPERVISOR-PERMISSION.md](POS-SUPERVISOR-PERMISSION.md)).

## المشكلة الحالية

- الأدوار في POS قائمة على «شاشات وهمية» في `TABSystemMenu`: `PosCashier` و`PosSupervisor` و`PosDeviceSync`، وأسماؤها ثابتة في الكود (`PosApproverDirectory.SupervisorEntity` / `DeviceSyncEntity`).
- المشرف نعم/لا فقط: أي مشرف يعتمد أي نوع وأي مبلغ، ولا يوجد دور «مدير» فعلي.
- أدوار `TABUserRoles` على مستوى الشركة، فلا يمكن أن يكون الشخص مشرفًا في فرع وكاشيرًا في فرع آخر.
- السياسات (`PosPolicyValue`) تُحسب للكاشير فقط، وليس للمعتمِد.
- لا يوجد منع لأن يعتمد الشخص عمليته بنفسه.

## التصميم المقترح

مجموعات صلاحيات POS **بيانات قابلة للتعديل** (وليست Enum أدوار)، وتعيين الطاقم لكل فرع.

### الجداول (قاعدة POS)

| الجدول | الحقول الأساسية | الغرض |
|---|---|---|
| `PosPermissionGroup` | `Code`، `AraName`، `LatName`، `IsActive` | مجموعة صلاحيات (كاشير، مشرف، مدير… يعرّفها العميل) |
| `PosPermissionGroupRight` | `GroupId` (FK)، `Right` (Enum)، `Allowed`، `MaxAmount`، `MaxPercent` | صلاحية واحدة داخل المجموعة مع حدودها |
| `PosStaff` | `UserId`، `BranchId`، `TerminalId` (اختياري)، `GroupId` (FK)، `IsActive`، `ValidFrom`، `ValidTo` | تعيين المستخدم على فرع/نقطة بمجموعة |

- مفتاح منطقي: (`UserId`، `BranchId`، `TerminalId`) لا يتكرر وهو نشط.
- الحقول المشتركة (Id، TenantId، حقول التدقيق) كالمعتاد.

### قائمة الصلاحيات (`PosRight` — الشيء الوحيد الثابت في الكود)

| المجموعة | الصلاحيات |
|---|---|
| تشغيل | `Sell`، `Return`، `Exchange`، `OpenShift`، `CloseShift`، `CashIn`، `CashOut`، `OpenDrawer`، `HoldSale` |
| اعتماد | `ApproveLineDiscount`، `ApproveInvoiceDiscount`، `ApprovePriceOverride`، `ApproveNegativeStock`، `ApproveReturnOverride`، `ApproveCashDifference`، `ApproveVoidSale`، `ApproveDeleteHeldSale`، `ApproveReprint`، `ApproveCashOut`، `ApproveLineDelete`، `ApproveLineEdit`، `ApproveOther` |
| أخرى | `SyncOthersWork` (بديل `PosDeviceSync`)، `ViewXReport`، `TrainingMode` |

- `MaxAmount` / `MaxPercent` تُستخدم لصلاحيات الاعتماد (مثل: مشرف يعتمد خصمًا حتى 20% وسحبًا حتى 1000).
- قاعدة ثابتة: **المعتمِد ≠ صاحب الطلب**.

### القواعد

1. **صلاحيات الويب (Back-office)** تبقى كما هي (قوائم + Entities) مثل باقي النظام.
2. **عمليات الجهاز**: الكاشير يحتاج `PosStaff` نشط على فرع النقطة + الصلاحية المطلوبة.
3. **الاعتماد**: المعتمِد له `PosStaff` نشط على نفس الفرع + `Approve<Type>` + المبلغ/النسبة ضمن حده + PIN صحيح.
4. **السياسات** تبقى لسلوك النقطة/الفرع (Deny / ManagerPin / Allow وقواعد الأوفلاين)، والحدود تأتي من مجموعة المعتمِد.

## التغييرات

### Backend (TABMS.POS)

- Entities + DbContext + Migration للجداول الثلاثة (تُطبَّق على القاعدة بعد المراجعة).
- خدمات CRUD: `PosPermissionGroupAppService` (هيدر + فوتر الصلاحيات) و`PosStaffAppService`.
- `PosStaffDirectory` بدل `PosApproverDirectory.IsSupervisorAsync` / `HasEntityCreateGrantAsync`.
- `PosAccessGuard`: كنترولرات الجهاز (`PosCheckout`، `PosShift`، `PosCashDrawer`، `PosReturnCheckout`، `PosApproval`) تتحقق من `PosStaff` + الصلاحية بدل منح الكيانات.
- `PosApprovalService`: فحص `Approve<Type>` والحد ومنع الاعتماد الذاتي، وحفظ لقطة الصلاحية في السجل.
- `GetApprovers` يُرجع لكل مشرف صلاحياته وحدوده. نقطة جديدة `PosStaff/GetMyRights?terminalId=`.
- `PosActorGuard`: `SyncOthersWork` بدل `PosDeviceSync`.
- `PosTenantSetup`: زرع مجموعات افتراضية (كاشير / مشرف / مدير) كبيانات قابلة للتعديل.

### الترحيل (مرة واحدة)

- كل من لديه `Adminstration.Entities.PosSupervisor.Create` (مستخدم أو دور) + فرع في `TABUserBranches` ← صف `PosStaff` بمجموعة «مشرف» لكل فرع.
- كل من لديه صلاحيات `PosCashier` ← صف `PosStaff` بمجموعة «كاشير».
- من لديه `PosDeviceSync` ← يُضاف `SyncOthersWork` لمجموعته أو مجموعة «مدير».
- `PosTenantSetup/MigrateStaff` بخيار `dryRun` يعرض التقرير قبل الحفظ.
- فترة انتقالية: الفحص القديم والجديد معًا خلف سياسة/إعداد، ثم إزالة القديم.

### Administration / Tab-MS-Front

- قوائم جديدة في `PosWebMenusDataSeedContributor`: `PosPermissionGroup` و`PosStaff`.
- شاشة **مجموعات الصلاحيات**: هيدر + جريد صلاحيات (مسموح / حد مبلغ / حد نسبة).
- شاشة **طاقم نقطة البيع**: المستخدم، الفرع، النقطة (اختياري)، المجموعة، التواريخ، نشط — مع إمكانية دمج إدارة PIN فيها.
- بعد الترحيل: إخفاء/إزالة `PosSupervisor` و`PosDeviceSync` و`PosCashier`.

### Desktop (Tab-MS-POS-Desktop)

- جلب `GetMyRights` عند فتح الوردية وحفظه للأوفلاين، وإخفاء/تعطيل الأزرار حسب الصلاحيات.
- كاش المشرفين يحمل الصلاحيات والحدود؛ نافذة الاعتماد تعرض فقط من يستطيع اعتماد هذا النوع وهذا المبلغ.
- `offlineVerify`: فحص الحد ومنع الاعتماد الذاتي.
- رسائل واضحة عند الرفض (مكتمل جزئيًا في المرحلة 1).

## ترتيب التنفيذ

1. Enum `PosRight` + الجداول + Migration + خدمات CRUD.
2. شاشتا الويب + القوائم.
3. `PosStaffDirectory` + `GetMyRights` + `GetApprovers` بالحدود (مع بقاء الفحص القديم).
4. الترحيل (`dryRun` ثم تنفيذ) ومراجعة التقرير.
5. تحديث الديسكتوب (الصلاحيات، فلترة المشرفين، الحدود أوفلاين).
6. تفعيل `PosAccessGuard` وفحص الحدود على السيرفر.
7. إزالة الفحص القديم والشاشات الوهمية وتحديث الوثائق.

## المخاطر

- **أوفلاين:** صلاحيات قديمة على الجهاز حتى المزامنة التالية؛ يُحدَّث عند فتح الوردية وكل دقيقتين.
- **الترحيل:** مستخدمون بلا فرع لن يُرحَّلوا؛ تقرير `dryRun` يوضح ذلك.
- **مصدر حقيقة مزدوج** في الفترة الانتقالية؛ تُحدد مدتها مسبقًا.
