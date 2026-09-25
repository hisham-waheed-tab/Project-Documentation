# نظام POS في Tab-MS-Front

## الشاشات

### إعدادات (base-entry — قابلة للتعديل)
| Route | Resource | المجلد |
|---|---|---|
| `/pos-system/pos-terminal/:id` | `PosTerminal` | `pages/pos-system/setup/pos-terminal` |
| `/pos-system/pos-cash-box/:id` | `PosCashBox` | `pages/pos-system/setup/pos-cash-box` |
| `/pos-system/pos-payment-method/:id` | `PosPaymentMethod` | `pages/pos-system/setup/pos-payment-method` |

**حقول العلاقات في الفورم** تستخدم `app-auto-complete`، والأسماء تظهر بالعربي أو الإنجليزي حسب لغة الواجهة:
- **نقطة البيع:**
  - الفرع من `BranchService`.
  - الخزنة من `PosCashBoxService` والمخزن من `StoresService`، ويظهر منهما ما يخص الفرع المختار فقط.
- **الخزنة:**
  - الفرع.
  - نقطة البيع المفضلة من `PosTerminalService`، وتظهر نقاط الفرع المختار فقط.

### السياسات (شاشة مخصصة — ليست base-entry)
`/pos-system/pos-policy-value/:id`، المجلد `pages/pos-system/setup/pos-policy-value`.

- تختار الجهة (شركة / فرع / نقطة بيع / دور / مستخدم) ثم السجل.
- تظهر كل السياسات مجمعة حسب الفئة. لكل سياسة:
  - القيمة الموروثة ومصدرها.
  - قيمة هذه الجهة إن كانت مخصصة.
  - عدد الجهات التي خصصتها.
- تخصيص، أو إلغاء التخصيص (رجوع للموروث)، أو تراجع. الحفظ جماعي.
- نوافذ:
  - **تخصيص سياسات:** اختيار متعدد.
  - **نسخ من جهة أخرى:** مع خيار الاستبدال.
  - **معاينة السياسات الفعّالة:** لنقطة بيع + مستخدم.
- الخدمة: `services/pos-system/setup/pos-policy/pos-policy.service.ts` على `PosPolicy/*`:
  - `GetScopeMatrix`
  - `SaveScopeValues`
  - `CopyScopeValues`
  - `PreviewEffective`
- الترجمة تحت المفتاح `posPolicies` في `assets/i18n/ar.json` و`en.json`.

#### وصول التعديل إلى الديسكتوب
الديسكتوب (`Tab-MS-POS-Desktop`) يقرأ `PosPolicy/GetEffective?terminalId=` ويحفظ النتيجة محليًا لاستخدامها بدون اتصال (`src/offline/policies.ts`). لا يلزم إعادة فتح البرنامج؛ التحديث يتم:
- عند فتح/تغيير الوردية أو عند عودة الاتصال.
- تلقائيًا كل دقيقتين أثناء الاتصال.
- عند رجوع التركيز لنافذة البرنامج.
- يدويًا من «أدوات الكاشير ← تحديث السياسات» (يظهر وقت آخر تحديث، وشارة «محفوظة/افتراضية» إن لم تُحمَّل من الخادم).

السياسات المطبقة على الديسكتوب:

| الفئة | السياسات | السلوك |
|---|---|---|
| Offline | ALLOW_OFFLINE_SALE, OFFLINE_MAX_HOURS, OFFLINE_MAX_DISCOUNT_PERCENT, OFFLINE_RETURN_MODE, OFFLINE_EXCHANGE_MODE, OFFLINE_CARD_PAYMENT, OFFLINE_SUPERVISOR_APPROVAL | منع/تقييد البيع والمرتجع بدون اتصال |
| الخصم | MAX_LINE_DISCOUNT_PERCENT, MAX_INVOICE_DISCOUNT_PERCENT, DISCOUNT_OVER_LIMIT_MODE, ALLOW_LINE_DISCOUNT, ALLOW_INVOICE_DISCOUNT | زر الخصم يختفي إن لم يُسمح. التجاوز: `Deny` رفض، `ManagerPin` موافقة مشرف (LineDiscount / InvoiceDiscount) |
| الفاتورة | LINE_DELETE_MODE, LINE_EDIT_MODE, INVOICE_CANCEL_MODE, MAX_HELD_SALES | الحذف أو الوصول للكمية 0 يخضع لـ LINE_DELETE_MODE. **تقليل** الكمية يخضع لـ LINE_EDIT_MODE (الزيادة بيع عادي). الموافقات: LineDelete=11، LineEdit=12 |
| التسعير | PRICE_CHANGE_MODE | زر «السعر» على السطر. `Deny` مخفي، `AllowAboveMin` لا يقل عن سعر الكتالوج (لا يوجد حد أدنى منفصل على الجهاز)، `Allow` حر. تغيير السعر يلغي خصم السطر |
| العميل | CUSTOMER_REQUIRED | يمنع الدفع بدون عميل |
| الطباعة | AUTO_PRINT, PRINT_COPIES, REPRINT_MODE | عدد النسخ للإيصال الأصلي فقط. إعادة الطباعة بعد نجاح الطباعة: `Deny` / `ManagerPin` (ReprintReceipt) / `Allow`. إعادة المحاولة بعد فشل الطباعة ليست إعادة طباعة |
| الرصيد | STOCK_INSUFFICIENT_MODE, OFFLINE_STOCK_MODE, STOCK_CHECK_SCOPE | `Block` / `Warn` / `AllowNegative`. **لا أثر حاليًا:** الكتالوج لا يحمل رصيدًا (`Product.stockKnown` غير مفعّل) لعدم وجود API رصيد في Inventory |
| أخرى | ALLOW_SPLIT_PAYMENT, RETURN_DAYS, RETURN_APPROVAL_AMOUNT, CASH_MOVEMENT_MODE, CASH_VARIANCE_APPROVAL_AMOUNT, VAT_PERCENT, PRICES_INCLUDE_VAT, DUPLICATE_SCAN_MODE | — |

