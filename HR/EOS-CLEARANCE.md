<div dir="rtl" markdown="1">

# التصفية / نهاية الخدمة (EOS) — شرح للمبرمجين

آخر تحديث: 2026-10-07 — أُضيف تدفق «حساب التصفية» الجديد (EOSCalc) في §3.3 ووسم الآثار MySource/MyKey في §3.4، وإجازة «رصيد» عند المراجعة + ملصق جاهزية الراتب + تحذيرات نوع التصفية في §3.5–§3.7؛ باقي الأقسام من قراءة الكود في 2026-09-30.

**اختصارات المسارات**
- `F:` = `Tab-MS-Front/src/app/tabms`
- `B:` = `Tab-MS Back-end/hr/TABMS.HR/modules/HRModule/src/HRModule.Application`
- `S:` = `B:/Services/EOService/EOServiceTrxHService.cs` (خدمة حركة التصفية، API `EOServiceTrxH`)

## 1. الفكرة باختصار
1. نعرّف **أنواع التصفية** (استقالة، نهاية عقد، إجازة...) وسياسة المكافأة لكل نوع.
2. في شاشة **حساب التصفية** نختار الموظف + النوع + تاريخ التصفية (`startdate` = `eosDate`) ونضغط احسب؛ الفرونت يجلب القيم من APIs ويحسب بعضها بنفسه.
3. الحفظ: القيم المحسوبة تُحفظ كما هي في `EOServiceTrxH` (الحفظ بـ `getRawValue()` فيشمل الحقول المعطلة).
4. **مراجعة**: التأكد من الإيقاف (أو إجازة مدفوعة مع البقاء، أو إجازة «رصيد» للإجازة بدون مرتب) + متغير إجمالي التصفية في **شهر التصفية** + حساب شهر التصفية فقط وتعليم FinalData "مراجع". (الإيقاف وحساب الأشهر أصبحا في زر الحساب — §3.3)
5. **صرف**: إنشاء سطر صرف مرتب (مسودة) للموظف + `Posted = true`.

## 2. شاشة أنواع التصفية
`F:/pages/hr-system/systems-settings/clearance/clearance-types` — API `EOServiceType` + جريد السياسات `EOServiceTypePolicy`.
الـ Entity: `HRModule.Domain/Models/EOServiceEntities/EOServiceType.cs`

| الحقل | في الشاشة؟ | يُستخدم في | ملاحظة |
|---|---|---|---|
| `code`, `eotypearaname`, `eotypelatname` | نعم | العرض؛ الاسم العربي يدخل في ملاحظة الإيقاف والمتغيرات | |
| `flightticketstype` (0 بدون، 1 ذهاب، 2 ذهاب وعودة) | نعم | قيمة التذكرة (`GetTicket_Loan_Amount`) | يختار `ticketgovalue` أو `ticketfullvalue` من `EOServiceBalances` |
| `payelementfields` (عناصر المرتب، multi-select بكود العنصر) | نعم | **دوران**: (1) أساس راتب المكافأة، (2) العنصر الذي تُرمى عليه المتغيرات عند المراجعة | انظر المخاطر |
| `isvacation` | نعم | الشاشة تحسب بدل إجازة بدل المكافأة | |
| `vacationdefid` (نوع الإجازة) | يظهر لو `isvacation` | رصيد الإجازة + حركة الإجازة المدفوعة | إجباري للنوع "مع البقاء" |
| `eowithstay` (مع البقاء) | يظهر لو `isvacation` | المراجعة: إجازة مدفوعة بدل إيقاف الموظف | يعمل فقط مع `isvacation` |
| `vacationsalaryelementfields` | **غير موجود في الشاشة** | أساس راتب بدل الإجازة + عنصر رمي بدل الإجازة | دائمًا فارغ ⇐ يُحسب على **كل** عناصر العقد |
| `hasvacationallow` | مخفي | لا شيء | غير مستخدم |
| `vacationallow1percentage`, `vacationallow2percentage` | نعم | لا شيء | غير مستخدمين في أي حساب (يُقترح إخفاؤهما) |
| السياسات: `fromyear`, `toyear`, `daysperyear`, `factor` | جريد | معادلة المكافأة | |

## 3. شاشة حساب التصفية — مصدر كل حقل
`F:/pages/hr-system/EO-service/eo-service-calc/eo-service-calc-form` والأقسام: `vaction-section`, `entilements-section`, `eos-custies-section`, `management-fees-section`, `other-allowancesand-deductions-section`.

