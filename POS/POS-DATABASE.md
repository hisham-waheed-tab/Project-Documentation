# POS — قاعدة البيانات باختصار

قاعدة `Dev-TABMS.POS` (PostgreSQL). كل الجداول فيها `tenantid` + soft delete (`isdeleted`).
المفتاح دائماً `id` (Guid). `Number` / `ShiftNumber` أرقام عرض فقط وليست مفاتيح.

## قاعدة الربط

- **FK حقيقي فقط داخل المستند الواحد** (رأس ← تفاصيله، وتعريف السياسة ← قيمها). باقي الروابط Guid منطقية بدون FK.
- **لا FK عبر الأنظمة**: `BranchId`، `UserId` من Administration، و`ItemId` و`StoreId` و`UnitId` من Inventory.
- لذلك كل سطر يحفظ **snapshot** للأسماء والأكواد وقت العملية (اسم الصنف، اسم الكاشير، اسم العميل).

## مرجع جداول الأنظمة الأخرى

حقول العلاقات تشير لهذه الجداول بالاسم المختصر في الجداول التالية:

| الحقل يشير إلى | القاعدة | الجدول |
|---|---|---|
| فرع | Administration | `Branches` |
| مستخدم | Administration | `AbpUsers` (IdentityUserId) |
| دور | Administration | `TABTenantRole` |
| صنف | Inventory | `InvItems` |
| مخزن | Inventory | `InvStores` |
| وحدة | Inventory | وحدات الصنف في Inventory |

**نوع الربط** في الجداول التالية:
- **FK**: قيد حقيقي في قاعدة البيانات.
- **منطقي**: Guid داخل قاعدة POS بدون قيد، ويتحقق منه الكود.
- **خارجي**: Guid لجدول في نظام آخر.

`TenantId` موجود في كل الجداول ولم يُكرر.

## الجداول

### الإعدادات (يديرها Front)

#### `PosTerminal` — نقطة البيع
فريد: `TenantId + BranchId + Code`. الحقول: `Code`، `AraName`، `LatName`، `AllowOfflineSales`، `TrainingMode`، `DeviceFingerprint`.

| حقل العلاقة | يشير إلى | النوع | إلزامي |
|---|---|---|---|
| `BranchId` | فرع | خارجي | نعم |
| `DefaultCashBoxId` | `PosCashBox` | منطقي | لا |
| `DefaultStoreId` | مخزن | خارجي | لا |

- الخزنة الافتراضية لازم تكون من نفس فرع نقطة البيع (يرفض السيرفر غير ذلك عند الحفظ).

#### `PosCashBox` — الخزنة النقدية
فريد: `TenantId + BranchId + Code`. الحقول: `Code`، `AraName`، `LatName`.

| حقل العلاقة | يشير إلى | النوع | إلزامي |
|---|---|---|---|
| `BranchId` | فرع | خارجي | نعم |
| `PreferredTerminalId` | `PosTerminal` | منطقي | لا |

- نقطة البيع المفضلة لازم تكون من نفس فرع الخزنة.
- لا يمكن حذفها أو نقلها لفرع آخر لو:
  - هي الخزنة الافتراضية لنقطة بيع في فرع مختلف.
  - أو عليها وردية غير مغلقة.
- نقلها إلى فرع نقطة البيع التي تستخدمها مسموح (تصحيح).

#### `PosTerminalDevice` — أجهزة نقطة البيع
الحقول: `DeviceType` (طابعة، درج، جهاز دفع...).

| حقل العلاقة | يشير إلى | النوع | إلزامي |
|---|---|---|---|
| `TerminalId` | `PosTerminal` | منطقي | نعم |

#### `PosPaymentMethod` — طرق الدفع
فريد: `TenantId + Code`. الحقول: `Code`، `MethodType`، `AllowOffline`، `AllowSplit`. لا توجد حقول علاقة.

#### `PosReturnReason` / `PosNoSaleReason` — أسباب المرتجع وفتح الدرج
فريد: `TenantId + Code`. لا توجد حقول علاقة.

#### `PosCustomer` — عملاء POS
فهرس على `Phone` وعلى `Mobile`.