خصم الفاتورة يُرسل مبلغًا في `PosSubmitSaleDto.InvoiceDiscount` مع `InvoiceDiscountApprovedByUserId/At` عند الاعتماد. الخادم يتجاوز فحص `MAX_INVOICE_DISCOUNT_PERCENT` عند وجود معتمد مؤهل، ويسجل `PosSaleApproval` من نوع InvoiceDiscount.

كل مفتاح جديد يُستخدم في الديسكتوب يجب إضافته إلى `POLICY_DEFAULTS` بنفس القيمة الافتراضية في `PosPolicyCatalog`.

### تقارير (قراءة فقط)
| Route | نوع | Resource |
|---|---|---|
| `/pos-system/pos-sale/:id` | header + footer | `PosSaleH` / `PosSaleF` (`headerKey=saleid`) |
| `/pos-system/pos-return/:id` | header + footer | `PosReturnH` / `PosReturnF` (`headerKey=returnid`) |
| `/pos-system/pos-shift/:id` | simple form readonly | `PosShift` |
| `/pos-system/pos-operations-monitor/:id` | شاشة مخصصة | `PosOperationsMonitor` (انظر أدناه) |

### مراقبة عمليات نقاط البيع (`PosOperationsMonitor`)

شاشة قراءة فقط تعرض كل ما يحدث على الأجهزة في سجل موحد، مع ملخص وتنبيهات وتفاصيل كل عملية.

- **Backend:** `PosOperationsMonitorAppService`. كل الأكشنات GET، فتكفي صلاحية Access على `PosOperationsMonitor`:
  - `GetOverview`: مؤشرات الفترة مع مقارنتها بالفترة السابقة، ومنحنى النشاط (بالساعة حتى 48 ساعة، وبعدها باليوم)، وتوزيع الدفع، وعدادات التنبيهات، وحالة الأجهزة.
  - `GetEvents`: السجل الموحد. الفلترة والترتيب والتقسيم تتم في قاعدة البيانات لكل مصدر، ثم تُدمج النتائج. أقصى Skip هو 5000، وأقصى صفحة 2000 (للتصدير).
  - `GetSale` / `GetReturn` / `GetShift`: تفاصيل العملية.
  - `GetLookups`: قوائم الأجهزة والكاشيرية ووسائل الدفع.
- **مصادر السجل:**
  - المبيعات: `PosSaleH` بدون Draft.
  - المرتجعات والاستبدال: `PosReturnH`.
  - فتح وإغلاق الوردية: `PosShift`.
  - الإيداع والسحب وفتح الدرج: `PosShiftCashMovement`.
  - الموافقات: `PosSupervisorOverrideLog`.
  - مشاكل المزامنة: `PosSyncLog` بحالة Conflict أو Failed فقط.
- **أوفلاين:**
  - العملية أوفلاين إذا كان `IsOfflineOrigin` مفعّلًا، أو إذا بدأ `Notes`/`Reason` بـ `[OFFLINE]` في الحركات النقدية والموافقات.
  - المعلّق على الجهاز ولم يُرفع بعد لا يراه السيرفر. الشاشة تعرض فقط `PendingSyncCount` الذي يبلّغ به الجهاز عند إغلاق الوردية.
