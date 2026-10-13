# تحليل أخطاء شاشة حساب التصفية (`EOService-calc`) — تحقيق فقط، من غير أي تعديل

> بتاريخ 2026-10-07. ده من قراءة الكود بس، من غير تشغيل.
> الاختصارات: `TB` = `components/base/base-tool-bar/base-tool-bar.component.ts`، `CT` = `components/base/base-create/base-create-tools/base-create-tools.component.ts`، `FORM` = `pages/hr-system/EO-service/eo-service-calc/eo-service-calc-form/eo-service-calc-form.component.ts`، `PAGE` = `.../eo-service-calc/eo-service-calc.component.ts`، `SVC` = باك `HRModule.Application/Services/EOService/EOServiceTrxHService.cs`.

## ملخص
| # | البند | الحالة | الإصلاح المقترح | يلمس Base؟ |
|---|---|---|---|---|
| 1 | «حفظ» في التعديل مش بيبعت request | **مؤكد** (بس لو الحركة ليها صفوف `EOServiceTrxF`) | `getEOSTrxFData` تملا `eosDetails` بدل `createBulkDataF` | لا |
| 1-أ | `enddate` قبل `startdate` (EOSS90) | **مؤكد** | توحيد التاريخ لـ `YYYY-MM-DD` في الفورم + validation في الباك | لا |
| 1-ب | الحركات (EOSS99/91) مش بتظهر في القائمة | **سبب مرجّح** (محتاج نتأكد من الداتابيز) | الباك ياخد `BranchId/SlipId` من الهيدر في Create ويحافظ عليهم في Update | لا (باك الشاشة بس) |
| 2 | بعد «حساب» في التعديل بيتبعت `CreateBulkData` بس | **مؤكد** + فيه خطأ في اسم الـ FK | نحفظ التفاصيل من `afterSaveWork/afterUpdateWork` بـ endpoint استبدال | لا (+ endpoint باك جديد) |
| 3 | `bulkFooterData` مش بيتفضى | **مؤكد** | `createBulkDataF.next([])` عند فتح/قفل الفورم في الشاشة | لا |
| 4 | `afterGetDataWork` و`GetById` بيتنادوا مرتين | **مؤكد** | نشيل النداء المكرر من اشتراك `editForm` في الفورم | لا (و`GetById` المكرر في Base يتأجل) |
| 5 | عمود قيمة العهدة فاضي | **مؤكد** | نغيّر اسم الخاصية لـ `custodyvalue` | لا |
| 6 | «مراجعة» في قائمة ⋮ بتتخطى `EOSReview` | **مؤكد** | نخفيها للشاشة دي (صلاحية) + حماية في الباك | لا |
| 7 | الحسابات بترجع أصفار ومفيش رصيد إجازات | **أسباب من الكود** | بيانات/إعدادات أكتر منها كود | — |

---

## 1) «حفظ» في التعديل مش بيبعت أي request — مؤكد
**السبب:**
- لما الحركة تتفتح، `FORM:321` في `getEOSTrxFData` بيعمل `createBulkDataF.next(eoservicefs)`، يعني array صفوف **من غير مفتاح فوتر**.
- `TB:390` بيخزنها في `bulkFooterData`.
- عند الحفظ، `TB:417` شايف إن `bulkFooterData` مش فاضية، فبيدخل مسار الـ bulk ويرجع **قبل** `TB:446` (`updateHeader`).
- الشكل ده مش multi-footer، فبيوصل لـ `TB:441` اللي هو `createBulkFooter(rows, null)`.
- `getFooterService(null)` بيرجّع `footerServiceInstance`، والشاشة مش بتمرره (`eo-service-calc.component.html` فيها `footerServices` بس). فبيحصل `console.error` و`return` (`TB:802-806`). **ولا request بيتبعت**.
- الشرط: الحركة يكون ليها صف `EOServiceTrxF` واحد على الأقل. لو `[]` المسار العادي بيشتغل.
- أثر جانبي: `getEOSTrxFData` مش بتملا `eosDetails`، فزرار «التفاصيل» في التعديل بيقول `noDataFound`. كمان بتجيب صف واحد بس (`GetalldatabyfilterWithCount(0, 1, …)`).

