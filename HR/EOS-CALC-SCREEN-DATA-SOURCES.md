# مصادر بيانات شاشة حساب التصفية (EOService-calc)

شاشة: `hr-system/EOService-calc/:id` — مثال: `https://dev-app.tab-erp.com/hr-system/EOService-calc/c4525ea8-20db-409d-b6ca-886ee79588c7`

تاريخ المراجعة من الكود: 2026-11-09. المرجع الأساسي هو الكود الحالي (Front + `EOServiceTrxHService.cs`). وُجد ملف أقدم `EOS-CALC-HTTP-MAP.md` بتاريخ 2026-10-07 (خريطة HTTP على مستوى المكوّن) — لم يُعدَّل. هذا الملف يركّز على كل عنصر ظاهر ومصدر حقله.

## رموز وملاحظات عامة

- `{HR}` = `environment.baseUrlHR` — على dev: `https://dev-hr-api.tab-erp.com/api/v1/`
- `{HOST}` = `environment.baseUrl` — على dev: `https://dev-host.tab-erp.com/api/v1/`
- Controllers في HR: `api/v1/[controller]/[action]`. أسماء حقول JSON بالـ camelCase.
- بعض الـ GET ترجع الـ DTO مباشرة (بدون `result`)، والبعض داخل `ApiResponse.result`. مذكور في عمود الحقل.
- **تسمية الحقل العربية** في الفورم تأتي من Field Dictionary: `FieldDictionaryListService.getList()` حسب `pageid` = `:id` في الراوت (`langvalue` للغة الحالية). لو مش موجودة يظهر `translate(fieldName)` من `ar.json`. النص في الجدول هو أقرب تسمية من `ar.json` أو من كود الشاشة؛ إن لم تُؤكَّد من القاموس كُتبت «تسمية FD غير مؤكدة».
- أعمدة الجريد الرئيسي وجريد البدلات/الاستقطاعات الأخرى: `GridList` + Field Dictionary (`menukey` / `fielddisplayon`).
- تحميل حركة محفوظة: شريط الأدوات يستدعي `GET {HR}EOServiceTrxH/GetById?id=` ثم `patchValue` لكل حقول الـ header، وبعدها تُستدعى lookups/إعادة الحسابات أدناه.

## 1) شريط الأدوات والـ Criteria (بحث الجريد)

الصفحة: `app-base-tool-bar` + `app-eo-service-calc-criteria`. أزرار الحفظ القياسية من الـ toolbar. `canDelete=false`. `hideToolbarReview=true` (مراجعة/صرف التصفية ليست من شريط هذه الشاشة).

| العنصر على الشاشة | field في الفورم | Endpoint | حقل الـ response | ملاحظة قصيرة |
|---|---|---|---|---|
| بحث (criteria) | applyCriteria | GET `{HR}EOServiceTrxH/GridList?menukey=&fielddisplayon=1&skipcount=&maxresultcount=&empid=&startdate=&enddate=&eoservicetypeid=&periodyears=&periodmonths=&perioddays=` | result (صفوف + headers من Field Dictionary) | Backend: `EOServiceTrxHService.GridList`. الفلاتر من فورم الـ criteria فقط. |
| مسح (criteria) | clearData | GET `{HR}EOServiceTrxH/GridList` (بدون فلاتر criteria) | نفسه | يعيد تحميل الجريد. |
| الموظف (criteria) | empid / empName | نافذة البحث: `POST {HOST}SqlExecution/SearchWithFilterAsync`. بعد الاختيار أو الكود: `GET {HR}Employee/GetalldatabyfilterWithCount?skipcount=0&maxresultcount=1&empcode=` | `result.items[0]._entitydto.id` (والاسم `empfullaraname`) | نفس `input-with-sql-search` (SQL من قاموس الحقل `empid`). |
| تاريخ البدء / التصفية (criteria) | startdate | فلتر فقط — لا endpoint منفصل | يُرسل كـ `startdate` إلى GridList | التسمية من FD لنفس `startdate`. |
| تاريخ الانتهاء (criteria) | enddate | فلتر فقط | `enddate` في GridList |  |
| نوع التصفية (criteria) | eoservicetypeid | GET `{HR}EOServiceType/GetAllData` | `id` / `eotypearaname` | `app-auto-complete` + `EOServiceTypeService.getAll()`. |
| سنوات/شهور/أيام المدة (criteria) | periodyears / periodmonths / perioddays | فلتر GridList فقط على هذه الشاشة | تُحفظ على الحركة من `CalcEOService` (`totalyears/totalmonths/totaldays`) لكنها **غير ظاهرة** في فورم الحساب | تظهر هنا كمعايير بحث فقط. |
| حفظ / حفظ وتعديل (toolbar) | كل حقول الفورم | POST `{HR}EOServiceTrxH/Create` أو `POST {HR}EOServiceTrxH/Update?id=` | `result.id` ثم إعادة `GetById` | Backend: `Create` / `UpdateAsync`. الـ payload يُطبَّع في `normalizeTrxPayload` (serial نص، enddate ≥ startdate). |

