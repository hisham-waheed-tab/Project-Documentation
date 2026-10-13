# خريطة استدعاءات HTTP — شاشة «مراجعة وصرف التصفيات» (`hr-system/EOService-review/:id`)

> النطاق: استدعاءات HTTP وخط سير كل زرار (بدون تفاصيل الـ business logic اللي متشرحة في `EOS-CLEARANCE.md`).
> `{HR}` = `environment.baseUrlHR` — `{HOST}` = `environment.baseUrl`. كل Controllers الـ HR على `api/v1/[controller]/[action]`.
> الشاشة **قراءة فقط** (مفيش إضافة/تعديل/حذف)؛ التعديل بيتعمل من شاشة حساب التصفية (زرار العين).
> المصدر: الكود بتاريخ 2026-10-07 (متجربش وهو شغال).

## الملفات
| الطبقة | الملف |
|---|---|
| الصفحة | `pages/hr-system/EO-service/eo-service-review/eo-service-review.component.*` (standalone، جدول `mat-table` + بطاقات حالة + ترقيم `app-custom-pagination`) |
| الفلتر | `eo-service-review/eo-service-review-criteria/` (`applyCriteria` ← `BaseService.applyCriteria`، `clearData` ← `refreshTable`) |
| نافذة تأثير التصفية | `eo-service-review/eo-service-effects-dialog/` |
| الموديل | `models/hr-system/EO-service/eo-service-review.ts` |
| خدمة الفرونت | `services/hr-system/EO-service/eo-service-trx-h.service.ts` (اتضاف: `getReviewList`، `eosCancelCalc`، `getEOSEffects`) |
| الـ Route | `pages/hr-system/hr-system-routing.module.ts` ← `EOService-review/:id` (`PermissionGuard`، `:id` = id الصفحة في `TABSystemMenu`) |
| الباك | `HRModule.Application/Services/EOService/EOServiceTrxHService.cs` (`GetReviewList`، `EOSCancelCalc`، `GetEOSEffects`) + `HRModule.Application.Contracts/DTO/EOService/EOServiceTrxH/EOServiceReviewDto.cs` |
| المنيو / Field Dictionary | بيتعملوا من زميل تاني في الفريق (مش ضمن الشغل ده) |

## الأعمدة والفلاتر
| العنصر | المصدر | Endpoint | Backend |
|---|---|---|---|
| تحميل الجدول + بطاقات الحالة + الإجماليات | `EOServiceReviewComponent.loadList` ← `getReviewList(params)` | `GET {HR}EOServiceTrxH/GetReviewList?empid=&eoservicetypeid=&fromdate=&todate=&status=&skipcount=&maxresultcount=` (هيدر `X-Branch-Id` / `X-PaySlip-Id` من `hr-context.interceptor`) | `GetReviewList` — حركات الفرع/الكشف، ترتيب تاريخ التصفية تنازلي، الحالة مشتقة (شوف تحت)، `counts` لكل حالة بنفس الفلاتر من غير فلتر الحالة، `totalsalariesowed` / `totalnetvalue` بعد فلتر الحالة، الترقيم في الذاكرة |
| المسلسل | `serial` | (نفس الرد) | `EOServiceTrxH.Serial` |
| الموظف (كود + اسم) | `empcode` + `emparaname`/`emplatname` حسب اللغة | | `Employee.EmpCode` / `EmpFullAraName` / `EmpFullLatName` |
| نوع التصفية (+ وسم «مع البقاء») | `eoservicetypearaname` + `eowithstay` | | `EOServiceType.EOTypeAraName` / `EOWithStay` |
| تاريخ التصفية | `startdate` | | `EOServiceTrxH.StartDate` |
| الرواتب المستحقة | `salariesowed` (— لو فاضي) | | اللقطة اللي بيحفظها `EOSCalc` |
| الصافي | `netvalue` | | `EOServiceTrxH.NetValue` |
| الحالة (chip ملوّن) | `status` (+ tooltip «آخر حساب» من `calculatedat`) | | `paid` لو `Posted` ← `reviewed` لو `Reviewed` ← `calculated` لو فيه إيقاف موسوم بالحركة ← `draft` |
| فلتر الموظف | `app-input-with-sql-search` ← `EmployeeService` | `GET {HR}Employee/GetalldatabyfilterWithCount?skipcount=0&maxresultcount=1&empcode=` (أو نافذة البحث) | `EmployeeAppService.GetListAsyncWithCount` |
| فلتر نوع التصفية | `app-auto-complete` ← `EOServiceTypeService.getAll()` | `GET {HR}EOServiceType/GetAllData` | `EOServiceTypeAppService.GetAllData` |
| من / إلى تاريخ | `app-date-picker` (`yyyy-MM-dd`) | بيتبعت `fromdate` / `todate` | على `StartDate` (إلى = شامل اليوم) |
| الحالة (أزرار pills في الفلتر + بطاقات الحالة فوق) | `setStatus` + `applyCriteria` | `status=draft|calculated|reviewed|paid` (فاضي = الكل) | فلترة بعد اشتقاق الحالة |
| الفرع | من محدد الفرع/الكشف في الشريط العلوي (مفيش dropdown في الشاشة) — تغييره بيعيد التحميل | الهيدر | `GetBranchIdOrFromRequest` (يقبل `branchid` اختياري) |
| بحث / تفريغ | `applyCriteria` / `clearData` | `GetReviewList` | |

