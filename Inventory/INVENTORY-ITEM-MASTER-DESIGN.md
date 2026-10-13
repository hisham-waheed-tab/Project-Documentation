# تصميم بيانات الصنف (Item Master) — ما تم تنفيذه

الحالة: منفذ على `Dev-TABMS.Inventory` (migrations: `Item_Master_Redesign`, `TrxInvF_VariantId`).
ملف الإكسيل `TAB_Item_Master_Tables_Examples.xlsx` استرشادي وليس ملزمًا حرفيًا.

## 1. الأكواد

- كل أكواد الأكواد الأساسية (`ItemCode`, `UnitCode`, `StoreCode`, `ItemGroupCode`, `ItemSubGroupCode`, `ItemClassCode`) أصبحت `string`.
- التفرد يُفحص في الـ AppService (`EnsureCodeIsUniqueAsync`) ومحمي بـ unique index مفلتر على `isdeleted = false`:
  - على مستوى الـ tenant: الأصناف، الوحدات، التصنيفات، المجموعات، الماركات، قوائم الأسعار، الأبعاد.
  - المجموعة الفرعية: داخل المجموعة. المخزن: داخل الفرع.

## 2. الوحدات (بدون تغيير في اللوجيك القديم)

- `InvItems.MainUnitId` = الوحدة الأساسية (وحدة الرصيد).
- `InvItemOtherUnits` = الوحدات الأخرى للصنف: `ToUnitId`, `UnitFactor` (أصبح `decimal(19,6)`), `MainUnitIsGreater`.
- التحويل للوحدة الأساسية (نفس منطق الفرونت `trx-inv-f-line-logic.service.ts`):
  `MainUnitIsGreater ? qty / UnitFactor : qty * UnitFactor` — متاح في `InvUnitConversion`.
- إضافات:
  - `InvUnits.DecimalPlaces` (0..6).
  - `InvItemOtherUnits.AllowSale`, `AllowPurchase` (افتراضي true).
  - `InvItems.DefaultSalesUnitId`, `DefaultPurchaseUnitId`: لازم تكون الوحدة الأساسية أو وحدة أخرى للصنف مسموح لها بالبيع/الشراء.
- قواعد `InvItemOtherUnits`: الصنف والوحدة إجباريان، المعامل > 0، لا تُضاف الوحدة الأساسية كوحدة أخرى، لا تكرار للوحدة في نفس الصنف.
- تم حذف `InvItemUnits` (كان تكرارًا لدور `InvItemOtherUnits`).

## 3. الـ Variants (SKU)

- كل صنف له variant افتراضي واحد (`CombinationKey = 'DEFAULT'`, `IsDefault = true`) كوده = كود الصنف.
- يُنشأ تلقائيًا عند إنشاء الصنف (Create و CreateBulkData)، ويتزامن كوده واسمه وحالته مع الصنف عند التعديل (`InvDefaultVariant`).
- الأصناف القديمة أخذت variant افتراضي في migration `Item_Master_Redesign`.

## 4. الباركود — `InvItemBarcodes`

- API: `InvItemBarcodes/GetByItem?itemId=`, `GetAllData?modifiedSince=`, `Find?barcode=`, `Create`, `Update?id=`, `Delete?id=`.
- القواعد:
  - الباركود إجباري، حد أقصى 100 حرف، فريد على مستوى الـ tenant.
  - الوحدة = الوحدة الأساسية للصنف أو إحدى وحداته الأخرى.
  - `VariantId` فارغ = الـ variant الافتراضي.
  - أول باركود لنفس (variant, unit) يصبح أساسيًا تلقائيًا، وتعيين باركود أساسي يلغي الأساسي السابق.
- الحماية: لا يمكن حذف وحدة أخرى أو تغييرها، ولا تغيير الوحدة الأساسية للصنف، طالما عليها باركود.
- شاشة الصنف (Angular): قسم "باركود الصنف" أسفل الشاشة، يظهر بعد حفظ الصنف.
- POS Desktop: الكتالوج يحمل باركودات **الوحدة الأساسية** فقط؛ المسح/البحث يطابق أي باركود منها أو كود الصنف.
  باركودات الوحدات الأخرى (كرتونة مثلاً) لا تُباع من الـ POS حاليًا لأن السلة بالوحدة الأساسية فقط.

## 5. حركات المخزون — `TrxInvF.VariantId`

- عمود جديد nullable مع FK على `InvItemVariants`.
- عند الحفظ، أي سطر بدون `VariantId` يأخذ الـ variant الافتراضي للصنف تلقائيًا (في `ModuleInventoryDbContext.SaveChanges`)،
  ولو تغيّر صنف السطر يُعاد تحديد الـ variant. حسابات `Factor` و `MainUnitIsGreater` لم تتغير.

## 6. حقول الشاشات (TABFieldDictionary)

السكربت [`sql/inventory-item-units-field-dictionary.sql`](sql/inventory-item-units-field-dictionary.sql) (idempotent) يضيف حقول:
`allowsale`, `allowpurchase`, `defaultsalesunitid`, `defaultpurchaseunitid`, `decimalplaces`.
نُفذ على `Dev-TABMS.Administration`، ويجب تنفيذه على أي بيئة أخرى.

## 7. ملاحظات مفتوحة

- الصنف كود `3` (صنف3) بدون وحدة أساسية — يحتاج تصحيح من الشاشة.
- عند النشر على بيئة أخرى: تطبيق الـ migrations بالترتيب ثم سكربت الـ field dictionary.
