# مقترح تعديلات Inventory لدعم POS (مواصفات فقط — لا تعديل في مستودع Inventory)

الحالة: مقترح للمراجعة. كل ما يلي مبني على قراءة الكود الحالي في
`Tab-MS Back-end/Inventory/modules/ModuleInventory`.

## 0. ملخص ما وجدناه في الكود الحالي

| الموضوع | الوضع الحالي | الأثر على POS |
|---|---|---|
| الباركود | لا يوجد أي حقل Barcode في `InvItems` أو `InvItemOtherUnits` | POS يبحث حاليًا بـ `ItemCode` فقط؛ قارئ الباركود لا يعمل مع أكواد المورد (EAN) |
| سعر المخزن | `InvItemStore.Price` نوعه `float` | أخطاء تقريب في المبالغ؛ يجب أن يكون `decimal(18,3)` مثل `TrxInvF` |
| رصيد الصنف | لا يوجد endpoint رصيد لكل مخزن | POS لا يستطيع التحذير من البيع بدون رصيد |
| التحديث التزايدي | `BaseEntity` فيه `LastModificationTime` و `IsDeleted` لكن لا يوجد فلتر عليهما | POS يعيد تحميل كل الأصناف في كل مرة |
| إنشاء حركة | `TrxInvH/Create` يعمل `InsertAsync` للرأس؛ الرقم `TrxSerial` يُجلب مسبقًا عبر `GetMaxSerial` | سباق على الرقم عند تزامن أكثر من مصدر، ولا توجد حماية من التكرار |
| الربط بالمصدر | `MyKey` (Guid) و `MySource` (string) موجودان | ممتازان كمفتاح idempotency — يُعاد استخدامهما بدل إضافة أعمدة جديدة |

## 1. باركود الأصناف — `InvItemBarcodes` (جدول جديد)

صنف واحد له أكثر من باركود، وكل باركود مرتبط بوحدة (علبة/كرتون).

```text
InvItemBarcodes : BaseEntity, IMultiTenant
  TenantId   Guid?
  ItemId     Guid        (FK InvItems)
  UnitId     Guid?       (FK InvUnits; null = الوحدة الرئيسية)
  Barcode    string(50)  NOT NULL
  IsPrimary  bool
Unique index: (TenantId, Barcode) WHERE IsDeleted = false
```

Endpoints (بنفس نمط `api/v1/[controller]/[action]`):

- `InvItemBarcodes/GetByItem?itemId=` — قائمة.
- `InvItemBarcodes/Find?barcode=` — يرجع `{ itemId, unitId, factor }`.
- CRUD قياسي.

لماذا جدول وليس عمود في `InvItems`: الأصناف المستوردة لها أكثر من EAN، والكرتون له باركود مختلف عن الحبة.

## 2. رصيد الصنف في المخزن

```text
GET InvItemStore/GetBalances?storeId=&itemIds=&modifiedSince=
→ [{ itemId, storeId, unitId, qtyOnHand, lastMovementAt }]
```

- الحساب من `TrxInvF` حسب اتجاه `TrxtypeConfig` (وارد/صادر)، **مع** الحركات غير المرحّلة من POS
  (انظر البند 4) حتى لا يظهر الرصيد أعلى من الحقيقة.
- POS يستخدمه للتحذير فقط (سياسة مقترحة تُضاف للكتالوج لاحقًا: `NEGATIVE_STOCK_MODE` = Allow/Warn/Block)، ولا يعتمد عليه
  أوفلاين.

## 3. التحديث التزايدي (Delta)

إضافة `modifiedSince` (DateTime?) و `includeDeleted` (bool) إلى الـ endpoints التالية:

- `InvItems/GetAllData`
- `InvItemStore/GetAllData`
- `InvItemOtherUnits/GetAllData`
- `InvItemBarcodes/GetAllData` (الجديد)

```csharp
query = query
  .WhereIf(modifiedSince.HasValue,
      x => (x.LastModificationTime ?? x.CreationTime) > modifiedSince)
  .IgnoreSoftDeleteIf(includeDeleted);   // عبر IDataFilter<ISoftDelete>
```

