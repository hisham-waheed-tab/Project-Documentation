# خريطة استدعاءات HTTP — شاشة حساب التصفية (`hr-system/EOService-calc/:id`)

> النطاق: دوال HTTP فقط (بدون business logic).
> `{HR}` = `environment.baseUrlHR` (dev: `https://dev-hr-api.tab-erp.com/api/v1/`) — `{HOST}` = `environment.baseUrl`.
> كل Controllers الـ HR على `api/v1/[controller]/[action]` (من `BaseAppService`).
> المصدر: قراءة كود الفرونت والباك بتاريخ 2026-10-07 (بدون تشغيل).

## الملفات
| الطبقة | الملف |
|---|---|
| الصفحة | `pages/hr-system/EO-service/eo-service-calc/eo-service-calc.component.*` (داخل `app-base-tool-bar`) |
| الفلتر | `eo-service-calc-criteria/` |
| الفورم + الأقسام | `eo-service-calc-form/` ← `vaction-section`، `entilements-section`، `other-allowancesand-deductions-section`، `management-fees-section`، `eos-custies-section` |
| أزرار دورة الحياة | `eo-service-lifecycle-actions/` |
| خدمة الفرونت | `services/hr-system/EO-service/eo-service-trx-h.service.ts` (`EOServiceTrxHService` ← `BaseHttpService`) |
| الباك | `HRModule.Application/Services/EOService/EOServiceTrxHService.cs` (Controller = `EOServiceTrxH`). ملف `EOServiceTrxHAppService.cs` كله معلّق |

