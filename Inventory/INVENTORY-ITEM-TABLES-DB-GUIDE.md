# دليل جداول تكويد الصنف — Inventory (لفريق قواعد البيانات)

- قاعدة البيانات: `TABMS.Inventory` (بيئة التطوير: `Dev-TABMS.Inventory`) — PostgreSQL.
- آخر migration: `20261013104040_TrxtypeConfig_SystemUsage`.
- الربط مع نقطة البيع (الكتالوج والترحيل): [../POS/POS-INVENTORY-INTEGRATION.md](../POS/POS-INVENTORY-INTEGRATION.md).
- الملف ده بيوصف الجداول كما هي في الكود والداتابيز الآن. للتصميم والقرارات راجع [INVENTORY-ITEM-MASTER-DESIGN.md](INVENTORY-ITEM-MASTER-DESIGN.md).

---

## 0. قواعد عامة لازم تتعرف قبل أي query

### 0.1 التسمية
- أسماء الجداول **PascalCase بين علامتي تنصيص**: `"InvItems"`، `"InvItemOtherUnits"`.
- أسماء الأعمدة **lowercase**: `itemcode`, `mainunitid`, `isdeleted`.
- مثال: `SELECT itemcode FROM "InvItems" WHERE isdeleted = false;`

### 0.2 الأعمدة المشتركة في كل الجداول (BaseEntity)

| العمود | النوع | الشرح |
|---|---|---|
| `id` | uuid | المفتاح الأساسي. كل العلاقات Guid. |
| `tenantid` | uuid null | الشركة (Multi-Tenant). **أي query لازم يتفلتر بيه.** null = بيانات Host. |
| `isdeleted` | bool | حذف منطقي (Soft delete). الصف المحذوف بيفضل في الجدول. **لازم `isdeleted = false` في أي تقرير.** |
| `deletiontime`, `deleterid` | | وقت ومين حذف. |
| `creationtime`, `creatorid` | | وقت ومين أنشأ. |
| `lastmodificationtime`, `lastmodifierid` | | آخر تعديل. يُستخدم للمزامنة التزايدية (POS). |
| `notactive` | bool null | الصف موقوف (موجود لكن لا يُستخدم في حركات جديدة). null = نشط. |
| `draft`, `reviewed`, `posted`, `createjournal`, `wfstatues` | | حقول Workflow عامة، غير مستخدمة في جداول التكويد غالبًا. |

### 0.3 الـ Unique indexes "مفلترة"
كل قيود التفرد معمولة كـ partial index بشرط `WHERE isdeleted = false`،
يعني ينفع يتكرر الكود لو الصف القديم محذوف منطقيًا. بعض القيود فيها كمان `coalesce(notactive,false) = false`.

### 0.4 الحذف
كل الـ FKs على جداول الصنف `ON DELETE RESTRICT` (أو NO ACTION) — مفيش Cascade.
الحذف من التطبيق منطقي دائمًا؛ **ممنوع DELETE فعلي من الداتابيز** على جداول عليها حركات.

### 0.5 علاقات بدون FK فعلي
بعض الأعمدة بتشاور على جداول في قواعد بيانات تانية (Administration / HR / Purchasing)، فمفيش FK في الداتابيز:
`branchid`, `supplierid`, `customerid`, `currencyid`, `identityuserid`, `projectid`. التحقق منها في التطبيق فقط.

---

## 1. الخريطة العامة

```text
                    InvItemGroups ──< InvItemSubGroups
                          │                 │
InvItemClass (شجرة) ──┐   │                 │
InvBrands ────────────┤   │                 │
                      ▼   ▼                 ▼
InvUnits ──────────> InvItems (الصنف) <─────┘
   ▲  ▲  ▲              │
   │  │  │              ├──< InvItemOtherUnits ──> InvUnits      (الوحدات الأخرى + المعامل)
   │  │  │              ├──< InvItemVariants (SKU)
   │  │  │              │        ├──< InvItemVariantDimensions ──> InvDimensions / InvDimensionValues
   │  │  │              │        ├──< InvItemBarcodes ──> InvUnits
   │  │  │              │        └──< InvItemPrices ──> InvUnits, InvPriceLists
   │  │  │              ├──< InvItemDimensionSetup ──< InvItemDimensionAllowedValues
   │  │  │              ├──< InvItemSuppliers ──> InvUnits
   │  │  │              └──< InvItemAlternativeCodes / InvItemAlternativeNames
   │  │  │
   │  │  └── TrxInvF (سطور الحركات: itemid, variantid, unitid) >── TrxInvH (رأس الحركة) ──> TrxtypeConfig (نوع الحركة)

InvPriceLists (العملة) ──< InvBranchPriceLists (القائمة الافتراضية لكل فرع)
```