الرد يحمل `serverTime` حتى يخزنه الجهاز كنقطة البداية التالية. هذا لا يتطلب
تغيير schema، والأعمدة موجودة أصلًا.

## 4. ترحيل مبيعات POS إلى المخزون — دفعة لكل وردية/مخزن

القرار المعتمد: **دفعة (batch)** وليس حركة لكل فاتورة.

### 4.1 في POS (سيُنفذ في POS لاحقًا، ليس في Inventory)

```text
PosInventoryPostingBatch
  Id, TenantId, BranchId, StoreId, ShiftId
  Status: Pending | Posted | Failed
  TrxInvHId (Guid?)   ← يُملأ بعد الترحيل
  LinesHash, Attempts, LastError, PostedAt
```

عند إغلاق الوردية تُجمع السطور لكل (صنف، وحدة، مخزن):
- المبيعات بالسالب.
- المرتجعات بالموجب، في حركة منفصلة بنوع مختلف.

### 4.2 المطلوب من Inventory: `TrxInvH/CreateFromExternal` (endpoint جديد)

```text
POST TrxInvH/CreateFromExternal
{
  myKey:  <BatchId>,          // idempotency
  mySource: "POS",
  trxTypeConfigId, branchId, storeId, trxDate, notes,
  lines: [{ lineNum, itemId, unitId, factor, quantity, price, taxValue, net }]
}
→ { trxInvHId, trxSerial, alreadyExisted }
```

- **ذري**: الرأس والسطور في `SaveChanges` واحد، داخل UoW transactional.
- **Idempotent**: يُضاف unique index جزئي على `(TenantId, MySource, MyKey) WHERE MyKey IS NOT NULL`.
  إذا وُجد سجل بنفس المفتاح يُرجَع كما هو مع `alreadyExisted = true`، ولا يُنشأ سجل ثانٍ.
- **الرقم يُولَّد على الخادم** داخل نفس المعاملة. البديل الحالي (`GetMaxSerial` ثم `Create`)
  فيه سباق؛ الأصح sequence لكل (Tenant, TrxTypeConfig, Year) أو `SELECT … FOR UPDATE`.
- `AutoGeneration = true` لتمييز الحركات الآلية في الشاشات.

### 4.3 أنواع الحركات المطلوبة في `TrxtypeConfig`

| الكود المقترح | الاستخدام | الاتجاه |
|---|---|---|
| `POS_SALE` | صرف مبيعات نقطة البيع | صادر |
| `POS_RETURN` | مرتجع مبيعات نقطة البيع | وارد |

تُعرّف كبيانات إعداد (seed) لكل tenant، ويُقرأ الـ Id في POS من سياستين مقترحتين
`INVENTORY_SALE_TRX_TYPE` / `INVENTORY_RETURN_TRX_TYPE` (تُضافان للكتالوج مع تنفيذ الترحيل) بدل تثبيته في الكود.

## 5. تصحيحات صغيرة مقترحة

1. `InvItemStore.Price`: من `float?` إلى `decimal?` بـ `decimal(18,3)`، مع migration تحويل.
2. `TrxInvH/Create` الحالي: يُفضّل أن يستخدم نفس مسار الإنشاء الذري أعلاه، حتى لا تبقى
   حركات برأس بلا سطور عند فشل الطلب الثاني.
3. `MySource.Contains(...)` في الفلتر يجب أن يكون مساواة `==`، لأن `"POS"` تطابق أيضًا `"POS_RETURN"`.

## 6. ترتيب التنفيذ المقترح

1. Delta (البند 3). لا تغيير في الـ schema، وأثره مباشر على زمن فتح POS.
2. `CreateFromExternal` مع index الـ idempotency (البند 4.2)، وهو شرط للترحيل.
3. الباركود (البند 1).
4. الأرصدة (البند 2).
5. تصحيح نوع السعر (البند 5.1)، ويحتاج تنسيقًا مع شاشات Inventory.