**الإصلاح (محلي، ملف FORM):**
```ts
// قبل
this.eoServiceTrxF.GetalldatabyfilterWithCount(0, 1, { eoservicetrxhid: eosTrxHId })...
  this.baseService.createBulkDataF.next(eoservicefs);
// بعد
this.eoServiceTrxF.GetalldatabyfilterWithCount(0, 1000, { eoservicetrxhid: eosTrxHId })...
  this.eosDetails = eoservicefs ?? [];   // للعرض بس — مش للحفظ
```
**الخطر:** منخفض، وفي الشاشة دي بس.

### 1-أ) `enddate` (2026-09-30) قبل `startdate` (2026-10-01) — مؤكد
**السبب:**
- `app-date-picker` بيستخدم `MomentDateAdapter`، والـ input مربوط بـ `[formControl]="control"` (date-picker.component.html). يعني الـ datepicker بيكتب **Moment** (نص الليل بتوقيت القاهرة) في الـ control الأول.
- بعد كده `(dateChange)` بيبعت نص `YYYY-MM-DD` (`date-picker.component.ts:143-153`).
- `FORM:86-88` بينسخ أول قيمة توصل `startdate` لـ `enddate` لو فاضي، والقيمة دي هي الـ Moment.
- بعدها `startdate` بيتبدّل بالنص، لكن `enddate` بيفضل Moment. وMoment لما يتحوّل JSON بيبقى `toISOString()` بتوقيت UTC، يعني `2026-09-30T21:00:00Z`. **ده بيطابق EOSS90 بالظبط**.
- الأثر: `EOSReview` بيستخدم `EndDate` كبداية للإيقاف (`SVC:647`) وفي الإجازة (`SVC:665`)، فالإيقاف بيبدأ يوم قبل التصفية.
- كمان `calcEndDate` بيحط `Date` (`vaction-section.component.ts:73`).
- ملحوظة: التولبار بياخد `getRawValue()` **قبل** `beforeSaveWork` (`TB:936` مقابل `TB:987`، و`TB:1071` مقابل `TB:1084`). فالتطبيع لازم يحصل في الفورم نفسه وقت تغيّر القيمة، مش في `beforeSaveWork`.

**الإصلاح (محلي):**
```ts
// FORM:86 — قبل
this.form.get('startdate')!.valueChanges.subscribe(v => { if (!this.form.get('enddate').value) this.form.get('enddate')!.setValue(v); });
// بعد
const toDateOnly = (v: any) => !v ? null : moment.isMoment(v) ? v.format('YYYY-MM-DD')
  : v instanceof Date ? v.toLocaleDateString('en-CA') : String(v).slice(0, 10);
this.form.get('startdate')!.valueChanges.subscribe(v => {
  const d = toDateOnly(v); if (!d) return;
  const end = this.form.get('enddate')!;
  if (!end.value || !this.isVacation || toDateOnly(end.value)! < d) end.setValue(d, { emitEvent: false });
});
// vaction-section.component.ts:73 — قبل: enddate: resultDate  ← بعد: enddate: resultDate.toLocaleDateString('en-CA')
```
+ في الباك (`Create`/`UpdateAsync` في SVC): نرفض `EndDate < StartDate`.
**الخطر:** منخفض. في الشاشة دي بس، وقيم التواريخ هتبقى نصوص `YYYY-MM-DD` زي باقي الـ pickers.