## 2) رأس الفورم: بيانات الموظف ونوع التصفية والصافي

| العنصر على الشاشة | field في الفورم | Endpoint | حقل الـ response | ملاحظة قصيرة |
|---|---|---|---|---|
| المسلسل | serial | عند التحميل: GET `{HR}EOServiceTrxH/GetById?id=` | `serial` | يُدخل يدوياً ويُحفظ مع Create/Update. يُحذف من الـ payload لو 0/فارغ. |
| الموظف | empid / empName | نفس بحث الـ SQL + `GET {HR}Employee/GetalldatabyfilterWithCount?skipcount=0&maxresultcount=1` (`empcode` أو عند التحميل `id=`) | `_entitydto.id` يُكتب في `empid`. العرض: `empcode` | `onEmpSelected`. عند فتح حركة: `getEmpData`. |
| شارة جاهزية الراتب (بجانب الموظف) | — (ليست control). المدخل: `empid` + `startdate` | GET `{HR}PayrollReadiness/CheckReadiness?year=&month=&empid=&maxresultcount=1&skipcount=0` | صف الموظف: `issues[]`, `issuecode`, `payrollyear`, `payrollmonth` | السنة/الشهر من `startdate` (مش الشهر المفتوح، إلا لو التاريخ فاضي فيُستخدم `GET {HR}PayCurrentMonth/GetCurrentMonth` داخل `resolveParams`). تُستبعد الأكواد 5 و6 و15 و23 قبل الحالة. النصوص من `ar.json` (`eosReadiness.ready` = جاهز لحساب الراتب، `critical` = بيانات ناقصة، `review` = يحتاج مراجعة). Backend: `PayrollReadinessAppService.CheckReadiness`. |
| تاريخ التصفية | startdate | إدخال مستخدم؛ عند التحميل `GetById.startdate` | `startdate` | تغييره يعيد تحميل العهد والرسوم، ويضبط `enddate` لو كانت أقدم. هو تاريخ نهاية الخدمة في الحسابات. |
| نوع التصفية | eoservicetypeid | قائمة: GET `{HR}EOServiceType/GetAllData`. عند التحميل: GET `{HR}EOServiceType/GetById?id=` | `id`, `eotypearaname`, `isvacation`, `eowithstay`, `flightticketstype`, `vacationdefid` | تسمية FD غير مؤكدة (غالباً «نوع التصفية»). `isVacation`/`isWithStay` يتحكمان في إظهار الإجازة/المكافأة/الرواتب المستحقة. تحميل النوع صار بـ GetById (القائمة كانت تتجاهل فلتر id). |
| الإدارة | department (label: departmentid) | من موظف: نفس `GetalldatabyfilterWithCount` | `empdepartment.deparaname` (عربي) أو `deplatname` | للعرض فقط (disabled). محسوب client-side من كائن الموظف. |
| الموقع | location (label: locationid) | نفسه | `emplocation.locaraname` / `loclatname` | للعرض فقط. |
| الوظيفة | job (label: jobid) | نفسه | `empjob.jobaraname` / `joblatname` | للعرض فقط. |
| الجنسية | nationality (label: nationalityid) | نفسه | `empnationality.nataraname` / `natlatname` | تسمية FD غير مؤكدة. للعرض فقط. |
| تاريخ آخر مباشرة للعمل | lastReturnDate (label: lastreturndate) | نفسه | `lastreturndate` (يُعرض الجزء YYYY-MM-DD أو `-`) | للعرض فقط. |
| تاريخ بداية التعيين | rectutingStartDate (label: recruitingstartdate) | نفسه | `recruitingstartdate` | للعرض فقط. الـ backend يستخدمه في مدة الخدمة (`CalculateAsync`). |
| إجمالي صافي التصفيات | netvalue | **لا endpoint** — حساب في الفرونت | — | في `EOServiceCalcComponent`: `endofservicebenefitsvalue - exchangedrewardbefore - managementfeesvalue + totalotherallowance - totalotherdeduction`. **لا يشمل** `flightvalue` ولا `vacationallowvalue` ولا `salariesowed` ولا `loansvalue` ولا العهد. يُحفظ مع الحركة لكنه يُعاد حسابه من الحقول الخمسة أعلاه (valueChanges). |
| حساب التصفية (زر) | — | انظر القسم 7 | — | نص الزر من `ar.json`: `eoCalculate` = حساب التصفية. |
| الملاحظات | notes | عند التحميل `GetById.notes`؛ يُحفظ Create/Update | `notes` | إدخال مستخدم. |