| حقل العلاقة | يشير إلى | النوع | إلزامي |
|---|---|---|---|
| `LoyaltyTierId` | `PosLoyaltyTier` | منطقي | لا |

#### `PosLoyaltyTier` — مستويات الولاء
فريد: `TenantId + Code`. الحقول: `MinPoints`، `EarnRatePercent`. لا توجد حقول علاقة.

#### `PosCustomerLoyaltyAccount` — حساب ولاء العميل
فريد: `TenantId + CustomerId` (حساب واحد لكل عميل).

| حقل العلاقة | يشير إلى | النوع | إلزامي |
|---|---|---|---|
| `CustomerId` | `PosCustomer` | منطقي | نعم |
| `LoyaltyTierId` | `PosLoyaltyTier` | منطقي | لا |

#### `PosItemSetting` — إعدادات الصنف في POS
امتداد لصنف Inventory داخل POS فقط. الحقول: `ShowOnPos`، `IsQuickButton`، `MinSellPrice`.

| حقل العلاقة | يشير إلى | النوع | إلزامي |
|---|---|---|---|
| `ItemId` | صنف | خارجي | نعم |
| `BranchId` | فرع | خارجي | لا (فارغ = كل الفروع) |

#### `PosUserPin` — رمز PIN للمشرف
فريد: `TenantId + UserId`. يحفظ hash فقط.

| حقل العلاقة | يشير إلى | النوع | إلزامي |
|---|---|---|---|
| `UserId` | مستخدم | خارجي | نعم |

### السياسات

#### `PosPolicyDefinition` — تعريف السياسة
فريد: `TenantId + PolicyKey`. الحقول: `PolicyKey`، `ValueType`، `DefaultValue`، `ResolutionMode`، `AllowedValues`، `Category`. لا توجد حقول علاقة.

#### `PosPolicyValue` — قيمة السياسة لجهة معينة
الحقول: `ScopeLevel`، `Value`. يُملأ **حقل واحد فقط** من حقول الجهة حسب `ScopeLevel`.

| حقل العلاقة | يشير إلى | النوع | إلزامي |
|---|---|---|---|
| `PolicyDefinitionId` | `PosPolicyDefinition` | **FK** | نعم |
| `BranchId` | فرع | خارجي | عند `ScopeLevel = 2` |
| `TerminalId` | `PosTerminal` | منطقي | عند `ScopeLevel = 3` |
| `RoleId` | دور | خارجي | عند `ScopeLevel = 4` |
| `UserId` | مستخدم | خارجي | عند `ScopeLevel = 5` |

- مستوى الشركة (`ScopeLevel = 1`) لا يملأ أي حقل جهة.
- الافتراضيات في الكود (`PosPolicyCatalog`). التهيئة تنسخها إلى `PosPolicyDefinition`.
- `PosPolicyValue` يُضاف فقط عند التخصيص من شاشة السياسات، وحذفه يعني الرجوع للقيمة الموروثة.
- **ترتيب الحل:**
  - المكان: نقطة البيع، ثم الفرع، ثم الشركة، ثم الافتراضي.
  - الشخص: المستخدم، وإلا أكثر الأدوار سماحًا.
  - `Override`: قيمة الشخص تغلب. `Restrict`: الأكثر تقييدًا بين المكان والشخص.

### التهيئة
`POST /api/v1/PosTenantSetup/InitializeDefaults` بـ body `{ "dryRun": false }` للتينانت الحالي فقط.
تزرع: تعريفات السياسات، طرق الدفع، أسباب المرتجع، أسباب فتح الدرج، مستويات الولاء، العميل النقدي.
أي جدول فيه صف للتينانت (حتى المحذوف) يُترك كما هو. `Terminal` و`CashBox` لا تُزرع لأنها مرتبطة بالفرع.

### التشغيل (الكاشير)