`──<` = واحد لمتعدد. `──>` = FK.

---

## 2. جداول التكويد الأساسية (Master codes)

### 2.1 `"InvUnits"` — الوحدات
دليل وحدات القياس (قطعة، كرتونة، كيلو، لتر).

| العمود | الشرح |
|---|---|
| `unitcode` | كود الوحدة (نص). فريد لكل tenant. |
| `unitaraname` / `unitlatname` | الاسم عربي / إنجليزي. |
| `decimalplaces` | عدد الأرقام العشرية المسموح بها في كمية هذه الوحدة (0 = قطعة صحيحة، 3 = كيلو). من 0 لـ 6. |

Unique: `(tenantid, unitcode)`.
ملاحظة: الوحدة هنا **عامة**؛ علاقتها بالصنف ومعامل التحويل في `InvItemOtherUnits`.

### 2.2 `"InvItemGroups"` — المجموعات الرئيسية
| العمود | الشرح |
|---|---|
| `itemgroupcode` | كود المجموعة. فريد لكل tenant. |
| `itemgrouparaname` / `itemgrouplatname` | الاسم. |

### 2.3 `"InvItemSubGroups"` — المجموعات الفرعية
| العمود | الشرح |
|---|---|
| `itemgroupid` | FK → `InvItemGroups.id`. المجموعة الأم (إجباري). |
| `itemsubgroupcode` | الكود. **فريد داخل المجموعة الأم** وليس على مستوى الشركة. |

Unique: `(itemgroupid, itemsubgroupcode)`.

### 2.4 `"InvItemClass"` — التصنيف الشجري
تصنيف متعدد المستويات (شجرة) مستقل عن المجموعات.

| العمود | الشرح |
|---|---|
| `itemclasscode` | الكود. فريد لكل tenant. |
| `parent` | FK ذاتي → `InvItemClass.id`. null = جذر الشجرة. |
| `itemclasslevel` | رقم المستوى في الشجرة (1 = جذر). |
| `longpath` | المسار الكامل من الجذر (للعرض والبحث السريع بدون recursive query). |
| `sortorder` | ترتيب العرض بين الإخوة. |

لقراءة الشجرة: `WITH RECURSIVE` على `parent`.

### 2.5 `"InvBrands"` — الماركات
`brandcode` (فريد لكل tenant)، `brandaraname`, `brandlatname`.

### 2.6 `"InvStores"` — المخازن
| العمود | الشرح |
|---|---|
| `branchid` | الفرع (من Administration، بدون FK). |
| `storecode` | الكود. **فريد داخل الفرع**. |
| `storelocation` | وصف الموقع. |

Unique: `(tenantid, branchid, storecode)`.
جداول مرتبطة: `"InvStoresUsers"` (المستخدمين المسموح لهم بالمخزن: `storesid`, `identityuserid`)،
`"InvProjectStores"` (ربط المشروع بالمخزن: `projectid`, `storeid` FK).

### 2.7 `"InvPriceLists"` — قوائم الأسعار
أمثلة: قطاعي، جملة، موزعين.

| العمود | الشرح |
|---|---|
| `pricelistcode` | الكود. فريد لكل tenant. |
| `pricelistaraname` / `pricelistlatname` | الاسم. |
| `currencycode` | عملة القائمة (`Currency.code` في Administration، بدون FK). كل أسعار القائمة بهذه العملة. **لا تتغير بعد إضافة أسعار.** |

### 2.8 `"InvBranchPriceLists"` — القائمة الافتراضية للفرع
| العمود | الشرح |
|---|---|
| `branchid` | الفرع (Administration، بدون FK). |
| `pricelistid` | FK → `InvPriceLists.id` (Restrict). |