### علم «محسوبة» (بدون migration)
- مفيش عمود جديد. الحركة **محسوبة** لو (مش مع البقاء) وفيه سطر `PayEmpStatusTrx` غير محذوف: `mysource='EOServiceTrxH' AND mykey=id` **أو** علامة الـ Notes القديمة `EOS:{id بصيغة N}`.
- `EOSCalc` بس اللي بينشئ الإيقاف ده قبل المراجعة؛ `EOSCancelCalc` / `EOSCancelReview` / `Delete` بيمسحوه، فالعلم بيرجع `draft` تلقائي.
- `calculatedat` = `creationtime` لآخر إيقاف (تقريبي لوقت آخر «حساب»).
- محتاج الـ migration `20261007100000_Add_EOS_MySource_MyKey` تكون متطبقة (عمودين `mysource`/`mykey`)، وإلا `GetReviewList`/`GetEOSEffects`/`EOSCancelCalc` هيفشلوا بخطأ عمود مش موجود.

## أزرار السطر (أيقونات)
| الأيقونة (اللون) | تظهر لما | الدالة | خدمة الفرونت | Endpoint | Backend | بعد النجاح |
|---|---|---|---|---|---|---|
| `calculate` حساب الشهر / إعادة الحساب (أزرق) | مش مع البقاء + مش مراجعة + مش مصروفة | `onCalc` (تأكيد) | `eosCalc(id)` | `POST {HR}EOServiceTrxH/EOSCalc?id=` | `EOSCalc` (إيقاف + حساب الأشهر المفتوح..التصفية + لقطة `salariesowed`) | toast + وميض السطر + `loadList(true)` |
| `undo` إلغاء حساب الشهر (برتقالي) | محسوبة + مش مراجعة + مش مصروفة | `onCancelCalc` (تأكيد) | `eosCancelCalc(id)` | `POST {HR}EOServiceTrxH/EOSCancelCalc?id=` | **جديد** `EOSCancelCalc` — يرفض لو مراجعة/مصروفة أو مع البقاء أو مفيش شهر مفتوح أو مش محسوبة؛ يمسح إيقاف الحركة (`RemoveEosStopsAsync` ← `PayEmpStatusTrxService.Delete`)، يعيد حساب الأشهر المفتوح..التصفية (يتخطى Reviewed/FinalClosed)، و`salariesowed = null` | زي فوق |
| `task_alt` تأكيد المراجعة (أخضر) | (محسوبة **أو** مع البقاء) + مش مراجعة + مش مصروفة | `onReview` (تأكيد) | `eosReview(id)` | `POST {HR}EOServiceTrxH/EOSReview?id=` | `EOSReview` (+ إجازة «رصيد» للإجازة بدون مرتب لو فيه أيام) | زي فوق |
| `remove_done` إلغاء المراجعة (أحمر) | مراجعة + مش مصروفة | `onCancelReview` (تأكيد) | `eosCancelReview(id)` | `POST {HR}EOServiceTrxH/EOSCancelReview?id=` | `EOSCancelReview` (بيمسح إجازات الحركة ويرجّع الرصيد) | زي فوق (الحالة بترجع `draft` لأن الإيقاف اتمسح) |
| `payments` صرف (فيروزي) | مراجعة + مش مصروفة | `onPay` (تأكيد) | `eosPayment(id)` | `POST {HR}EOServiceTrxH/EosPayment?id=` | `EosPayment` | زي فوق |
| `insights` تأثير التصفية (بنفسجي) | محسوبة أو مراجعة أو مصروفة | `onEffects` ← `EoServiceEffectsDialogComponent.load` | `getEOSEffects(id)` | `GET {HR}EOServiceTrxH/GetEOSEffects?id=` | **جديد** `GetEOSEffects` (قراءة بس) — شوف تحت | نافذة |
| `visibility` فتح شاشة الحساب (رمادي) | دايماً | `onOpen` ← `resolveCalcMenuId` | `TabSystemMenuService.getFlatMenuPermissions()` (من الكاش)، ولو مش موجود `findPageAndSystem('EOServiceTrxH')` | `GET {HOST}TABSystemMenu/Getalldatabyfilter?pagemenukey=EOServiceTrxH` (fallback بس) | — | `window.open(router.serializeUrl(createUrlTree(['/hr-system/EOService-calc', menuId], {queryParams: {mode:'edit', id}})), '_blank')` — بتفتح في **تبويب جديد** ← منطق `mode=edit` الموجود في `BaseToolBarComponent` |