الشكل العام (الأسهم الداخلية = **FK** حقيقي):
```
PosShift
 └─ PosShiftCashMovement (FK ShiftId)            إيداع / سحب / فتح درج

PosSaleH
 ├─ PosSaleF               (FK SaleId)
 ├─ PosSalePayment         (FK SaleId)
 ├─ PosSaleDelivery        (FK SaleId, 1:1)      التسليم المؤجل
 ├─ PosSaleApproval        (FK SaleId)           موافقات المشرف
 └─ PosSaleLoyaltyMovement (FK SaleId)

PosReturnH
 ├─ PosReturnF       (FK ReturnId)
 └─ PosReturnPayment (FK ReturnId)
```

#### `PosShift` — الوردية
فهرس: `TenantId + TerminalId + Status`. الحقول: `ShiftNumber`، `Status` (1 مفتوحة، 2 قيد الإغلاق، 3 مغلقة، 4 موقوفة)، `OpeningBalance`، `ExpectedCash`، `ActualCash`، `PendingSyncCount`.

| حقل العلاقة | يشير إلى | النوع | إلزامي |
|---|---|---|---|
| `BranchId` | فرع | خارجي | نعم |
| `TerminalId` | `PosTerminal` | منطقي | نعم |
| `CashBoxId` | `PosCashBox` | منطقي | نعم (من نفس الفرع) |
| `CashierUserId` | مستخدم | خارجي | نعم |
| `VarianceApprovedByUserId` | مستخدم (المشرف) | خارجي | لا |

#### `PosShiftCashMovement` — حركات الخزنة
الحقول: `MovementType`، `Amount`، `MovementTime`.

| حقل العلاقة | يشير إلى | النوع | إلزامي |
|---|---|---|---|
| `ShiftId` | `PosShift` | **FK** | نعم |
| `ReasonId` | `PosNoSaleReason` | منطقي | لا |
| `PerformedByUserId` | مستخدم | خارجي | نعم |
| `ApprovedByUserId` | مستخدم (المشرف) | خارجي | لا |

#### `PosSaleH` — رأس فاتورة البيع
فريد: `TenantId + TerminalId + ClientLocalId`. الحقول: `Number`، `Status`، `GrandTotal`، `PaidTotal`، `IsOfflineOrigin`، `IsTrainingMode`، snapshot للعميل والكاشير.

| حقل العلاقة | يشير إلى | النوع | إلزامي |
|---|---|---|---|
| `BranchId` | فرع | خارجي | نعم |
| `TerminalId` | `PosTerminal` | منطقي | نعم |
| `ShiftId` | `PosShift` | منطقي | لا |
| `CashBoxId` | `PosCashBox` | منطقي | لا |
| `StoreId` | مخزن | خارجي | لا |
| `CashierUserId` | مستخدم | خارجي | نعم |
| `CustomerId` | `PosCustomer` | منطقي | لا (فارغ = عميل نقدي) |
| `LockedByTerminalId` | `PosTerminal` | منطقي | لا (قفل الفاتورة المعلقة) |
| `RelatedReturnId` | `PosReturnH` | منطقي | لا (فاتورة ناتجة عن استبدال) |

#### `PosSaleF` — سطور الفاتورة
فريد: `SaleId + LineNo`. الحقول: `Quantity`، `UnitPrice`، `LineTotal`، snapshot لاسم الصنف.

| حقل العلاقة | يشير إلى | النوع | إلزامي |
|---|---|---|---|
| `SaleId` | `PosSaleH` | **FK** | نعم |
| `ItemId` | صنف | خارجي | لا |
| `UnitId` | وحدة | خارجي | لا |
| `StoreId` | مخزن | خارجي | لا |

#### `PosSalePayment` — مدفوعات الفاتورة
الحقول: `Amount`.

| حقل العلاقة | يشير إلى | النوع | إلزامي |
|---|---|---|---|
| `SaleId` | `PosSaleH` | **FK** | نعم |
| `PaymentMethodId` | `PosPaymentMethod` | منطقي | لا |

#### `PosSaleDelivery` — التسليم المؤجل (1:1)
فريد: `SaleId`.

| حقل العلاقة | يشير إلى | النوع | إلزامي |
|---|---|---|---|
| `SaleId` | `PosSaleH` | **FK** | نعم |
| `CustomerId` | `PosCustomer` | منطقي | نعم |