## الحقول
| الحقل | دالة الفرونت | Endpoint | Backend |
|---|---|---|---|
| الموظف `empid` (فلتر + فورم) | `input-with-sql-search` ← `EmployeeService.GetalldatabyfilterWithCount(0,1,{empcode})` (عند كتابة الكود أو بعد الاختيار من النافذة) | `GET {HR}Employee/GetalldatabyfilterWithCount?skipcount=0&maxresultcount=1&empcode=` | `EmployeeAppService.GetListAsyncWithCount` |
| ↳ نافذة البحث عن الموظف | لو الحقل له SQL في قاموس الحقول: `SqlSearchService.getDataBySqlQuery`، وإلا `setDropDownData` | `POST {HOST}SqlExecution/SearchWithFilterAsync` أو `GET {HR}Employee/GetalldatabyfilterWithCount?skipcount=0&maxresultcount=10000` | — |
| ↳ ملصق «جاهزية الراتب» جنب الموظف | `PayrollReadinessBadgeComponent` (`components/global/payroll-readiness-badge/`) ← `PayrollReadinessService.checkReadiness(0, 1, {empid, year, month})` بسنة/شهر `startdate` (لو فاضي: الشهر المفتوح من `CurrentMonthService`). بيستبعد الأكواد 5/6/15/23. الضغط بيفتح `PayrollReadinessIssuesDialogComponent` (من غير استدعاء جديد) | `GET {HR}PayrollReadiness/CheckReadiness?year=&month=&empid=&maxresultcount=1&skipcount=0` | `PayrollReadinessAppService.CheckReadiness` (فرع/كشف من الـ headers؛ بيرجع اللي عندهم مشاكل بس ← فاضي = جاهز) |
| الإدارة / الموقع / الوظيفة / الجنسية / آخر عودة / بداية التعيين | تتملى من رد الموظف نفسه (`onEmpSelected`) | — (مفيش استدعاء مستقل) | — |
| نوع التصفية `eoservicetypeid` (فلتر + فورم) | `app-auto-complete` ← `EOServiceTypeService.getAll()` | `GET {HR}EOServiceType/GetAllData` | `EOServiceTypeAppService.GetAllData` |
| نوع تذاكر الطيران | قائمة ثابتة `EOServiceTypeService.flightTicketsType` حسب نوع التصفية | — (محلي) | — |
| قيمة التذاكر `flightvalue`، المكافأة المصروفة قبل كده `exchangedrewardbefore`، السلف `loansvalue` | `getTicketLoansData` ← `getTicketLoanAmount` | `GET {HR}EOServiceTrxH/GetTicket_Loan_Amount?empid=&eostypeid=&eosdate=` | `GetTicketAndAdvanceValuesAsync` |
| إجمالي الإجازات / المستخدمة / المستحقة / بدل الإجازة | `getCalcVacValue` ← `calcVacValue` (لو النوع إجازة `isVacation`). أيام الإجازة من التاريخين = النهاية − البداية + 1 (محلي). تحذيرات نوع التصفية (مفيش `vacationdefid` / مفيش عناصر راتب إجازة) من بيانات النوع المحمّلة — من غير استدعاء جديد | `GET {HR}EOServiceTrxH/CalcVacValue?employeeid=&eostypeid=&eosdate=` | `CalcVacValue` |
| الرواتب المستحقة `salariesowed` (مخفي مع البقاء) | بتتملى **من «حساب» بس** من رد `eosCalc` (لقطة محفوظة على الحركة) | `POST {HR}EOServiceTrxH/EOSCalc?id=` | `EOSCalc` |
| ↳ زرار «تفاصيل» جنب الرواتب المستحقة | `EntilementsSectionComponent.getSalariesOwedDetails` ← `getSalariesOwed` ← نافذة `EosDetailsComponent` (الشهر، الإجمالي، الصافي، الأيام الفعلية، حالة المرتب) | `GET {HR}EOServiceTrxH/GetSalariesOwed?empid=&eosdate=[&trxid=]` | `GetSalariesOwed` (قراءة بس من FinalData) |
| مكافأة نهاية الخدمة، المدة (سنين/شهور/أيام) + تفاصيل المكافأة | `calcEOSDetails` ← `calcEOService` (لو النوع **مش** إجازة). في أنواع الإجازة الحقل وزرار التفاصيل مخفيين، و`clearGratuity` بتصفّرهم أول ما تختار النوع | `GET {HR}EOServiceTrxH/CalcEOService?employeeid=&eostypeid=&eosdate=` | `CalculateAsync` |
| الصافي `netvalue` | حساب محلي (المكافأة − المصروف قبل كده − الرسوم + البدلات − الاستقطاعات) | — | — |
| شبكة بدلات واستقطاعات أخرى | `shared-details-grid` ← `EOServicesOtherElementsFService.gridList` | `GET {HR}EOServicesOtherElementsF/GridList?menukey=&pageparameter=&fielddisplayon=&skipcount=&maxresultcount=&eoserviceshid=` | `EOServicesOtherElementsFAppService.GridList` |
| ↳ عمود العنصر (dropdown) | `getDDLData` ← `EOServicesOtherElementsService.getAll` | `GET {HR}EOServicesOtherElements/GetAllData` | `GetAllData` |
| إجمالي البدلات / الاستقطاعات الأخرى | `calcTotalOtherAllowancesandDeductionsF` | `GET {HR}EOServicesOtherElementsF/GetalldatabyfilterWithCount?skipcount=0&maxresultcount=1000&eoserviceshid=` | `GetListAsyncWithCount` |
| شبكة الرسوم الإدارية | `getEmpRemainingFeesData` ← `ManagmentFeesService.getEmpRemainingFees` | `GET {HR}ManagmentFees/GetEmpRemainingFees?employeeid=&exitdate=` | `ManagmentFeesAppService.GetRemainingFeesAsync` |
| ↳ الصفوف المختارة + إجمالي الرسوم (في التعديل بس) | `getManagementFeesFDataForEO` | `GET {HR}EOServicesManagmentFeesF/GetalldatabyfilterWithCount?skipcount=0&maxresultcount=1000&eoserviceshid=` | `GetListAsyncWithCount` |
| شبكة العهد المادية | `getCustodiesData` ← `CustodyTrxHService.getUndeliveredCustodiesForEmployee` | `GET {HR}CustodyTrxH/GetUndeliveredCustodiesForEmployee?empid=&untilDate=` | `CustodyTrxHService.GetUndeliveredCustodiesForEmployee` |
| جدول التصفيات (صفحة القائمة) | `app-base-grid` ← `EOServiceTrxHService.gridList` | `GET {HR}EOServiceTrxH/GridList?menukey=&fielddisplayon=1&skipcount=&maxresultcount=&<criteria>` | `EOServiceTrxHService.GridList` |