### 1-ب) EOSS99/EOSS91 مش بتظهر في القائمة — سبب مرجّح (محتاج نتأكد من الداتابيز)
- القائمة بتفلتر بالضبط على `BranchId == X-Branch-Id && SlipId == X-PaySlip-Id` (`SVC:185-189`).
- `Create` بياخد `R.BranchId = trxH.BranchId; R.SlipId = trxH.SlipId;` (`SVC:502-503`) من الـ body. الفورم **ملوش** `branchid/slipid` (`FORM` `buildForm`)، والتولبار مش بيضيف `branchid` غير لو المفتاح موجود (`TB:965-978`).
- الـ interceptors بتضيف headers بس، مش body. والـ `BeforeAfterActionFilter`/`BeforeSaveConfigeProcessor` بيولّدوا Serial/Draft بس، ومش بيملوا الفرع. فالقيمة بتتحفظ `Guid.Empty`.
- وكمان `UpdateAsync` بيعمل `ObjectMapper.Map(trxH, _currentEntity)` (`SVC:518`)، و`UpdateEOServiceTrxHDto` فيه `BranchId/SlipId` (السطور 16-18) ومش متعمله Ignore في AutoMapper (`EOServiceAutoMapperProfile.cs:67-75`). يعني **أي حفظ تعديل بيصفّر الفرع/القسيمة** والحركة بتختفي من القائمة.
- إن EOSS90 ظاهرة معناه إنه يا اتعملت من مسار مختلف، يا الفرع اتملى بطريقة مش متتبعة. **محتاج نتأكد:**
  `SELECT serial, branchid, slipid, draft, startdate, enddate, creationtime FROM eoservicetrxh WHERE serial IN ('EOSS90','EOSS91','EOSS99');`
- احتمالات تانية أضعف: «حفظ مؤقت» (localStorage بس، `CT:414-418`)، أو فشل Create بـ 400 (مثلاً `EndDate` `[Required]`).

**الإصلاح (باك الشاشة بس):**
```csharp
// SVC:502-503 — قبل
R.BranchId = trxH.BranchId; R.SlipId = trxH.SlipId;
// بعد (الـ helpers موجودة في BaseAppService.cs:75-87)
R.BranchId = GetBranchIdOrFromRequest(trxH.BranchId); R.SlipId = GetPaySlipIdOrFromRequest(trxH.SlipId);
// UpdateAsync — قبل الـ Map
if (trxH.BranchId == Guid.Empty) trxH.BranchId = _currentEntity.BranchId;
if (trxH.SlipId == Guid.Empty)  trxH.SlipId  = _currentEntity.SlipId;
```
**الخطر:** منخفض. الحركات اللي اتحفظت بـ `Guid.Empty` محتاجة سكريبت تصحيح بعد ما نتأكد.

## 2) بعد «حساب» في التعديل بيتبعت `CreateBulkData` بس — مؤكد (+ FK غلط)
- `FORM:208` بيعمل `createBulkDataF.next([{ 'EOServiceTrxF': details }])`، وده multi-footer. فبيدخل `TB:432-438` اللي هو `createBulkFooter(details,'EOServiceTrxF')`. ولأن `headerId` موجود بيروح لـ `proceed()` على طول (`TB:843-852`): **`CreateBulkData` بس، ومفيش `Update` للهيدر** (بيرجع قبل `TB:446`).
- `CreateBulkData` في الباك بيعمل insert بس (`EOServiceTrxFAppService.cs:236-242`)، فالصفوف القديمة **بتتكرر**.
- **FK غلط:** `createBulkFooter` بيدمج `headerParamsData = { eoserviceshid: id }` (`headerKey="eoserviceshid"`)، بينما `EOServiceTrxFDto` محتاج `EOServiceTrxHId`. فالـ FK بيوصل `Guid.Empty` وغالباً بيفشل بـ FK violation (في الإنشاء كمان). ده بيفسر ليه صفوف `EOServiceTrxF` غالباً مش موجودة أصلاً، وبالتالي البند 1 بيظهر قليل.

**الإصلاح (محلي + endpoint باك):** نوقف استخدام bulk التولبار للتفاصيل خالص.
```ts
// FORM:208 — قبل: this.baseService.createBulkDataF.next([{ 'EOServiceTrxF': this.eosDetails }]);
// بعد: this.eosDetailsDirty = true;   // نسيب this.eosDetails زي ما هي
// FORM — hooks التولبار بينده عليها أصلاً (TB:1002-1007 و TB:1099-1104)
afterSaveWork(id)   { this.persistEosDetails(id); }
afterUpdateWork(id) { this.persistEosDetails(id); }
private persistEosDetails(id) {
  if (!this.eosDetailsDirty) return;
  const rows = this.eosDetails.map(d => ({ ...d, eoservicetrxhid: id }));
  this.eoServiceTrxF.replaceForHeader(id, rows).subscribe(() => this.eosDetailsDirty = false);
}
```
+ باك: `EOServiceTrxFAppService.ReplaceForHeader(Guid headerId, List<EOServiceTrxFDto>)` في `[UnitOfWork]` (يمسح القديم ويعمل insert للجديد، ويحط `EOServiceTrxHId = headerId` صراحةً).
**الخطر:** منخفض-متوسط. محلي + endpoint جديد، ومش بيلمس Base. والحفظ بيرجع للمسار الطبيعي (`Create`/`Update`).