زر الحساب `getEOServiceData()` (`eo-service-calc-form.component.ts:218`): يستدعي دائمًا `GetTicket_Loan_Amount`، ثم `CalcVacValue` لو النوع إجازة، وإلا `CalcEOService`.

### 3.1 APIs الحساب
| API | الدالة | ماذا ترجع وكيف |
|---|---|---|
| `GetTicket_Loan_Amount` | `S:288` | من `EOServiceBalances` (صف لكل موظف، **يُنشأ بأصفار لو غير موجود رغم أنه GET**): `ticketvalue` حسب نوع التذكرة، و`eoservicespentbefore`. و`loanvalue` = مجموع أقساط السلف غير المحسوبة وغير الملغاة/الموقوفة (`PayLoansH/F`) — **كل المتبقي بدون حد تاريخ** (`S:319`) |
| `CalcEOService` | `S:346` | المدة من `RecruitingStartDate` حتى التاريخ: سنين = أيام÷365، شهور = الباقي÷30، أيام = الباقي. `eossalary` = إجمالي عناصر `payelementfields` لشهر/سنة التاريخ. لكل سياسة: `(eossalary / 30) × daysperyear × سنوات_فعالة × factor` حيث `سنوات_فعالة = min(السنين, toyear) − fromyear`. تقريب الإجمالي لرقمين عشريين. **السنين الكاملة فقط** |
| `CalcVacValue` | `S:410` | لو للنوع `vacationdefid`: صف `VacEmpBalance` الذي يغطي التاريخ ⇐ `currentbalance = Credit` (عمود محسوب مخزن = `VacBalance − Debit`)، `consumedbefore = Debit`. و`monthsalary` = إجمالي `vacationsalaryelementfields` (أو كل العناصر) للشهر. غير ذلك: أصفار |

**إجمالي العناصر الشهري** `GetMonthlyElementTotalAsync` (`B:/Services/PayRoll/Contract/PayContractFYearService.cs:41-118`): كل عقود الموظف (`PayContractH`) المتداخلة مع السنة ⇐ سطور العناصر (`PayContractF`) ⇐ مبالغ السنة `PayContractFYear.Amt{الشهر}`. نوع العنصر 1 و2 يُجمع، 3 يُطرح، تقريب رقمين. قائمة عناصر فارغة ⇐ كل العناصر.

### 3.2 الحقول
| الحقل (القسم) | المصدر |
|---|---|
| `vacationaccrued` المتبقي (إجازات) | `CalcVacValue.currentbalance` |
| `vacationdaysused` المستخدم | `consumedbefore` |
| `vacationtotalaccrued` الإجمالي | فرونت: `consumedbefore + currentbalance` |
| `vacationdays` أيام الإجازة | إدخال، أو من التاريخين `end − start + 1` شامل اليومين (`vaction-section.component.ts` `calcVacDays`)؛ والعكس `enddate = startdate + الأيام − 1` (`calcEndDate`) — نفس عدّ `VacEmpTrxService.Create`؛ لا يزيد عن المتبقي (`Credit`) |
| `vacationallowvalue` بدل الإجازة (المستحقات) | فرونت (`eo-service-calc-form.component.ts:183`): `(monthsalary / 30) × vacationdays` — بدون تقريب، ويُخزن `decimal(8,2)` |
| `flightvalue` التذكرة | `GetTicket_Loan_Amount.ticketvalue` |
| `loansvalue` السلف | `GetTicket_Loan_Amount.loanvalue` (عرض فقط) |
| `exchangedrewardbefore` مكافأة مصروفة سابقًا | `eoservicespentbefore` من `EOServiceBalances` (شاشة الأرصدة الافتتاحية) |
| `salariesowed` "رواتب مستحقة" | لقطة من `EOSCalc` = مجموع Gross من FinalData (الشهر المفتوح..شهر التصفية). مخفي مع البقاء. زر «تفاصيل» بجانبه ⇐ `GetSalariesOwed` (قراءة فقط) — §3.3 |
| `endofservicebenefitsvalue` مكافأة نهاية الخدمة | `CalcEOService.totalamount` (التفاصيل تُحفظ في `EOServiceTrxF`) |
| `periodyears/months/days` | `CalcEOService` |
| `managementfeesvalue` الرسوم الإدارية | مجموع `remainamount` للسطور المختارة. المتبقي من `ManagmentFees/GetEmpRemainingFees` (`B:/Services/EOService/ManagmentFeesAppService.cs:183`): `price ÷ أيام_الفترة × (todate − تاريخ_الخروج + 1)`، والسطور في `EOServicesManagmentFeesF` |
| `totalotherallowance` / `totalotherdeduction` | مجموع `amount` لسطور `EOServicesOtherElementsF` حسب نوع العنصر (2 استحقاق، 3 استقطاع) |
| العُهد (`eos-custies-section`) | `CustodyTrxH/GetUndeliveredCustodiesForEmployee` — عرض فقط؛ `totalcustody` لا يُحسب (يبقى 0) |
| `netvalue` الصافي | فرونت (`eo-service-calc.component.ts:114`): `المكافأة − المصروف_سابقًا − الرسوم_الإدارية + بدلات_أخرى − استقطاعات_أخرى` |