#### `PosSaleApproval` — موافقات المشرف
| حقل العلاقة | يشير إلى | النوع | إلزامي |
|---|---|---|---|
| `SaleId` | `PosSaleH` | **FK** | نعم |
| `SaleLineId` | `PosSaleF` | منطقي | لا (فارغ = على الفاتورة كلها) |
| `RequestedByUserId` | مستخدم (الكاشير) | خارجي | نعم |
| `ApprovedByUserId` | مستخدم (المشرف) | خارجي | لا |

#### `PosSaleLoyaltyMovement` — حركة نقاط الولاء
| حقل العلاقة | يشير إلى | النوع | إلزامي |
|---|---|---|---|
| `SaleId` | `PosSaleH` | **FK** | نعم |
| `CustomerId` | `PosCustomer` | منطقي | نعم |

#### `PosReturnH` — رأس المرتجع / الاستبدال
فريد: `TenantId + TerminalId + ClientLocalId`. الحقول: `Number`، `ReturnDate`، `RefundTotal`، `ExchangeDifference`، `ReasonText`.

| حقل العلاقة | يشير إلى | النوع | إلزامي |
|---|---|---|---|
| `BranchId` | فرع | خارجي | نعم |
| `TerminalId` | `PosTerminal` | منطقي | نعم |
| `ShiftId` | `PosShift` | منطقي | لا |
| `CashierUserId` | مستخدم | خارجي | نعم |
| `OriginalSaleId` | `PosSaleH` | منطقي | نعم |
| `CustomerId` | `PosCustomer` | منطقي | لا |
| `ReasonId` | `PosReturnReason` | منطقي | لا |
| `ExchangeSaleId` | `PosSaleH` (فاتورة الاستبدال الجديدة) | منطقي | لا |
| `ApprovedByUserId` | مستخدم (المشرف) | خارجي | لا |

#### `PosReturnF` — سطور المرتجع
فريد: `ReturnId + LineNo`.

| حقل العلاقة | يشير إلى | النوع | إلزامي |
|---|---|---|---|
| `ReturnId` | `PosReturnH` | **FK** | نعم |
| `OriginalSaleLineId` | `PosSaleF` | منطقي | لا |
| `ItemId` | صنف | خارجي | لا |
| `ExchangeItemId` | صنف (البديل في الاستبدال) | خارجي | لا |

#### `PosReturnPayment` — رد المبلغ
| حقل العلاقة | يشير إلى | النوع | إلزامي |
|---|---|---|---|
| `ReturnId` | `PosReturnH` | **FK** | نعم |
| `PaymentMethodId` | `PosPaymentMethod` | منطقي | لا |

### السجلات والمزامنة
كل حقول العلاقة هنا منطقية أو خارجية (بدون FK).

| الجدول | حقول العلاقة |
|---|---|
| `PosSyncOutbox` | `TerminalId` → `PosTerminal` (إلزامي)، `EntityId` → السجل المرفوع (يُحدَّد جدوله حسب `EntityName`) |
| `PosSyncLog` | `TerminalId` → `PosTerminal`، `OutboxId` → `PosSyncOutbox`، `EntityId` → السجل (حسب `EntityName`) |
| `PosDeviceEvent` | `TerminalId` → `PosTerminal` (إلزامي)، `ShiftId` → `PosShift`، `SaleId` → `PosSaleH` |
| `PosPrintLog` | `TerminalId` → `PosTerminal` (إلزامي)، `ShiftId` → `PosShift`، `SaleId` → `PosSaleH`، `ReturnId` → `PosReturnH` |
| `PosSupervisorOverrideLog` | `BranchId` → فرع، `TerminalId` → `PosTerminal` (إلزاميان)، `ShiftId`، `SaleId`، `ReturnId`، `RequestedByUserId` → مستخدم (إلزامي)، `ApprovedByUserId` → مستخدم |
| `PosPriceInquiryLog` | `TerminalId` → `PosTerminal`، `CashierUserId` → مستخدم (إلزاميان)، `ShiftId` → `PosShift`، `ItemId` → صنف |

## العلاقة مع Inventory