## 3) `bulkFooterData` مش بيتفضى — مؤكد
- `TB:385-393` بيتبدّل بس لما ييجي emit غير null. ومفيش reset في `createFormDisplay` (`TB:135-152`) ولا `cancel/clear` (`CT:286-298`) ولا بعد نجاح `createBulkFooter` (`TB:821-836`).
- يعني array من حركة فتحتها قبل كده ممكن يعطّل حفظ حركة جديدة (نفس سيناريو البند 1). و`[{EOServiceTrxF}]` من حساب قديم ممكن يتحفظ على حركة تانية.

**الإصلاح (محلي، ملف PAGE):**
```ts
// PAGE:50 داخل createFormDisplay.subscribe + في ngOnDestroy (PAGE:190)
this.baseService.createBulkDataF.next([]);   // [] بتعدّي شرط if(res) في TB:388 فبتصفّر bulkFooterData
```
بعد البند 2 الشاشة مش هتعمل emit أصلاً، والسطر ده حماية إضافية.
**الخطر:** منخفض. **ما نصفّرهاش في Base بعد الحفظ**، لأن فيه شاشات ممكن تعمل emit مرة واحدة وتحفظ أكتر من مرة.

## 4) `afterGetDataWork` و`GetById` مرتين — مؤكد
- `TB:1231` بيعمل `editForm.next(data)`، والفورم مشترك (`FORM:90-95`) فبينادي `afterGetDataWork`. **وكمان** `TB:1233` بينادي `formComponent.afterGetDataWork(data)`. النتيجة: Employee + EOServiceType + EOServiceTrxF مرتين.
- `GetById`: الأول `TB:1225`، والتاني من `CT:539` (`loadEntityDraft`) بعد `sendEditId` (`TB:150`).
- إضافي (Base): `editForm` معرّف كـ `new ReplaySubject<any>()` من غير حجم (`base.service.ts:92`، root). يعني أي subscriber جديد بيستقبل **كل** القيم القديمة، حتى اللي جاية من شاشات تانية.

**الإصلاح (محلي):** نشيل `this.afterGetDataWork(res);` من `FORM:95` ونسيب نداء التولبار، اللي بيغطي الفتح والاستعادة. باقي سطور الاشتراك (patch + grids) تفضل زي ما هي.
**Base (مقترح للنقاش بعدين):** `ReplaySubject(1)`، وإن `loadEntityDraft` ياخد من `editForm` بدل ما يعمل `GET`. **خطر متوسط** لأنه بيأثر على كل الشاشات.

## 5) عمود قيمة العهدة فاضي — مؤكد
`eos-custies-section.component.ts:61` اسم العمود `custodyvalue`، بينما السطر 95 بيحطها في `value: item.custodyvalue`.
```ts
// قبل: value: item.custodyvalue,   ← بعد: custodyvalue: item.custodyvalue,
```
ملاحظات: الباك بيرجّع `CustodyValue = c?.Value`، يعني قيمة تعريف العهدة مش مضروبة في `OutstandingQuantity` (`CustodyTrxHService.cs:367`)، وده قرار بيزنس. وكمان `totalcustody` في الفورم محدش بيملاه.
**الخطر:** منخفض جداً.

## 6) «مراجعة» في قائمة ⋮ العامة بتتخطى `EOSReview` — مؤكد
`CT:321-327` في `setReviewed` بيعمل `saveAsReviewed`، وبعدها `saveForm`، فبيوصل `Update` عادي فيه `reviewed=true`. ده من غير إيقاف ولا متغيرات ولا شهر، وبعده `EOSReview` بيرفض بـ «تمت المراجعة مسبقاً».