**`EOSCalc` (إجازة بدون مرتب / إنهاء خدمة — مش مع البقاء):**
- بيرفض لو: الحركة مراجعة/مصروفة، النوع مع البقاء، مفيش شهر مرتب مفتوح، أو شهر التصفية (`startdate`) قبل الشهر المفتوح. الرفض `statuscode 400` جوه الرد والفرونت بيعرض الرسالة.
- بيمسح إيقاف الحركة القديم (`Notes` تبدأ بـ `EOS:{id}`) وينشئ إيقاف جديد من `startdate` عبر `PayEmpStatusTrxService` (بيحدّث `LastLeaveDate`).
- `RunSalaryCalcSync` للموظف لكل شهر من المفتوح لحد شهر التصفية (فرع/كشف الحركة)؛ شهر FinalData بتاعه Reviewed/FinalClosed بيتخطى من غير رسالة.
- `salariesowed` = مجموع **الإجمالي** للأشهر دي من FinalData: `NetSalary + SumDeduction + Tax + EmpVal` (مفيش عمود Gross)، وبيتحفظ على الرأس. الرد: `{salariesowed, source, days, message, months[]}`.

**`GetSalariesOwed`:** قراءة بس من FinalData (من غير تقدير عقد) لنفس الحساب، الأشهر من المفتوح لحد شهر التصفية (لو المفتوح بعد شهر التصفية أو مش موجود: شهر التصفية بس). بيرجع `months[]`: `year, month, grosssalary, netsalary, actualdays, daysinmonth, payrollstatus, skipped`.

**إمتى بتتنده؟**
- العهد + الرسوم: أوتوماتيك لما (الموظف + `startdate`) يتغيروا — `EOServiceCalcComponent.ngAfterViewInit`.
- جاهزية الراتب: أوتوماتيك عند اختيار الموظف، تغيير `startdate`، وفتح الحركة للتعديل (debounce 400ms + switchMap، ومن غير تكرار لنفس الموظف/التاريخ). مسح الموظف يخفي الملصق.
- الرواتب المستحقة: **مفيش تحديث أوتوماتيك** (`watchSalariesOwed` اتشال) — بتتملى من «حساب» بس، أو من الحركة المحفوظة.
- فتح حركة للتعديل: `GET {HR}EOServiceTrxH/GetById?id=` (التولبار + `loadEntityDraft`)، وبعدها `afterGetDataWork`: Employee و EOServiceType (`GetalldatabyfilterWithCount?id=`) و `GET {HR}EOServiceTrxF/GetalldatabyfilterWithCount?eoservicetrxhid=`، + شبكة البدلات وإجمالياتها + العهد + الرسوم.