> الصافي **لا يشمل** بدل الإجازة ولا التذكرة ولا السلف ولا العهد. وهو مبني على `combineLatest` مع `skip(1)` على الحقول الخمسة، فلا يُحسب إلا بعد أن يتغير كل حقل منها مرتين؛ في تصفية الإجازة (المكافأة لا تتغير) قد يبقى 0.

### 3.3 تدفق «حساب التصفية» المحدّث (EOSCalc)
**إجازة بدون مرتب / إنهاء خدمة** (أي نوع ليس `eowithstay`):
1. الفرونت يحفظ الحركة أولًا (`update` أو `create` ثم وضع التعديل) ثم `POST EOServiceTrxH/EOSCalc?id=`.
2. السيرفر: يرفض لو مراجعة/مصروفة، أو لا يوجد شهر مرتب مفتوح (`PayCurrentMonth`)، أو شهر التصفية (`startdate`) قبل الشهر المفتوح.
3. يحذف إيقاف الحركة السابق ثم ينشئ إيقافًا جديدًا من `startdate` (يوم الإيقاف) عبر `PayEmpStatusTrxService` (يحدّث `LastLeaveDate`). الربط بالحركة عبر `MySource = 'EOServiceTrxH'` + `MyKey = id الحركة` (§3.4).
4. لكل شهر من المفتوح حتى شهر التصفية: `RunSalaryCalcSync` للموظف (فرع/كشف الحركة، 1..آخر يوم). صف FinalData بحالة Reviewed/FinalClosed ⇐ يُتخطى بصمت.
5. `salariesowed` = Σ Gross للأشهر نفسها، حيث Gross = `NetSalary + SumDeduction + Tax + EmpVal` (لا يوجد عمود Gross)، ويُحفظ لقطة على الرأس.
6. أيام العمل: `fn_emp_actual_workdays_ctx` يخصم أيام حركات `PayEmpStatusTrx` غير المحذوفة (من `fromdate` شاملًا) ⇐ شهر التصفية = الأيام قبل يوم الإيقاف.
7. بعده الفرونت يكمل `GetTicket_Loan_Amount` + `CalcVacValue`/`CalcEOService` كما كان.

**مع البقاء (`eowithstay`)**: بدون إيقاف وبدون حساب أشهر؛ `salariesowed` مخفي؛ يُصرف بدل الإجازة فقط.

**بعد ذلك:** المراجعة تتأكد من وجود الإيقاف (وتنشئه لو غير موجود) وترمي المتغير على شهر التصفية وتعيد حساب شهر التصفية فقط، ولا تغيّر `salariesowed`. الحركة مقفلة للتعديل بعد المراجعة/الصرف (`Update` يرفض). إلغاء المراجعة وحذف المسودة: حذف المتغير + إيقاف الحركة ثم إعادة حساب الأشهر (مع تخطي المراجَع/المغلق).

### 3.4 وسم آثار التصفية (MySource / MyKey)
كل سجل تنشئه التصفية في جداول أخرى يُوسم بمصدره (Migration `20261007100000_Add_EOS_MySource_MyKey` — **لم تُطبَّق بعد**):