**المقترح:** **نخفيها على الشاشة دي** بدل ما نوجّهها لـ `eosReview`، لأن التوجيه محتاج Base يعرف endpoint خاص بالشاشة.
1. إعداد: نشيل صلاحية `canreview/cancancelreview` من منيو `EOService-calc` (مفيش كود). زراير `eo-service-lifecycle-actions` مش معتمدة على الصلاحية دي.
2. حماية في الباك (`SVC` `UpdateAsync`): نحافظ على `Reviewed/Posted` الحاليين ونرفض التعديل لو الحركة مراجعة/مصروفة:
```csharp
if (_currentEntity.Reviewed == true || _currentEntity.Posted == true) return BadApiResponse<UpdateEOServiceTrxHDto>(null, "لا يمكن التعديل بعد المراجعة/الصرف.");
trxH.Reviewed = _currentEntity.Reviewed; trxH.Posted = _currentEntity.Posted;
```
(ملحوظة: `updateHeader` في التولبار مش بيشيك على `statuscode` في الـ body، فرسالة الرفض ممكن تظهر كنجاح. علشان كده الإخفاء في الواجهة أساسي.)
- بديل في Base (opt-in): `@Input() hideReviewActions = false` يتمرر من Toolbar ← Create ← CreateTools. **آمن** (الافتراضي من غير تغيير) بس بيلمس 3 components من Base.

## 7) أصفار في `CalcEOService`/`CalcVacValue` ورسالة «يجب ألا يزيد عن 0» — أسباب من الكود
- **مدة الخدمة:** `SVC:380` بيحسب `eosDate - employee.RecruitingStartDate` (تاريخ التعيين في ملف الموظف، **مش** بداية العقد). لو التعيين = 2026-10-01 وتاريخ التصفية = 2026-10-01 تبقى 0 يوم، فالسنين 0، فكل سطور اللائحة `effectiveYears = 0` والمبلغ 0 (`SVC:397-418`).
- **الراتب (`EosSalary`/`MonthSalary`):** `PayContractFYearService.GetMonthlyElementTotalAsync` (السطور 42-100) بيرجّع 0 لو:
  - مفيش عقد بيغطي السنة،
  - أو مفيش `PayContractF` للعناصر المحددة في نوع التصفية (`PayElements`/`VacationSalaryElements`؛ لو فاضية بياخد كل العناصر)،
  - أو **مفيش صفوف `PayContractFYear` لسنة 2026** (المبالغ الشهرية `Amt1..Amt12`؛ والمطلوب هنا `Amt10`).
  - الاحتمال الأخير ده الأرجح لو المرتب 5000 في العقد بس جدول التوزيع السنوي متولّدش. ده غالباً «الجدول» المقصود؛ مفيش جدول اسمه Fouater في كود الـ HR.
  - **تم (2026-10-07):** الرواتب المستحقة `salariesowed` مبقتش بتيجي من `EosSalary`؛ بقت من `GetSalariesOwed` (التفاصيل في `EOS-CALC-HTTP-MAP.md`).
- **الإجازات:** `CalcVacValue` بيرجّع كل القيم 0 لو `VacationDefId` مش معرّف في نوع التصفية (`SVC:438`). ولو معرّف، بيدوّر على `VacEmpBalance` بيغطي تاريخ التصفية (`SVC:443`)، وموظف جديد غالباً ملوش رصيد مُرحّل، فبيرجع `CurrentBalance = 0`.
- **حد أيام الإجازة:** `FORM:80-82` بيحط `max(vacationaccrued)` = `CurrentBalance` = 0، فتظهر «يجب ألا يزيد عن 0».

**المقترح:** نتأكد من الداتا قبل أي كود: `RecruitingStartDate` للموظف، وصفوف `PayContractFYear` لسنة 2026، وعناصر نوع التصفية، و`VacationDefId`، ورصيد `VacEmpBalance`. كود (اختياري): رسالة واضحة بدل الأصفار لما الراتب = 0 أو مفيش رصيد.