Unique: `(tenantid, branchid)` — قائمة افتراضية واحدة لكل فرع. ربط الفرع بقائمة أخرى يحذف الربط القديم.
الاستخدام: نقطة البيع تأخذ قائمة الجهاز (`PosTerminal.pricelistid`)، وإن كانت فارغة تأخذ قائمة الفرع من هنا.

---

## 3. الصنف — `"InvItems"`

الجدول الرئيسي. صف واحد لكل صنف.

### حقول التعريف
| العمود | الشرح |
|---|---|
| `itemcode` | كود الصنف (نص، إجباري). فريد لكل tenant. |
| `itemaraname` / `itemlatname` | الاسم. لو واحد فاضي التطبيق بيملاه من التاني. |
| `itemdescription`, `itemnotes` | وصف وملاحظات. |

### حقول العلاقات
| العمود | يشاور على | الشرح |
|---|---|---|
| `mainunitid` | `InvUnits.id` | **الوحدة الأساسية** = وحدة الرصيد والتكلفة. كل الكميات بتتحول لها. |
| `defaultsalesunitid` | `InvUnits.id` | وحدة البيع الافتراضية (اختياري). لازم تكون الأساسية أو وحدة في `InvItemOtherUnits` لنفس الصنف وعليها `allowsale`. |
| `defaultpurchaseunitid` | `InvUnits.id` | وحدة الشراء الافتراضية. نفس الشرط مع `allowpurchase`. |
| `itemgroupid` | `InvItemGroups.id` | المجموعة. |
| `itemsubgroupid` | `InvItemSubGroups.id` | المجموعة الفرعية (المفروض تكون تابعة لـ `itemgroupid`). |
| `itemclassid` | `InvItemClass.id` | التصنيف. |
| `brandid` | `InvBrands.id` | الماركة. |
| `itemsp1id`, `itemsp2id` | `InvItemSpecification` | مواصفات (بدون FK، غير مستخدمة حاليًا). |
| `policyid` | `InvItemInactivityPolicy` | سياسة الركود (بدون FK). |

### حقول السلوك
| العمود | الشرح |
|---|---|
| `trackinventory` | الصنف مخزني (له رصيد). false = خدمة. افتراضي true. |
| `monitorbalance` | التحذير/المنع عند البيع بدون رصيد. |
| `hasvariants` | الصنف له موديلات (لون/مقاس). false = له variant افتراضي واحد فقط. |
| `trackserial`, `trackbatch` | تتبع سيريال / تشغيلة (للتوسع، غير مفعلين في الحركات حاليًا). |
| `hasexpiredate`, `expiredays` | له تاريخ صلاحية، وعدد أيام الصلاحية الافتراضي. |
| `isproduct` | صنف مُنتَج (تصنيع). |
| `apprweight`, `calories`, `itemlocation` | وزن تقريبي، سعرات، مكان التخزين — معلومات وصفية. |

---

## 4. وحدات الصنف — `"InvItemOtherUnits"`

الوحدات **الإضافية** للصنف ومعامل تحويل كل وحدة للوحدة الأساسية.
**الوحدة الأساسية نفسها لا تُكتب هنا** — هي في `InvItems.mainunitid` ومعاملها 1 ضمنيًا.

| العمود | الشرح |
|---|---|
| `itemid` | الصنف (`InvItems.id`) — **علاقة منطقية بدون FK في الداتابيز**. |
| `tounitid` | FK → `InvUnits.id`. الوحدة الإضافية. |
| `unitfactor` | `decimal(19,6)`، أكبر من صفر. معامل التحويل. |
| `mainunitisgreater` | اتجاه المعامل (شرح تحت). |
| `allowsale` / `allowpurchase` | هل الوحدة متاحة في البيع / الشراء. افتراضي true. |

### طريقة التحويل للوحدة الأساسية
```text
qty_main = mainunitisgreater ? qty / unitfactor
                             : qty * unitfactor
```
مثال: الأساسية "قطعة"، الإضافية "كرتونة = 12 قطعة":
`tounitid = كرتونة, unitfactor = 12, mainunitisgreater = false` → 2 كرتونة = 24 قطعة.
مثال عكسي: الأساسية "كرتونة"، الإضافية "قطعة": `unitfactor = 12, mainunitisgreater = true` → 24 قطعة = 2 كرتونة.