| الجدول | من ينشئه | الأعمدة والقيم |
|---|---|---|
| `PayEmpStatusTrx` (إيقاف) | `EOSCalc` (و`EOSReview` لو غير موجود) | `mysource = 'EOServiceTrxH'`، `mykey = id الحركة` |
| `VacEmpTrx` (إجازة مدفوعة — مع البقاء، أو إجازة «رصيد» — إجازة بدون مرتب) | `EOSReview` | نفس القيم |
| `PayVariableElements` (متغير إجمالي التصفية) | `EOSReview` | `mysource = id الحركة` (عمود uuid قديم)، `mysourcetable = 'EOServiceTrxH'` |
| `SalaryPayment` (سند الصرف) | `EosPayment` | `mysource = 'EOServiceTrxH'`، `mykey = id الحركة` |

- الأطوال: `mysource`/`mysourcetable` = `varchar(64)`، `mykey` = `uuid`؛ فهارس `(mykey, mysource)` و`(mysource, mysourcetable)`.
- لا تُوسم: `FinalData` (يُعاد حسابه)، `Employee`، `VacEmpBalance`، سطور `SalaryPaymentLine` (تُعرف من الرأس).
- الحذف/الإلغاء يبحث بالوسم أولًا، ثم علامة `Notes` القديمة `EOS:{id}`، ثم مطابقة التاريخ للحركات الأقدم. إلغاء المراجعة يحذف إجازات الحركة (مدفوعة أو «رصيد») ويُرجع `VacEmpBalance.Debit`؛ وحذف المسودة يحذف أي إجازة موسومة احتياطيًا. كذلك أصبح `VacEmpTrxService` ينتظر (`await`) تحديث الرصيد `UpdateDebit` في الإنشاء/التعديل/الحذف (كان يُستدعى بدون انتظار فقد يضيع التحديث).
- شاشة «مراجعة وصرف التصفيات» (`hr-system/EOService-review/:id`) تعرض آثار الحركة بنفس الوسم عبر `GET EOServiceTrxH/GetEOSEffects?id=`، وتقرأ القائمة من `GetReviewList` (الحالة مشتقة: مسودة / محسوبة = يوجد إيقاف موسوم / مراجَعة / مصروفة — بدون عمود جديد)، وأضافت `POST EOServiceTrxH/EOSCancelCalc?id=` لعكس الحساب قبل المراجعة (حذف الإيقاف + إعادة حساب الأشهر + `salariesowed = null`). التفاصيل: `EOS-REVIEW-SCREEN-HTTP-MAP.md`.

### 3.5 إجازة «رصيد» عند المراجعة (إجازة بدون مرتب)
- **متى:** في `EOSReview` فقط، للنوع `isvacation = true` و**ليس** `eowithstay`. «إنهاء خدمة» لا يأخذ إجازة.
- **تُتخطى بصمت** لو `vacationdefid` فارغ أو `vacationdays = 0`، أو لو يوجد سطر موسوم للحركة (لا تكرار).
- **السطر:** `VacEmpTrx` بنوع دفع `Vacation (0)` = «رصيد» (وليس «مدفوع» = `paid (1)`)، نوع الإجازة = `vacationdefid`، من `startdate` لعدد `vacationdays` (النهاية = البداية + الأيام − 1)، موسوم `MySource = 'EOServiceTrxH'` + `MyKey = id الحركة`. الكود: `ApplyBalanceVacationAsync` في `S:`.
- **الإنشاء** عبر `VacEmpTrxService.Create`: يزيد `VacEmpBalance.Debit` (يخصم من الرصيد). لو الرصيد لا يكفي، أو الإجازة متقاطعة مع إجازة أخرى، أو لا يوجد رصيد يغطي الفترة كلها ⇐ المراجعة **تفشل كلها** برسالة `Create` (UnitOfWork يرجع كل شيء).
- **لا تؤثر على المرتب:** حساب المرتب لا يقرأ `VacEmpTrx` (يعتمد على الإيقاف `PayEmpStatusTrx` و`LastLeaveDate`)، فلا إيقاف مكرر ولا خصم مرتب.
- **العكس:** `EOSCancelReview` (وحذف المسودة احتياطيًا) ⇐ `RemoveEosVacationsByTagAsync`: حذف كل إجازات الحركة بالوسم مع إرجاع `Debit`.
- نافذة «تأثير التصفية» تعرض نوع الدفع: «رصيد» أو «مدفوع».

