<div dir="rtl" markdown="1">

# التصفية / نهاية الخدمة (EOS) — شرح للمبرمجين

آخر تحديث: 2026-09-30 — مبني على قراءة الكود فقط (لم يُشغَّل شيء).

**اختصارات المسارات**
- `F:` = `Tab-MS-Front/src/app/tabms`
- `B:` = `Tab-MS Back-end/hr/TABMS.HR/modules/HRModule/src/HRModule.Application`
- `S:` = `B:/Services/EOService/EOServiceTrxHService.cs` (خدمة حركة التصفية، API `EOServiceTrxH`)

## 1. الفكرة باختصار
1. نعرّف **أنواع التصفية** (استقالة، نهاية عقد، إجازة...) وسياسة المكافأة لكل نوع.
2. في شاشة **حساب التصفية** نختار الموظف + النوع + تاريخ التصفية (`startdate` = `eosDate`) ونضغط احسب؛ الفرونت يجلب القيم من APIs ويحسب بعضها بنفسه.
3. الحفظ: القيم المحسوبة تُحفظ كما هي في `EOServiceTrxH` (الحفظ بـ `getRawValue()` فيشمل الحقول المعطلة).
4. **مراجعة**: إيقاف الموظف أو إجازة مدفوعة + رمي متغيرات في شهر المرتب المفتوح + حساب مرتب الموظف وتعليمه "مراجع".
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
| `vacationdays` أيام الإجازة | إدخال، أو من التاريخين `ceil(end − start)` (`vaction-section.component.ts:44`)؛ لا يزيد عن المتبقي |
| `vacationallowvalue` بدل الإجازة (المستحقات) | فرونت (`eo-service-calc-form.component.ts:183`): `(monthsalary / 30) × vacationdays` — بدون تقريب، ويُخزن `decimal(8,2)` |
| `flightvalue` التذكرة | `GetTicket_Loan_Amount.ticketvalue` |
| `loansvalue` السلف | `GetTicket_Loan_Amount.loanvalue` (عرض فقط) |
| `exchangedrewardbefore` مكافأة مصروفة سابقًا | `eoservicespentbefore` من `EOServiceBalances` (شاشة الأرصدة الافتتاحية) |
| `salariesowed` "رواتب مستحقة" | `CalcEOService.eossalary` — **هو راتب الشهر لعناصر النوع، وليس متأخرات** |
| `endofservicebenefitsvalue` مكافأة نهاية الخدمة | `CalcEOService.totalamount` (التفاصيل تُحفظ في `EOServiceTrxF`) |
| `periodyears/months/days` | `CalcEOService` |
| `managementfeesvalue` الرسوم الإدارية | مجموع `remainamount` للسطور المختارة. المتبقي من `ManagmentFees/GetEmpRemainingFees` (`B:/Services/EOService/ManagmentFeesAppService.cs:183`): `price ÷ أيام_الفترة × (todate − تاريخ_الخروج + 1)`، والسطور في `EOServicesManagmentFeesF` |
| `totalotherallowance` / `totalotherdeduction` | مجموع `amount` لسطور `EOServicesOtherElementsF` حسب نوع العنصر (2 استحقاق، 3 استقطاع) |
| العُهد (`eos-custies-section`) | `CustodyTrxH/GetUndeliveredCustodiesForEmployee` — عرض فقط؛ `totalcustody` لا يُحسب (يبقى 0) |
| `netvalue` الصافي | فرونت (`eo-service-calc.component.ts:114`): `المكافأة − المصروف_سابقًا − الرسوم_الإدارية + بدلات_أخرى − استقطاعات_أخرى` |

> الصافي **لا يشمل** بدل الإجازة ولا التذكرة ولا السلف ولا العهد. وهو مبني على `combineLatest` مع `skip(1)` على الحقول الخمسة، فلا يُحسب إلا بعد أن يتغير كل حقل منها مرتين؛ في تصفية الإجازة (المكافأة لا تتغير) قد يبقى 0.

## 4. المراجعة والصرف
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
4. **`vacationsalaryelementfields` بدون شاشة** ⇐ بدل الإجازة على كل عناصر العقد (استحقاقات − استقطاعات).
5. **أكثر من عقد في نفس السنة** ⇐ تُجمع مبالغ نفس العنصر من كل العقود.
6. **نقص الإعدادات = صفر بصمت**: لا `vacationdefid` ⇐ أصفار؛ لا عقد أو مبالغ سنة ⇐ راتب 0 ⇐ مكافأة 0؛ لا شهر مفتوح ⇐ حساب الشهر يُتخطى.
7. **إلغاء المراجعة لا يعكس أي أثر**، وإعادة المراجعة قد تكرر الإيقاف والمتغيرات (أو تفشل في الإجازة بسبب التداخل).
8. **تحديث رصيد الإجازة بدون `await`**: `B:/Services/Vacations/VacEmpTrxService.cs:253` ⇐ قد لا يُحفظ أو يسبب تعارضًا على نفس الـ DbContext.
9. **الصافي** لا يشمل بدل الإجازة/التذكرة/السلف/العهد، وقد لا يُحسب أصلًا بسبب `skip(1)`.
10. `salariesowed` اسمه مضلل؛ `vacationallowvalue` لا يُعاد حسابه لو تغيرت الأيام بعد "احسب"؛ `GetTicket_Loan_Amount` (GET) ينشئ صف أرصدة.
11. السلف تُعرض ولا تُخصم أو تُغلق؛ التذكرة والرسوم والبدلات الأخرى لا تُرحّل لأي مكان.

</div>