## 3) قسم الإجازات

تبويب `vacations` = «الإجازات». الحقول الثلاثة الأولى تظهر دائماً. تاريخ الانتهاء وعدد الأيام يظهران فقط لو نوع التصفية `isvacation=true`.

| العنصر على الشاشة | field في الفورم | Endpoint | حقل الـ response | ملاحظة قصيرة |
|---|---|---|---|---|
| إجمالي الاجازات | vacationtotalaccrued | يُحسب في الفرونت بعد `GET {HR}EOServiceTrxH/CalcVacValue?employeeid=&eostypeid=&eosdate=` | `consumedbefore + currentbalance` | Backend `CalcVacValue`: الرصيد من `VacEmpBalance` (آخر فترة تغطي تاريخ التصفية و`VacationDefId`). `currentbalance` = المتاح (Credit−Debit)، `consumedbefore` = Debit. |
| الاجازات المستخدمة | vacationdaysused | نفس `CalcVacValue` | `consumedbefore` |  |
| الرصيد المتاح / المستحق (تسمية FD غير مؤكدة) | vacationaccrued | نفس `CalcVacValue` | `currentbalance` | disabled. لو لا `vacationdefid` على النوع ترجع أصفار ويظهر تحذير. |
| تاريخ الانتهاء (نوع إجازة فقط) | enddate | إدخال مستخدم أو يُحسب من عدد الأيام | يُحفظ في `GetById.enddate` / Create/Update | client-side: `enddate = startdate + (vacationdays − 1)`. inclusive مثل `VacEmpTrx`. |
| عدد أيام الإجازة (نوع إجازة فقط، تسمية FD غير مؤكدة) | vacationdays | إدخال مستخدم أو يُحسب من التاريخ؛ عند «حساب التصفية» يُضبط من الرصيد | بعد الحساب: `min(المدخل، currentbalance)` لو الرصيد>0 وإلا 0 | عكس التاريخ: `vacationdays = enddate − startdate + 1`. بدل الإجازة يُحسب في الفرونت من هذا العدد. |
| تحذير غياب تعريف إجازة | vacationTypeWarnings | لا HTTP | مفتاح `eosVacationWarnings.noVacationDef` في ar.json | يظهر لو `isvacation` و`vacationdefid` فاضي. |

## 4) قسم المستحقات

تبويب `entitlements` = «المستحقات». `salariesowed` يختفي لو `eowithstay`. مكافأة نهاية الخدمة تختفي لو نوع إجازة فقط (`isVacation`).