### 3.6 ملصق جاهزية الراتب بجوار الموظف
- مكوّن مستقل `F:/components/global/payroll-readiness-badge/` (نسخة منفصلة؛ شاشة `payroll-readiness` لم تتغير).
- يستدعي `GET PayrollReadiness/CheckReadiness` (عبر `PayrollReadinessService.checkReadiness(0, 1, {empid, year, month})`) بسنة/شهر **تاريخ التصفية** (`startdate`)؛ لو التاريخ فارغ ⇐ الشهر المفتوح. يتحدث عند اختيار الموظف وتغيير التاريخ وفتح الحركة للتعديل (debounce 400ms + switchMap)، ويختفي عند مسح الموظف.
- الـ API يرجع الموظفين الذين لديهم مشاكل فقط ⇐ قائمة فارغة = «جاهز».
- في شاشة التصفية فقط تُستبعد الأكواد الناتجة عن التصفية نفسها قبل حساب الحالة وقبل الديالوج: 5 و6 (إنهاء خدمة قبل/خلال الشهر)، 15 و23 (إجازة قبل/خلال الشهر).
- الحالات: جاهز (أخضر) / بيانات ناقصة (أحمر) / يحتاج مراجعة (برتقالي) / تعذّر الفحص. الضغط (عند وجود مشاكل) يفتح نفس `PayrollReadinessIssuesDialogComponent` بنفس خيارات الجريد.
- مفيد لتفسير **بدل الإجازة = 0**: الأكواد 1/2 (لا عقد)، 11 (لا عنصر أساسي)، 12 (لا مبالغ سنة العقد للشهر) هي غالبًا سبب `monthsalary = 0` في `CalcVacValue`.

### 3.7 تحذيرات نوع التصفية في قسم الإجازات
تظهر لأنواع الإجازة فقط (`isvacation`)، من بيانات النوع الموجودة في الفرونت (بدون API جديد):
- لا يوجد `vacationdefid` ⇐ لا رصيد ولا بدل إجازة، ولا إجازة تُخصم عند المراجعة (ومع البقاء: المراجعة ترفض).
- لا توجد عناصر راتب إجازة (`vacationsalaryelementfields`) ⇐ راتب الإجازة يُحسب من كل عناصر العقد. ملاحظة: الحقل غير موجود في شاشة الإعداد بعد، فهذا التحذير سيظهر غالبًا لكل أنواع الإجازة حتى يُضاف.

## 4. المراجعة والصرف
> ⚠️ §4.1 و§4.2 أدناه وصف قديم (2026-09-30)؛ السلوك الحالي في §3.3.

### 4.1 مراجعة `EOSReview` (`S:521`، داخل UnitOfWork)
الشرط: غير مراجعة وغير مصروفة. ثم بالترتيب:

| الخطوة | ما يُكتب | مصدر القيم |
|---|---|---|
| 1-أ: النوع `isvacation` و`eowithstay` | `ApplyPaidVacationAsync` (`S:633`): حركة إجازة مدفوعة `VacEmpTrx` من `startdate` لعدد `vacationdays` (أو حتى `enddate`) + زيادة `Debit` في `VacEmpBalance` | نوع الإجازة = `vacationdefid` (خطأ لو فارغ)، عبر `VacEmpTrxService.Create` |
| 1-ب: غير ذلك | `ApplyEmployeeStopAsync` (`S:614`): حركة إيقاف موظف `PayEmpStatusTrx` (مراجعة) من `enddate` أو `startdate` | `Reason = 0` ثابت في الكود، الملاحظة = اسم النوع |
| 2 | `ApplyVariablesAsync` (`S:661`): متغيرات `PayVariableElements` في **شهر المرتب المفتوح** (`PayCurrentMonth`)، مراجعة، `MySource = id الحركة`، القيمة `Math.Abs` (الإشارة من نوع العنصر) | الجدول التالي |
| 3 | `ApplyMonthReviewedAsync` (`S:721`): حساب مرتب الموظف للشهر المفتوح (`RunSalaryCalcSync`) ثم إجراءات دورة المرتب له فقط: Calculate ⇐ RunCheck ⇐ CloseForReview ⇐ MarkReviewed | لو لا يوجد شهر مفتوح: يتخطى بصمت |
| 4 | `Reviewed = true` | |

**عنصر كل متغير** (`ResolveElementIdAsync`، `S:796`): أول كود في القائمة (بالترتيب المحفوظ) له عنصر في `PayElements` ولم يُستخدم في نفس الحركة. **لا توجد أكواد ثابتة ولا بحث بالاسم.**