Unique: `(itemid, tounitid)` — الوحدة لا تتكرر لنفس الصنف.
قواعد التطبيق: لا تساوي الوحدة الأساسية، ولا تُحذف أو تتغير طالما عليها باركود.

---

## 5. الموديلات (SKU) والأبعاد

### 5.1 `"InvItemVariants"` — الـ SKU
كل صنف له **variant افتراضي واحد على الأقل**. الصنف اللي له لون/مقاس له variant لكل تركيبة.

| العمود | الشرح |
|---|---|
| `itemid` | FK → `InvItems.id`. |
| `variantcode` | كود الـ SKU. فريد لكل tenant. في الافتراضي = `itemcode`. |
| `variantaraname` / `variantlatname` | الاسم. |
| `combinationkey` | مفتاح التركيبة (مثال: `COLOR=RED;SIZE=L`). في الافتراضي = `'DEFAULT'`. فريد داخل الصنف. |
| `isdefault` | هل هو الـ variant الافتراضي. **variant افتراضي واحد فقط لكل صنف** (`ux_invitemvariants_itemid_default`). |

الـ variant الافتراضي بيتعمل تلقائيًا مع الصنف، وكوده واسمه بيتحدثوا مع تعديل الصنف.

### 5.2 `"InvDimensions"` و `"InvDimensionValues"` — الأبعاد وقيمها
- `InvDimensions`: نوع البعد (`dimensioncode` فريد لكل tenant): لون، مقاس.
- `InvDimensionValues`: القيم (`dimensionid` FK، `valuecode` فريد داخل البعد، `sortorder`): أحمر، أزرق / S, M, L.
- الإدارة: مركز الأصناف ← زر «الأبعاد» (`InvItemCenter/GetDimensions`، `SaveDimension`، `SaveDimensionValue`، `ReorderDimensionValues`، `DeleteDimension`، `DeleteDimensionValue`).
- `dimensioncode` و`valuecode` يدخلوا في `combinationkey` للـ SKU، فالكود المستخدم في SKUs مقفول. الاسم يتغير عادي، لكن أسماء الـ SKUs القديمة تفضل زي ما اتولدت.
- الحذف: البعد لو مش مستخدم في أي صنف، والقيمة لو مش مستخدمة في أي SKU. غير كده يتوقف (`notactive`).
- الموقوف لا يظهر عند إعداد صنف جديد، ولا يتولد منه SKU جديد، ويفضل شغال في الـ SKUs الحالية.

### 5.3 `"InvItemDimensionSetup"` — أبعاد الصنف
أي أبعاد تنطبق على الصنف. `itemid` FK، `dimensionid` FK، `isrequired`، `sortorder`. Unique `(itemid, dimensionid)`.

### 5.4 `"InvItemDimensionAllowedValues"` — القيم المسموحة للصنف
لو الصنف ليه ألوان معينة بس. `itemid`, `dimensionid`, `dimensionvalueid` (كلهم FK). Unique على الثلاثة.

### 5.5 `"InvItemVariantDimensions"` — تركيبة الـ SKU
قيمة كل بعد في الـ variant. `variantid`, `itemid`, `dimensionid`, `dimensionvalueid` (كلهم FK).
Unique `(variantid, dimensionid)` — قيمة واحدة لكل بعد في الـ SKU.

---

## 6. الباركود — `"InvItemBarcodes"`

| العمود | الشرح |
|---|---|
| `itemid` | FK → `InvItems.id`. |
| `variantid` | FK → `InvItemVariants.id` (إجباري). لو مش محدد من الشاشة = الـ variant الافتراضي. |
| `unitid` | FK → `InvUnits.id`. الوحدة اللي الباركود بيمثلها: الأساسية أو وحدة في `InvItemOtherUnits` لنفس الصنف. |
| `barcode` | قيمة الباركود (حد أقصى 100). **فريد لكل tenant** — الباركود يشاور على صنف/وحدة واحدة فقط. |
| `barcodetype` | `CODE128` (افتراضي)، `EAN13`, `EAN8`, `UPC`, `QR`. |
| `isprimary` | الباركود الأساسي لنفس (variant, unit) — واحد فقط نشط (`ux_invitembarcodes_variant_unit_primary`). يُستخدم في الطباعة. |
| `supplierid` | لو الباركود خاص بمورد (بدون FK). |