| العنصر على الشاشة | field في الفورم | Endpoint | حقل الـ response | ملاحظة قصيرة |
|---|---|---|---|---|
| نوع تذاكر الطيران | flightticketstype | لا HTTP للقائمة — ثابت في `EOServiceTypeService.flightTicketsType` | يُعرَض `araname` حسب `EOServiceType.flightticketstype` (0 بدون تذاكر، 1 ذهاب، 2 ذهاب وعودة) | بعد اختيار النوع / GetById للنوع. القيمة المالية من endpoint التذاكر أدناه. |
| قيمة التذكرة (تسمية FD غير مؤكدة) | flightvalue | GET `{HR}EOServiceTrxH/GetTicket_Loan_Amount?empid=&eostypeid=&eosdate=` | `ticketvalue` (من جذر الـ body، ليس داخل result) | Backend `GetTicketAndAdvanceValuesAsync`: من `EOServiceBalances` — ذهاب=`ticketgovalue`، ذهاب وعودة=`ticketfullvalue`، غير ذلك 0. يحتاج سجل رصيد خدمة للموظف. |
| بدل الإجازة (تسمية FD غير مؤكدة) | vacationallowvalue | بعد `CalcVacValue` — **حساب فرونت** | يستخدم `monthsalary` من `CalcVacValue` | `(monthsalary / 30) * vacationdays` إذا الرصيد المتاح>0 والأيام>0 والراتب>0، وإلا 0. راتب الإجازة من عناصر `VacationSalaryElements` على النوع، أو كل عناصر العقد لو القائمة فاضية. `GetMonthlyElementTotalAsync` لشهر/سنة تاريخ التصفية. |
| الرسوم الإدارية (حقل المجموع) | managementfeesvalue | مجموع من قسم الرسوم (انظر 6) | مجموع `remainamount` للصفوف المختارة المحفوظة | disabled. يتحدث مع اختيار/حذف صف الرسوم. |
| السلف / القروض (تسمية FD غير مؤكدة) | loansvalue | نفس `GetTicket_Loan_Amount` | `loanvalue` | Backend `GetEmpRemainTotalLoanAsync`: مجموع `PayLoansF.InstallValue` غير المحسوبة وغير الملغاة/الموقوفة. **`untilDate` يُمرَّر null من هذا النداء — لا فلترة بتاريخ التصفية.** |
| إجمالي البدلات الأخرى | totalotherallowance | بعد `GET {HR}EOServicesOtherElementsF/GetalldatabyfilterWithCount?skipcount=0&maxresultcount=1000&eoserviceshid=` — مجموع فرونت | صفوف `_entitydto.amount` حيث `element.payelementtypecode === 2` | client-side في `calcTotalOtherAllowancesandDeductionsF`. |
| إجمالي الاستقطاعات الأخرى | totalotherdeduction | نفس الـ endpoint | `amount` حيث `payelementtypecode === 3` | client-side. |
| إجمالي الرواتب المستحقة | salariesowed | قيمة الحقل تُملأ فقط من `POST {HR}EOServiceTrxH/EOSCalc?id=` ← `result.salariesowed` | `result.salariesowed` | لا يظهر في نوع «مع البقاء». يُحفظ على الحركة. التفاصيل زر منفصل (لا يعيد ملء الحقل). Backend `EOSCalc`: إيقاف من تاريخ البداية، حساب أشهر من المفتوح حتى شهر التصفية (يتخطى Reviewed/FinalClosed)، ثم Gross من FinalData = `NetSalary+SumDeduction+Tax+EmpVal`. |
| تفاصيل (بجانب الرواتب المستحقة) | — زر `details` | GET `{HR}EOServiceTrxH/GetSalariesOwed?empid=&eosdate=[&trxid=]` | جذر: `months[]` (`year,month,grosssalary,netsalary,actualdays,payrollstatus,skipped`) | قراءة فقط من FinalData (`GetSalariesOwed`) — لا يعيد حساب الأشهر. الفترة: الشهر المفتوح إلى شهر التصفية (أو شهر التصفية فقط لو المفتوح بعده). Popup أعمدة ثابتة: الشهر، الإجمالي، الصافي، الأيام الفعلية، حالة المرتب (مترجمة في الفرونت). |
| صرف الراتب مع الفلتر (تسمية FD غير مؤكدة) | salarywithfilter | يُحفظ مع Create/Update / `GetById.salarywithfilter` | `salarywithfilter` | checkbox — إدخال مستخدم. لم يُرَ في كود الحساب الحالي أنه يغيّر معادلة ظاهرة على الشاشة. |
| المكافأة المصروفة سابقاً (تسمية FD غير مؤكدة) | exchangedrewardbefore | نفس `GetTicket_Loan_Amount` | `eoservicespentbefore` | من `EOServiceBalances.eoservicespentbefore`. يدخل في معادلة `netvalue`. |
| مكافأة نهاية الخدمة (تسمية FD غير مؤكدة؛ label=`endofservbenefitsvalue` / control=`endofservicebenefitsvalue`) | endofservicebenefitsvalue | GET `{HR}EOServiceTrxH/CalcEOService?employeeid=&eostypeid=&eosdate=` | `totalamount` (جذر الـ body) | لا يُستدعى لو `eowithstay`. Backend `CalculateAsync`: مدة الخدمة من `RecruitingStartDate` حتى تاريخ التصفية (سنة=365، شهر=30). الراتب من عناصر `PayElements` على النوع (`GetMonthlyElementTotalAsync`). الشرائح من `EOServiceTypePolicy` ثم معامل الشريحة التي يقع فيها إجمالي الخدمة يُطبَّق على كل المبلغ. عند EOSCalc تُحفظ سطور المكافأة في `EOServiceTrxF` في الـ backend. |
| تفاصيل (بجانب المكافأة) | — زر؛ بيانات مسبقة في `eosDetails` | لا HTTP إضافي (يستخدم `details` من `CalcEOService`) | `details[]`: `fromyear,toyear,daysperyear,factor,amount` | أعمدة البوب أب ثابتة في الفرونت. عمود `yearscount` معروض لكن **backend لا يملأ `YearsCount` حالياً** (غالباً فاضي). |