## الأزرار
| الزر | handler | دالة الخدمة | Endpoint | Backend | دوال HTTP داخلية / بعدها |
|---|---|---|---|---|---|
| **حساب التصفية** | `EoServiceCalcFormComponent.getEOServiceData` | **مش مع البقاء:** حفظ (`update` أو `create` ثم `createFormDisplay` لوضع التعديل) ← `eosCalc(id)` ← `getTicketLoanAmount` + (`calcVacValue` أو `calcEOService`). **مع البقاء:** نفس القديم من غير حفظ ولا `eosCalc` | `POST {HR}EOServiceTrxH/Update?id=` أو `/Create` ← `POST {HR}EOServiceTrxH/EOSCalc?id=` ← الـ GET اللي فوق | `UpdateAsync`/`Create` ← `EOSCalc` ← `GetTicketAndAdvanceValuesAsync` / `CalcVacValue` / `CalculateAsync` | الحفظ هنا للهيدر بس (التولبار لسه لازم تدوس «حفظ» عشان باقي الحقول والتفاصيل). الزرار disabled أثناء التنفيذ. `details` بتاعة `CalcEOService` بتتخزن عشان تتحفظ bulk في `EOServiceTrxF` |
| التفاصيل (جنب المكافأة) | `EntilementsSectionComponent.getEOServiceDetails` | — | مفيش (popup من نتيجة الحساب) | — | مخفي في أنواع الإجازة |
| **حفظ** | `BaseCreateToolsComponent.save` ← `baseService.saveForm` ← `BaseToolBarComponent` | `create` / `update` | جديد: `POST {HR}EOServiceTrxH/Create` — تعديل: `POST {HR}EOServiceTrxH/Update?id=` | `Create` / `UpdateAsync` | لو فيه تفاصيل مكافأة من الحساب: `Create` (auto) وبعده `POST {HR}EOServiceTrxF/CreateBulkData` (`EOServiceTrxFAppService.CreateBulkData`)، وبعدين الحركة تتفتح تعديل (`GetById`…) + `GridList` للقائمة |
| حفظ ونسخ | `saveAndCopy` | زي حفظ | زي حفظ | | |
| حفظ كمسودة | `saveAsDraft` | `create` بـ `draft=true` | `POST {HR}EOServiceTrxH/Create` | `Create` | بيظهر في الإنشاء بس، ولو الشاشة معمولها draft في المنيو |
| حفظ مؤقت (قائمة ⋮) | `temporarySave` | — | **مفيش HTTP** (localStorage) | | |
| استعادة (صفحة القائمة) | `retrieveLocalData` | — | مفيش HTTP مباشر | | بيندَه `afterGetDataWork` ← lookups الموظف/النوع/`EOServiceTrxF` |
| تفريغ / إلغاء | `clear` / `cancel` | — | مفيش HTTP | | |
| بحث (الفلتر) | `EoServiceCalcCriteriaComponent.applyCriteria` | `gridList` | `GET {HR}EOServiceTrxH/GridList?...&empid=&startdate=&enddate=&eoservicetypeid=&periodyears=&periodmonths=&perioddays=` | `GridList` | |
| تفريغ (الفلتر) | `clearData` | `gridList` | `GET {HR}EOServiceTrxH/GridList` | `GridList` | |
| **تم المراجعة** | `EoServiceLifecycleActionsComponent.onReview` | `eosReview(id)` | `POST {HR}EOServiceTrxH/EOSReview?id=` | `EOSReview` (يتأكد من الإيقاف وينشئه لو مش موجود + **إجازة «رصيد»** `VacEmpTrx` لنوع إجازة مش مع البقاء لو `vacationdays > 0` و`vacationdefid` موجود — بتخصم من الرصيد، ولو `Create` رفض المراجعة كلها بتفشل؛ أو إجازة مدفوعة مع البقاء + متغير إجمالي التصفية على `SetupBranch.EOSPayElementId` في **شهر التصفية** + حساب شهر التصفية بس + `Reviewed`؛ مش بيغيّر `salariesowed`) | لو الرد من غير `result`: `reloadTrx` ← `GET EOServiceTrxH/GetById?id=`. لو فيه `result`: `editForm.next` ← الفورم كله بيعيد تحميل lookups التعديل |
| **إلغاء المراجعة** | `onCancelReview` | `eosCancelReview(id)` | `POST {HR}EOServiceTrxH/EOSCancelReview?id=` | `EOSCancelReview` (يمسح المتغير + إيقاف الحركة + كل إجازات الحركة بالوسم (مدفوعة أو رصيد) مع إرجاع `Debit`، ويرجّع حالة FinalData، ويعيد حساب الأشهر من المفتوح لحد التصفية مع تخطي المراجَع/المغلق) | زي اللي فوق |
| **تم الصرف** | `onPayment` | `eosPayment(id)` | `POST {HR}EOServiceTrxH/EosPayment?id=` | `EosPayment` (صرفية عن طريق جاهزية المرتب + `Posted`) | زي اللي فوق |
| مراجعة / إلغاء المراجعة (قائمة ⋮ العامة) | `BaseCreateToolsComponent.setReviewed(true/false)` | `TABReviewLogService.createReviewLog` + مسار الحفظ | `{HOST}TABReviewLog/…` (اسم الـ action مش متأكد منه) + `POST {HR}EOServiceTrxH/Update?id=` ومعاه `reviewed` | `UpdateAsync` (**دلوقتي بيحتفظ بـ `reviewed`/`posted` من الداتابيز** فالمسار ده مبقاش بيغيّرهم؛ ولو الحركة مراجعة/مصروفة `Update` بيرفض) | |
| حفظ صف (بدلات واستقطاعات) | `shared-details-grid.save` ← `gridService.saveRow` ← `BaseToolBar.createFooter/updateFooter` | `EOServicesOtherElementsFService.create/update` | `POST {HR}EOServicesOtherElementsF/Create` أو `/Update?id=` | `Create` / `Update` | لو الحركة لسه متحفظتش: `EOServiceTrxH/Create` الأول. وبعدها `GridList` + إعادة الإجماليات |
| حذف صف (بدلات واستقطاعات) | `gridService.delete` ← `BaseToolBar.deleteRow` | `delete(id)` | `POST {HR}EOServicesOtherElementsF/Delete?id=` | `Delete` | `GridList` + إعادة الإجماليات |
| اختيار / إلغاء اختيار صف رسوم إدارية | `onRowSelect` / `onRowUnselect` (`saveOnSelect`) | `ManagementFeesFService.create` / `delete` | `POST {HR}EOServicesManagmentFeesF/Create` / `Delete?id=` | `Create` / `Delete` | `Create` للهيدر الأول لو الحركة جديدة |
| حذف حركة التصفية | — | — | **مش متاح**: `[canDelete]="false"` على `app-base-tool-bar`، ومفيش زرار حذف في الفورم | `DeleteByIdAsync` (لو اتنده: بيرفض للمراجَع/المصروف، وبيمسح المتغير + أي إجازة موسومة + إيقاف الحركة ويعيد حساب الأشهر) | |
| طباعة / حفظ وطباعة | `printReport` | — | عارض التقارير (متتبعتوش) | | قائمة التقارير: `ReportDesign/GetReportsByTabSystemMenu` |