مسح باركود = `SELECT itemid, variantid, unitid FROM "InvItemBarcodes" WHERE tenantid = :t AND barcode = :b AND isdeleted = false AND coalesce(notactive,false) = false;`
ثم تحويل الكمية للأساسية من `InvItemOtherUnits` (لو `unitid <> mainunitid`).

---

## 7. الأسعار

### 7.1 `"InvItemPrices"` — أسعار قوائم الأسعار (المستخدمة في نقطة البيع)
| العمود | الشرح |
|---|---|
| `itemid` | FK → الصنف. |
| `variantid` | FK اختياري. null = السعر لكل موديلات الصنف. |
| `unitid` | FK → الوحدة اللي السعر ليها (سعر الكرتونة غير سعر القطعة). |
| `pricelistid` | FK → `InvPriceLists`. |
| `currencycode` | نسخة من عملة القائمة (`InvPriceLists.currencycode`)، تُكتب تلقائيًا عند الحفظ. |
| `price` | السعر. |
| `fromdate` / `todate` | فترة السريان. `todate` null = مفتوح. |

Index: `(itemid, unitid, pricelistid)`. السعر الساري = `fromdate <= اليوم AND (todate IS NULL OR todate >= اليوم)`.
سعر الـ SKU في نقطة البيع: صف بنفس `variantid`، وإلا صف `variantid IS NULL`، وإلا لا يوجد سعر (البيع ممنوع).

### 7.2 `InvItemStore` — قديم
سعر الصنف في المخزن (`price` float). **لم يعد مستخدمًا في نقطة البيع**، والجدول غير موجود في قاعدة dev (يوجد كود قديم فقط).

---

## 8. الموردين والأكواد البديلة

### 8.1 `"InvItemSuppliers"`
| العمود | الشرح |
|---|---|
| `itemid` | FK → الصنف. |
| `supplierid` | المورد (بدون FK). Unique `(itemid, supplierid)`. |
| `defaultpurchaseunitid` | FK → `InvUnits` — وحدة الشراء من هذا المورد. |
| `ispreferred` | المورد المفضل — واحد فقط نشط لكل صنف. |
| `leadtimedays` | مدة التوريد بالأيام. |
| `minimumorderqty` | الحد الأدنى للطلب (بوحدة الشراء). |

### 8.2 `"InvItemAlternativeCodes"`
أكواد الصنف في أنظمة/جهات أخرى (كود المورد، كود العميل، كود نظام خارجي).
`itemid` FK، `variantid` FK اختياري، `codetype` (نوع الكود)، `alternativecode`، `supplierid`/`customerid`، `externalsystem`.
Index (غير فريد): `(itemid, codetype, alternativecode)`.

### 8.3 `"InvItemAlternativeNames"`
أسماء بديلة: لغات أخرى أو اسم الصنف عند المورد/العميل.
`itemid` FK، `variantid` FK اختياري، `nametype`، `languagecode` (مثال `ar`, `en`, `fr`)، `alternativename`.

### 8.4 `"InvItemAlternatives"` (قديم)
أصناف بديلة (لو الصنف خلص يُقترح بديله): `itemid`, `itemalterid`. بدون FK.

---

## 9. علاقة الصنف بالحركات — `"TrxInvF"` (سطور الحركات)

| العمود | الشرح |
|---|---|
| `itemid` | FK → الصنف. |
| `variantid` | FK → `InvItemVariants` (جديد). لو مش مبعوت بيتملى تلقائيًا بالـ variant الافتراضي عند الحفظ. |
| `unitid` | FK → الوحدة المستخدمة في السطر. |
| `factor`, `mainunitisgreater` | **نسخة من المعامل وقت الحركة** — الحركة لا تتأثر لو اتغير المعامل بعدين. |
| `displayqty` | الكمية بوحدة السطر كما أدخلها المستخدم. |
| `quantity` | الكمية محولة للوحدة الأساسية (هي اللي تتحسب في الرصيد). |

**تقارير الرصيد لازم تستخدم `quantity` (الأساسية)** وليس `displayqty`.