## 5) بدلات واستقطاعات أخرى (جريد)

تبويب `otherAllowancesandDeductions`. جريد `shared-details-grid` / `footerServiceKey=eoServicesOtherElementsF`. الأعمدة من Field Dictionary عبر GridList (ليست hardcoded).

| العنصر على الشاشة | field في الفورم | Endpoint | حقل الـ response | ملاحظة قصيرة |
|---|---|---|---|---|
| أعمدة الجريد (تختلف حسب القاموس) | عادة منها: `elementid`, `amount`, `serial` (حسب DTO والعرض) | GET `{HR}EOServicesOtherElementsF/GridList?menukey=&pageparameter=&fielddisplayon=&skipcount=&maxresultcount=&eoserviceshid=` | صفوف `_entitydto` + headers من FD | عند فتح الحركة: `getTableDataByHeaderId({eoserviceshid})`. قائمة العنصر في عمود dropdown: `GET {HR}EOServicesOtherElements/GetAllData` (عرض `arabicname`). |
| إضافة/تعديل/حذف صف | elementid, amount, ... | POST `{HR}EOServicesOtherElementsF/Create` أو `/Update?id=` أو `/Delete?id=` | الصف المحفوظ | بعد الحفظ يُعاد حساب إجمالي البدلات/الاستقطاعات (القسم 4). |

## 6) الرسوم الإدارية (جريد) + العهد

أعمدة هذين الجريدين **ثابتة في الكود** (ليست Field Dictionary).