| الاتجاه | ماذا |
|---|---|
| Inventory ← POS (قراءة) | `InvItems` (الأصناف) و`InvItemStore.Price` (السعر لكل فرع/مخزن). الديسكتوب يقرأها من Inventory API ويخزنها محلياً |
| POS → Inventory (أثر المخزون) | `PosInventoryPostingBatch` (BranchId، StoreId، الفترة، Status، `InventoryDocumentId`) ← `PosInventoryPostingLine` (ItemId، StoreId، SoldQuantity، ReturnedQuantity، `NetQuantity`) |

| الجدول | حقل العلاقة | يشير إلى | النوع | إلزامي |
|---|---|---|---|---|
| `PosInventoryPostingBatch` | `BranchId` | فرع | خارجي | نعم |
| | `StoreId` | مخزن | خارجي | لا |
| | `InventoryDocumentId` | مستند المخازن (مثل `TrxInvH`) | خارجي | لا (يُملأ بعد الترحيل) |
| `PosInventoryPostingLine` | `BatchId` | `PosInventoryPostingBatch` | **FK** | نعم |
| | `ItemId` | صنف | خارجي | نعم |
| | `StoreId` | مخزن | خارجي | لا |
| | `UnitId` | وحدة | خارجي | لا |

- الرصيد **لا يُحفظ في POS**. POS يجمّع صافي الحركة لكل صنف ومخزن ثم يُرحّل مستنداً واحداً لـ Inventory.
- `InventoryDocumentId` يربط الدفعة بمستند المخازن بعد نجاح الترحيل.
- فواتير التدريب (`IsTrainingMode`) لا تُرحّل.
- **الحالي:** الجدولان وشاشة CRUD لهما موجودة، لكن توليد الدفعات تلقائياً من المبيعات والترحيل الفعلي **غير منفّذ بعد**.

## القاعدة المحلية Offline (الديسكتوب)

ملف SQLite: `userData/pos-local.db`، وتصل إليه عملية Electron الرئيسية فقط (`electron/localStore.cjs`).

| الجدول | الحقول | الاستخدام |
|---|---|---|
| `cache` | `kind`، `id`، `data` (JSON) | نسخة من البيانات المرجعية القادمة من السيرفر (منتجات، أسعار، سياسات...) + السجلات المحلية (`sale`، `return`، `shift`، `cash_movement`) |
| `outbox` | `seq`، `id`، `kind`، `entity_id`، `payload`، `status`، `attempts`، `next_attempt_at` | طابور العمليات التي تنتظر الرفع |
| `kv` | `key`، `value` | قيم متفرقة (الجلسة، أوقات آخر تحديث) |
| `sequence` | `name`، `value` | ترقيم محلي للفواتير والورديات |
| `secure` | `key`، `value` (مشفر) | التوكن وبيانات حساسة |

**التدفق:**
- **البيانات المرجعية باتجاه واحد (سيرفر ← جهاز):** عند الاتصال تُستبدل في `cache`، وعند الانقطاع يُقرأ آخر snapshot.
- **العمليات (جهاز ← سيرفر):** تُكتب محلياً + صف في `outbox` في نفس اللحظة، ثم `syncWorker` يرفعها بالترتيب (`seq`):

| `outbox.kind` | Endpoint | الجدول في السيرفر |
|---|---|---|
| `shift_open` / `shift_close` | `PosShift/Open` / `Close` | `PosShift` |
| `sale` | `PosCheckout/SubmitSale` | `PosSaleH` + تفاصيلها |
| `return` | `PosReturnCheckout/SubmitReturn` | `PosReturnH` + تفاصيلها |
| `cash_movement` | `PosCashDrawer/AddMovement` | `PosShiftCashMovement` |
| `approval_log` | `PosCheckout/LogOfflineApprovals` | `PosSaleApproval` |

- **منع التكرار:** الجهاز يولّد `id` و`ClientLocalId`، وفي السيرفر فهرس فريد على `(TenantId, TerminalId, ClientLocalId)` في `PosSaleH` و`PosReturnH`. إعادة الإرسال بعد انقطاع أو crash آمنة.
- الفواتير المرفوعة من الجهاز يكون فيها `IsOfflineOrigin = true`. و`PosShift.PendingSyncCount` قد يمنع إغلاق الوردية.