> استدعاءات عامة من الإطار (مش خاصة بالشاشة): `ReportDesign/GetReportsByTabSystemMenu`، `Command/GetAll`، قاموس الحقول والصلاحيات.

## ملاحظات (مهمة للـ UAT)
1. زراير «تم المراجعة / إلغاء المراجعة / تم الصرف» بتظهر **بس** لما `*ngIf="trxId"` يتحقق، يعني الحركة تكون محفوظة ومفتوحة تعديل (`form.id`). في وضع الإنشاء مش بتظهر. واسم الزرار «تم المراجعة» مش «مراجعة».
   - تم المراجعة بيبقى disabled لو `busy || reviewed || posted`. إلغاء المراجعة وتم الصرف بيبقوا disabled لو `busy || !reviewed || posted`.
2. «مراجعة / إلغاء المراجعة» في قائمة ⋮ العامة بتظهر بس لو: وضع تعديل + صلاحية `canreview` / `cancancelreview` للشاشة + `reviewed` قيمته boolean (`false` / `true`). المسار ده بيعمل `Update` عادي.
3. بعد المراجعة (`reviewed = true`) الشاشة بتدخل view mode: حفظ / حفظ ونسخ / تفريغ بيختفوا.
4. ملاحظة من الكود (متجربتش وهي شغالة): في التعديل، `getEOSTrxFData` بيبعت صفوف `EOServiceTrxF` لـ `createBulkDataF` كـ array من غير مفتاح فوتر، فلما تدوس «حفظ» التولبار بيدخل `createBulkFooter(rows, null)` وملوش `footerServiceInstance`، و**مفيش أي request بيتبعت** (ولا حتى `Update` للهيدر). كمان بعد «حساب» لنوع مش إجازة وإنت في التعديل، بيتبعت `CreateBulkData` بس من غير `Update` للهيدر. و`bulkFooterData` مش بيتفضى بعد الحفظ.
5. `afterGetDataWork` بيتنده مرتين لما تفتح تعديل (من التولبار ومن اشتراك `editForm` في الفورم)، فالـ lookups بتتكرر. و`GetById` كمان بيتنده مرتين.
6. العهد: الفرونت بيحوّل `custodyvalue` لـ `value`، بس عمود الشبكة اسمه `custodyvalue`، فغالباً عمود القيمة بيطلع فاضي.
7. الحقل اللي اسمه «تاريخ البدء» `startdate` هو اللي بيتبعت `eosdate` في كل حسابات التصفية.
8. التسميات: الموجود في `ar.json` مكتوب زي ما هو، والباقي جاي من قاموس الحقول في الداتابيز فاتكتب بوصف عربي + اسم الحقل.