| العنصر على الشاشة | field في الفورم | Endpoint | حقل الـ response | ملاحظة قصيرة |
|---|---|---|---|---|
| رقم التسلسل / الاسم العربي / الاسم اللاتيني / المبلغ الكلي / من تاريخ / الى تاريخ / الأيام المتبقية / المبلغ المتبقى | حقول الصف: `lineno, araname, latname, remainprice, eoservicesfromdate, managmentfeestodate, dayscount, remainamount` | GET `{HR}ManagmentFees/GetEmpRemainingFees?employeeid=&exitdate=` | يُعمل map: `id→managmentfeesid`, `serial→lineno`, `araname`, `latname`, `totalamount→remainprice`, `fromdate→eoservicesfromdate`, `todate→managmentfeestodate`, `remainingdays→dayscount`, `remainingamount→remainamount` | Backend `GetRemainingFeesAsync`: رسوم الموظف التي تغطي تاريخ الخروج. المتبقي = (price/إجمالي الأيام)×(todate−exitDate+1). يُستدعى عند تغيير موظف+تاريخ، وعند فتح الحركة. |
| الصفوف المختارة سابقاً (تمييز الاختيار) | id / managmentfeesid | GET `{HR}EOServicesManagmentFeesF/GetalldatabyfilterWithCount?skipcount=0&maxresultcount=1000&eoserviceshid=` | `_entitydto` + مجموع `remainamount` → `managementfeesvalue` | `loadRowsFromGridList=false`, `saveOnSelect=true`: اختيار صف = Create، إلغاء = Delete. |
| حفظ/حذف صف رسوم مختار | remainamount | POST `{HR}EOServicesManagmentFeesF/Create` أو `/Delete?id=` | — | يحدّث `managementfeesvalue` محلياً (+/− `remainamount`). |
| اسم العهدة العربي / اللاتيني | custodyaraname / custodylatname | GET `{HR}CustodyTrxH/GetUndeliveredCustodiesForEmployee?empid=&untilDate=` | `result[].custodyaraname` / `custodylatname` | Backend: تسليم − استلام حتى التاريخ، غير المُتلَفة. أسماء من `CustodyDef`. |
| قيمة العهدة | عمود الجريد: `custodyvalue` | نفس الـ endpoint: `result[].custodyvalue` (من `CustodyDef.Value`) | الفرونت يكتب البيانات في حقل `value` وليس `custodyvalue` | **عدم تطابق مؤكد في الكود:** العمود اسمه `custodyvalue` بينما الـ map يستخدم `value` — القيمة الظاهرة غالباً فارغة. (كان مذكوراً في توثيق 7 أكتوبر وما زال موجوداً). الجريد للعرض فقط (`canCreate/Edit/Delete=false`). `totalcustody` موجود في الفورم لكن **غير ظاهر** على الشاشة ولا يُحدَّث من هذا الجريد. |

## 7) زر «حساب التصفية» (تسلسل الـ HTTP)

لا يُنفَّذ لو ناقص موظف/نوع/تاريخ، أو بعد مراجعة/صرف، أو أثناء `calcBusy`.

1. نوع **مع البقاء** (`eowithstay`): **يتخطى EOSCalc** ويستدعي فقط حسابات البند 2.
2. غير ذلك:
   - حفظ أولاً: `POST {HR}EOServiceTrxH/Update?id=` أو `/Create` (بعد Create تتحول الشاشة لتعديل عبر `createFormDisplay`).
   - ثم `POST {HR}EOServiceTrxH/EOSCalc?id=` → يملأ `salariesowed` من `result.salariesowed`. يرفض 400 لو مراجعة/صرف أو نوع مع البقاء أو لا يوجد شهر مفتوح صالح. يحفظ أيضاً سطور المكافأة في `EOServiceTrxF`.
3. `runOtherCalcs`: `GetTicket_Loan_Amount` دائماً؛ `CalcVacValue` لو `isVacation`؛ `CalcEOService` لو ليس `eowithstay` (حتى لو النوع فيه إجازة — المكافأة تُحسب ما عدا «مع البقاء»).

## 8) أزرار دورة الحياة (مراجعة / إلغاء مراجعة / صرف)

**غير ظاهرة على هذه الشاشة.** في `eo-service-calc-form.component.html` المكوّن `app-eo-service-lifecycle-actions` معلّق بتعليق أن الأزرار على شاشة «مراجعة وصرف التصفيات» فقط. الـ toolbar أيضاً يخفي المراجعة العامة (`hideToolbarReview`). تبقى هنا للمرجع فقط:

| العنصر على الشاشة | field في الفورم | Endpoint | حقل الـ response | ملاحظة قصيرة |
|---|---|---|---|---|
| تم المراجعة (ليست على هذه الشاشة) | reviewed | POST `{HR}EOServiceTrxH/EOSReview?id=` | `result.reviewed` / أو إعادة `GetById` | Backend `EOSReview`. |
| إلغاء المراجعة (ليست على هذه الشاشة) | reviewed | POST `{HR}EOServiceTrxH/EOSCancelReview?id=` | `result` |  |
| تم الصرف (ليست على هذه الشاشة) | posted | POST `{HR}EOServiceTrxH/EosPayment?id=` | `result.posted` |  |

## 9) الجريد الرئيسي (أسفل الشاشة)

| العنصر على الشاشة | field في الفورم | Endpoint | حقل الـ response | ملاحظة قصيرة |
|---|---|---|---|---|
| أعمدة الجريد الرئيسي | حسب Field Dictionary للـ menukey الخاص بالشاشة و`fielddisplayon=1` | GET `{HR}EOServiceTrxH/GridList?menukey=&fielddisplayon=1&skipcount=&maxresultcount=` + فلاتر criteria | `result.headers` (أسماء الأعمدة من القاموس) و`result` صفوف الحركة (`EOServiceTrxH`) | لو `fielddisplayon=0` على حقول القاموس قد تختفي أعمدة. اختيار صف يحمّل `GetById`. قائمة الأعمدة الدقيقة تعتمد على القاموس الحالي وليست hardcoded — **غير مؤكدة هنا بدون قراءة قاموس الصفحة.** من DTO الحركة تُحفظ تقريباً كل حقول الفورم (serial, empid, dates, type, vacation*, salariesowed, flightvalue, endofservicebenefitsvalue, loansvalue, netvalue, totals, fees, notes, flags...). |

## حقول في الفورم وغير ظاهرة على الشاشة

موجودة في `buildForm` وتُحفظ/تُحمَّل مع الحركة لكن بلا control ظاهر: `id`, `reviewed`, `posted`, `salary`, `periodyears/periodmonths/perioddays` (إلا في criteria), `vacationadddays`, `accno`, `totalcustody`. مدة الخدمة تُملأ من `CalcEOService` (`totalyears/months/days`) عند الحساب.

## فروق مهمة مقابل توثيق 7 أكتوبر 2026

- تحميل نوع التصفية أصبح `EOServiceType/GetById` وليس فلتر القائمة بـ id.
- `salariesowed` يُملأ من `EOSCalc` فقط (مع حفظ مسبق للحركة)؛ `GetSalariesOwed` للبوب أب فقط.
- زر الحساب يحفظ الحركة أولاً ثم `EOSCalc` ثم باقي الحسابات. نوع «مع البقاء» لا يستدعي `EOSCalc`.
- `netvalue` في الكود الحالي لا يضيف التذكرة ولا بدل الإجازة ولا الرواتب المستحقة ولا السلف ولا العهد.
- عدم تطابق `custodyvalue`/`value` ما زال موجوداً.
- أزرار المراجعة/الصرف لم تعد على هذه الشاشة.
- `YearsCount` في تفاصيل المكافأة لا يُضبط في `CalculateAsync`.
- قروض `GetTicket_Loan_Amount`: لا فلترة بتاريخ التصفية (`untilDate=null`).

## عناصر غير مؤكدة

- النص العربي الفعلي لكل label من Field Dictionary (يعتمد على قاموس `pageid` في الراوت وقد يختلف بعد تعديل القاموس).
- قائمة أعمدة الجريد الرئيسي وجريد البدلات/الاستقطاعات الأخرى (من القاموس / `fielddisplayon`).
- أثر `salarywithfilter` على أي حساب ظاهر — غير مستخدم في منطق الشاشة الحالي من قراءة الكود.