### 9.1 `"TrxInvH"` — رأس الحركة (الأعمدة المهمة للرصيد ونقطة البيع)
| العمود | الشرح |
|---|---|
| `trxtypeconfigid` | FK → `TrxtypeConfig`. يحدد اتجاه الحركة. |
| `trxserial`, `trxyear`, `trxdate` | رقم وسنة وتاريخ الحركة. |
| `storeid` | المخزن (والسطر قد يحدد مخزنًا آخر في `TrxInvF.storeid`). |
| `draft` | الحركة المسودة **لا تدخل** في الرصيد. |
| `mykey`, `mysource` | مصدر الحركة الآلية. ترحيل نقطة البيع: `mykey` = رقم الدفعة في POS، `mysource` = `POS-OUT` (بيع) أو `POS-IN` (مرتجع). |
| `autogeneration` | true = حركة أنشأها النظام. |

### 9.2 `"TrxtypeConfig"` — أنواع الحركات
| العمود | الشرح |
|---|---|
| `trxkind` | 1 حركة (تؤثر في الرصيد)، 2 أمر. |
| `inout` | 1 وارد، 2 منصرف، 3 و4 بدون تأثير. |
| `operatingtype` | 1 مبيعات، 2 مشتريات، 3 تحويل، 4 إنتاج، 5 أخرى. |
| `branchid` | null = لكل الفروع. |
| `systemusage` | النوع الذي يستخدمه النظام تلقائيًا: null عادي، 1 مبيعات نقطة البيع، 2 مرتجع نقطة البيع. Unique `(tenantid, branchid, systemusage)`. |

الرصيد في مخزن = مجموع `TrxInvF.quantity` للحركات `trxkind = 1` و`draft` ليست true، موجب لـ `inout = 1` وسالب لـ `inout = 2`، والمخزن = `coalesce(f.storeid, h.storeid)`.

---

## 10. استعلامات مفيدة

كل وحدات الصنف مع المعامل (الأساسية + الإضافية):
```sql
SELECT i.itemcode, u.unitaraname, 1::numeric AS factor, false AS mainunitisgreater, true AS ismain
FROM "InvItems" i JOIN "InvUnits" u ON u.id = i.mainunitid
WHERE i.id = :item AND i.isdeleted = false
UNION ALL
SELECT i.itemcode, u.unitaraname, o.unitfactor, o.mainunitisgreater, false
FROM "InvItemOtherUnits" o
JOIN "InvItems" i ON i.id = o.itemid
JOIN "InvUnits" u ON u.id = o.tounitid
WHERE o.itemid = :item AND o.isdeleted = false;
```

أصناف بدون وحدة أساسية (بيانات ناقصة):
```sql
SELECT itemcode, itemaraname FROM "InvItems"
WHERE isdeleted = false AND mainunitid IS NULL;
```

باركودات على وحدة لم تعد معرفة للصنف (يجب أن تكون صفر):
```sql
SELECT b.barcode, i.itemcode
FROM "InvItemBarcodes" b JOIN "InvItems" i ON i.id = b.itemid
WHERE b.isdeleted = false
  AND b.unitid <> coalesce(i.mainunitid, '00000000-0000-0000-0000-000000000000')
  AND NOT EXISTS (SELECT 1 FROM "InvItemOtherUnits" o
                  WHERE o.itemid = b.itemid AND o.tounitid = b.unitid AND o.isdeleted = false);
```

---

## 11. ملاحظات معروفة على البيانات/الهيكل

- `InvItemOtherUnits.itemid` بدون FK فعلي على `InvItems` (موروث). مقترح إضافته بعد تنظيف أي صفوف يتيمة.
- على `InvItemOtherUnits.tounitid` يوجد FK مكرر باسمين (`FK_InvItemOtherUnits_InvUnits_ToUnitId` و `FK_InvItemOtherUnits_InvUnits_tounitid`) — نفس القيد؛ ممكن حذف القديم.
- `InvItemStore`: كود قديم بدون جدول في dev؛ يُحذف لاحقًا.
- أكواد مكررة قديمة تم تمييزها بلاحقة `-2` أثناء migration `Item_Master_Redesign` (مثال: وحدة `1-2`، صنف `2-2`).