| المتغير | الشرط | قائمة الأكواد |
|---|---|---|
| «بدل إجازة» | `VacationAllowValue ≠ 0` | `vacationsalaryelementfields`؛ ولأنها فارغة دائمًا يُستخدم البديل `payelementfields ∪ vacationsalaryelementfields` |
| «مكافأة نهاية خدمة» | `EndOfServiceBenefitsValue ≠ 0` | `payelementfields` |
| «صافي تصفية» | فقط لو السابقان = 0 و`NetValue ≠ 0` | `payelementfields` |

لو لم يوجد عنصر ⇐ خطأ «عيّن عناصر المرتب على نوع التصفية». لو توجد قيم ولا يوجد شهر مفتوح ⇐ خطأ.

**ما لا تفعله المراجعة:** لا ترمي التذكرة ولا الرسوم الإدارية ولا البدلات/الاستقطاعات الأخرى ولا العهد؛ لا تغلق أو توقف السلف؛ لا تحدّث `eoservicespentbefore`؛ لا تنشئ قيود GL؛ لا تنهي العقد.

### 4.2 إلغاء المراجعة `EOSCancelReview` (`S:568`)
يغيّر `Reviewed = false` **فقط** (ممنوع بعد الصرف). لا يلغي الإيقاف ولا الإجازة ولا المتغيرات ولا حالة مرتب الشهر.

### 4.3 الصرف `EosPayment` (`S:593`)
الشرط: مراجعة وغير مصروفة، للموظف بنك، ويوجد شهر مفتوح.
- `ApplySalaryPaymentAsync` (`S:762`): `SalaryPaymentReadiness.GenerateFromReadiness` لهذا الموظف فقط، للشهر المفتوح، نسبة 100%، بنك الموظف، تاريخ الصرف = `enddate` أو `startdate`، المرجع = رقم التصفية، **مسودة** (`Draft = true`، بدون إرسال للمراجعة). أي أنه يصرف صافي مرتب الشهر كله (بما فيه المتغيرات المرمية).
- `Posted = true`.
- لا قيود GL في هذا الكود (إن وُجدت فمن دورة صرف المرتبات لاحقًا — لم تُتتبع).

## 5. ثغرات ومخاطر
1. **السيرفر يثق في قيم الفرونت**: `VacationAllowValue` و`EndOfServiceBenefitsValue` و`NetValue` تُحفظ كما أُرسلت ويُرمى بها متغيرات بدون إعادة حساب.
2. **قاسم 30 ثابت** (بدل الإجازة والمكافأة) و365 للسنة، والمكافأة بالسنين الكاملة فقط.
3. **`payelementfields` له دوران**: أساس الراتب **و**عنصر رمي المكافأة/بدل الإجازة ⇐ غالبًا يُرمى المتغير على أول عنصر (مثل الأساسي). يُقترح إعدادان منفصلان: عنصر رمي المكافأة وعنصر رمي بدل الإجازة.
4. **`vacationsalaryelementfields` بدون شاشة** ⇐ بدل الإجازة على كل عناصر العقد (استحقاقات − استقطاعات). شاشة الحساب تعرض تحذيرًا الآن (§3.7).
5. **أكثر من عقد في نفس السنة** ⇐ تُجمع مبالغ نفس العنصر من كل العقود.
6. **نقص الإعدادات = صفر بصمت**: لا `vacationdefid` ⇐ أصفار؛ لا عقد أو مبالغ سنة ⇐ راتب 0 ⇐ مكافأة 0؛ لا شهر مفتوح ⇐ حساب الشهر يُتخطى.
7. **إلغاء المراجعة لا يعكس أي أثر**، وإعادة المراجعة قد تكرر الإيقاف والمتغيرات (أو تفشل في الإجازة بسبب التداخل).
8. **تحديث رصيد الإجازة بدون `await`**: `B:/Services/Vacations/VacEmpTrxService.cs:253` ⇐ قد لا يُحفظ أو يسبب تعارضًا على نفس الـ DbContext.
9. **الصافي** لا يشمل بدل الإجازة/التذكرة/السلف/العهد، وقد لا يُحسب أصلًا بسبب `skip(1)`.
10. `salariesowed` اسمه مضلل؛ `vacationallowvalue` لا يُعاد حسابه لو تغيرت الأيام بعد "احسب"؛ `GetTicket_Loan_Amount` (GET) ينشئ صف أرصدة.
11. السلف تُعرض ولا تُخصم أو تُغلق؛ التذكرة والرسوم والبدلات الأخرى لا تُرحّل لأي مكان.

</div>