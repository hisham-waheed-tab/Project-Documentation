# POS — قاعدة البيانات باختصار

قاعدة `Dev-TABMS.POS` (PostgreSQL). كل الجداول فيها `tenantid` + soft delete (`isdeleted`).
المفتاح دائماً `id` (Guid). `Number` / `ShiftNumber` أرقام عرض فقط وليست مفاتيح.

## قاعدة الربط

- **FK حقيقي فقط داخل المستند الواحد** (رأس ← تفاصيله). باقي الروابط Guid منطقية بدون FK.
- **لا FK عبر الأنظمة**: `BranchId`، `UserId` من Administration، و`ItemId` و`StoreId` و`UnitId` من Inventory.
- لذلك كل سطر يحفظ **snapshot** للأسماء والأكواد وقت العملية (اسم الصنف، اسم الكاشير، اسم العميل).

## الجداول

### الإعدادات (يديرها Front)
| الجدول | الحقول المهمة | ملاحظات |
|---|---|---|
| `PosTerminal` | `BranchId`، `Code`، `DefaultCashBoxId`، `DefaultStoreId`، `AllowOfflineSales` | فريد: Tenant + Branch + Code |
| `PosCashBox` | `BranchId`، `Code`، `PreferredTerminalId` | الخزنة |
| `PosTerminalDevice` | `TerminalId`، `DeviceType` | طابعة، درج، جهاز دفع |
| `PosPaymentMethod` | `Code`، `MethodType`، `AllowOffline`، `AllowSplit` | فريد: Tenant + Code |
| `PosReturnReason` / `PosNoSaleReason` | `Code` | أسباب المرتجع وفتح الدرج |
| `PosCustomer` | `Mobile`، `Phone`، `LoyaltyTierId` | عملاء POS |
| `PosLoyaltyTier` / `PosCustomerLoyaltyAccount` | `MinPoints`، `EarnRatePercent` / `CustomerId` | الولاء |
| `PosItemSetting` | `ItemId`، `BranchId`؟، `ShowOnPos`، `IsQuickButton`، `MinSellPrice` | امتداد لصنف Inventory في POS فقط |
| `PosUserPin` | `UserId`، hash | PIN المشرف |

### السياسات
- `PosPolicyDefinition`: `PolicyKey`، `ValueType`، `DefaultValue`، `ResolutionMode`. لها ← `PosPolicyValue` (FK).
- `PosPolicyValue`: `ScopeLevel` + واحد من `BranchId` / `TerminalId` / `RoleId` / `UserId` + `Value`.
- الافتراضيات في الكود (`PosPolicyCatalog`). التهيئة تنسخها إلى `PosPolicyDefinition`، و`PosPolicyValue` يُضاف فقط عند التخصيص.

### التهيئة
`POST /api/v1/PosTenantSetup/InitializeDefaults` بـ body `{ "dryRun": false }` للتينانت الحالي فقط.
تزرع: تعريفات السياسات، طرق الدفع، أسباب المرتجع، أسباب فتح الدرج، مستويات الولاء، العميل النقدي.
أي جدول فيه صف للتينانت (حتى المحذوف) يُترك كما هو. `Terminal` و`CashBox` لا تُزرع لأنها مرتبطة بالفرع.

### التشغيل (الكاشير)
```
PosShift (TerminalId, CashBoxId, CashierUserId, Status)
 └─ PosShiftCashMovement (FK ShiftId)            إيداع / سحب / فتح درج

PosSaleH (BranchId, TerminalId, ShiftId, StoreId, CustomerId, Status, ClientLocalId)
 ├─ PosSaleF        (FK SaleId)  ItemId, Quantity, UnitPrice, LineTotal, StoreId
 ├─ PosSalePayment  (FK SaleId)  PaymentMethodId, Amount
 ├─ PosSaleDelivery (FK SaleId)  1:1 للتسليم المؤجل
 ├─ PosSaleApproval (FK SaleId)  موافقات المشرف
 └─ PosSaleLoyaltyMovement (FK SaleId)

PosReturnH (OriginalSaleId → PosSaleH, ExchangeSaleId, ReasonId, ClientLocalId)
 ├─ PosReturnF       (FK ReturnId)  OriginalSaleLineId → PosSaleF, ItemId
 └─ PosReturnPayment (FK ReturnId)
```

### السجلات والمزامنة
`PosSyncOutbox` و`PosSyncLog` للمزامنة، و`PosDeviceEvent` و`PosPrintLog` و`PosSupervisorOverrideLog` و`PosPriceInquiryLog` للتدقيق. كلها مرتبطة منطقياً بـ `TerminalId`.

## العلاقة مع Inventory

| الاتجاه | ماذا |
|---|---|
| Inventory ← POS (قراءة) | `InvItems` (الأصناف) و`InvItemStore.Price` (السعر لكل فرع/مخزن). الديسكتوب يقرأها من Inventory API ويخزنها محلياً |
| POS → Inventory (أثر المخزون) | `PosInventoryPostingBatch` (BranchId، StoreId، الفترة، Status، `InventoryDocumentId`) ← `PosInventoryPostingLine` (ItemId، StoreId، SoldQuantity، ReturnedQuantity، `NetQuantity`) |

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