- **التنبيهات:** مبنية على حقائق مخزنة فقط، بلا تقديرات:

  | التنبيه | الشرط | المستوى |
  |---|---|---|
  | تعارض مزامنة | سجل مزامنة بحالة Conflict أو Failed | Attention |
  | فرق نقدية غير معتمد | فرق عند الإغلاق بدون اعتماد | Attention |
  | فرق نقدية معتمد | فرق عند الإغلاق مع اعتماد | Info |
  | وردية مفتوحة من يوم سابق | وردية مفتوحة بدأت قبل اليوم | Attention |
  | عمليات غير مرفوعة عند الإغلاق | `PendingSyncCount > 0` | Attention |
  | موافقة مرفوضة | حالة الموافقة Rejected | Attention |
  | معتمِد غير مؤهل وقت المزامنة | `[NOT-ELIGIBLE-AT-SYNC]` في السبب | Attention |
  | دفع بطاقة معلّق | حالة الدفع OfflinePending أو PendingReconciliation | Attention |
  | إعادة طباعة، موافقة، تدريب، إلغاء | — | Info |

  مستوى Critical محجوز ولا يُستخدم حاليًا.
- **ترحيل المخزون:** يظهر كمرحلة "غير مفعّل بعد" إلى أن يُكتب `PosInventoryPostingBatch` (`InventoryPostingEnabled`).
- **عمليات التدريب:** مستبعدة افتراضيًا، وتظهر عبر فلتر "تدريب" أو "إظهار عمليات التدريب".
- **الرابط يحفظ الحالة (Deep link):** كل الفلاتر وطريقة العرض والتفاصيل المفتوحة محفوظة في query params، مثلًا `?range=last7d&quick=1&open=sale:<id>`.
- **التحديث التلقائي:** كل 60 ثانية، ويتوقف عندما يكون التبويب مخفيًا. إذا نزل المستخدم في القائمة لا تُستبدل العناصر، بل يظهر زر "N عملية جديدة".

## API

- Local: `environment.baseUrlPOS` = `https://localhost:44349/api/v1/`
- Scope: أُضيف `POS` إلى `environment.scope`
- `GridList` بنفس نمط باقي الأنظمة (مثل HR):
  - `GetalldatabyfilterWithCount` يرجع `EntityWithCountDto` (عدد المرفقات والملاحظات).
  - `GridList` يبني الأعمدة عبر `IFieldDisplayService` من `TABFieldDictionary` حسب `menukey`.
  - **بدون صفوف Field Dictionary للشاشة لا تظهر أعمدة في الجريد.**

## تسجيل القائمة (Administration)

المصدر: `PosWebMenusDataSeedContributor` (`syscode = 70`)، وتم تطبيقه أيضًا على قاعدة `Dev-TABMS.Administration`.

| MenuKey | PageUrl | RelatedEntities | RelatedExtraApis | CRUD |
|---|---|---|---|---|
| PosTerminal | pos-system/pos-terminal | PosTerminal | PosCashBox.GetAllData, InvStores.GetAllData | نعم |
| PosPaymentMethod | pos-system/pos-payment-method | PosPaymentMethod | — | نعم |
| PosPolicyValue | pos-system/pos-policy-value | PosPolicyValue, PosPolicy, PosTenantSetup | PosTerminal.GetAllData, Branches.GetAllData | نعم |
| PosCashier | (بدون صفحة — للديسكتوب) | — | قراءة البيانات المرجعية | Access + Insert |
| PosCashBox | pos-system/pos-cash-box | PosCashBox | PosTerminal.GetAllData, Branches.GetAllData | نعم |
| PosSaleH | pos-system/pos-sale | — | — | قراءة فقط (+ PosSaleF فوتر) |
| PosReturnH | pos-system/pos-return | — | — | قراءة فقط (+ PosReturnF فوتر) |
| PosShift | pos-system/pos-shift | — | — | قراءة فقط |
| PosOperationsMonitor | pos-system/pos-operations-monitor | PosOperationsMonitor | Branches.GetAllData | قراءة فقط (تقارير، sort 70020) |

- `RelatedEntities` تمنح صلاحية الكيان كاملًا.
- `RelatedExtraApis` تمنح APIs قراءة محددة، تحتاجها قوائم الاختيار.
- الصلاحيتان لا تُطبقان على ABP إلا بعد **إعادة حفظ صلاحية المستخدم أو الدور**.
- قوائم الأدوار والمستخدمين في شاشة السياسات لا تحتاج صلاحية إضافية: `TABTenantRole` و`UserCustom` مستثناة من فحص الصلاحيات في Administration.

> إن كان Front على **cloud** (`dev-host`) وليس Admin المحلي، يجب تكرار التسجيل (القائمة + Field Dictionary) على بيئة السحابة.

## اختبار

`http://localhost:4200/pos-system/pos-terminal/{menuId}`
أو من القائمة بعد منح صلاحية Access على الشاشات.