- كل الإجراءات: نافذة تأكيد `ConfirmationDialogService.confirm` (الرسالة فيها المسلسل واسم الموظف)، وأزرار السطر كلها disabled وفي spinner على الزرار طول ما الطلب شغال (`busyRowId`)، ومفيش إجراء تاني يتنفذ في نفس الوقت.
- رد `statuscode >= 400` في body (BadApiResponse) ← `showServerErrorMessage(message)`. أخطاء HTTP للـ POST بيعرضها `error.interceptor` (مفيش toast مكرر)؛ أخطاء الـ GET بتتعرض من الشاشة.
- أزرار دورة الحياة بتختفي لو صلاحية الصفحة (`PermissionsListService`) مفيهاش `edit` ولا `insert`. العين وتأثير التصفية بيفضلوا ظاهرين.
- مع البقاء: مفيش «حساب الشهر» ولا «إلغاء الحساب» — المراجعة مباشرة.

## نافذة «تأثير التصفية» — `GetEOSEffects`
| القسم | الاستعلام في الباك |
|---|---|
| ملخص (النوع، التاريخ، الحالة، الرواتب المستحقة، الصافي، عدد الآثار) | `EOServiceTrxH` + `Employee` + `EOServiceType`، والحالة بنفس منطق القائمة |
| إيقاف الموظف | `PayEmpStatusTrx` للموظف: `mysource='EOServiceTrxH' AND mykey=id` أو `notes LIKE 'EOS:{N}%'` (وسم «علامة قديمة») |
| الإجازات (مدفوعة مع البقاء / «رصيد» للإجازة بدون مرتب) | `VacEmpTrx`: `mysource='EOServiceTrxH' AND mykey=id` + اسم `VacationDef`. `paymenttype` بيرجع نص (`Vacation` أو `paid`) والنافذة بتعرضه «رصيد» أو «مدفوع» (`paymentTypeLabel`) |
| المتغيرات | `PayVariableElements`: `mysource = id AND (mysourcetable='EOServiceTrxH' OR mysourcetable IS NULL)` + كود/اسم `PayElements` |
| الصرف | `SalaryPayment`: `mysource='EOServiceTrxH' AND mykey=id` + مبلغ سطر الموظف (`SalaryPaymentLine.AmountAfterRounding`) |
| أشهر المرتب | `FinalData` للموظف (فرع/كشف الحركة) من الشهر المفتوح لحد شهر التصفية (أو شهر التصفية بس لو المفتوح بعده) — Gross = Net + SumDeduction + Tax + EmpVal، الأيام الفعلية، حالة المرتب |

كل الاستعلامات بتحترم الحذف الناعم (المحذوف مش بيظهر).

## المنيو والصلاحيات
- تسجيل الشاشة في المنيو وصلاحياتها والـ Field Dictionary بيتعملوا من زميل تاني في الفريق.
- الـ route `EOService-review/:id` محمي بـ `PermissionGuard` (`:id` = id الصفحة في المنيو).
