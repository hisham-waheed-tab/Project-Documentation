# تغيير المدير الجماعي (Bulk Change Manager)

## الهدف
بدل ما ندخل لكل موظف في شاشة الموظفين ونغيّر مديره، الشاشة دي بتعرض الموظفين بفلاتر وتسمح باختيار مجموعة ونقلهم لمدير جديد مرة واحدة.

## الشاشة (Front)
- Route: `hr-system/employees-bulk-manager/:id` (المنيو والـ Field Dictionary بتتضاف من الأدمن).
- الملفات: `src/app/tabms/pages/hr-system/hr-management/employees-bulk-manager/`.
- الفلاتر: الإدارة `departmentid`، المجموعة الوظيفية `performjobgroupsid`، المدير الحالي `managerid`، اسم الموظف.
- الجريد: `app-base-grid` على `Employee/GridList` (اختيار متعدد للصفحة الحالية، محتاج عمود `select` في الـ Field Dictionary).
- المدير الجديد بيتختار بالعدسة `app-input-with-sql-search`، ثم خطوة تأكيد، ثم ملخص النتيجة.

## الباك (HR)
`POST api/v1/Employee/BulkChangeManager`
```json
{ "employeeIds": ["guid"], "managerId": "guid | null" }
```
الرد:
```json
{ "requestedCount": 0, "updated": 0,
  "skipped": [{ "empId": "guid", "reason": "NotFound | SelfAssignment | CircularManager" }],
  "wfSyncWarnings": ["guid"] }
```
- المدير لازم يكون موجود في نفس الفرع (Header الفرع).
- الموظف مايبقاش مدير نفسه ← يتخطى `SelfAssignment`.
- منع الدوائر: بنمشي على سلسلة مديري المدير الجديد، ولو فيها موظف من المختارين ← يتخطى `CircularManager`.
- التحديث في UoW واحد، ولكل موظف بيتنادى `SyncWfEmployeeManagerAsync` (نفس منطق Update) لمزامنة `WFEmployee.ManagerId`، ولو صف الـ WF مش موجود يرجع في `wfSyncWarnings`.
- `EmployeeFilter` اتضاف له `PerformJobGroupsId`.

## مفتوح
- صلاحية الـ endpoint حسب نمط `Adminstration.Entities.Employee.*`.
- «اختيار كل نتائج الفلتر» (مش الصفحة الحالية بس) غير مدعوم حاليًا.
- مفيش جدول تاريخ لتغيير المدير.

## مزامنة سير العمل (WF)

- الربط مع `WFEmployee` بيتم بالـ EmpCode والفرع (مش باليوزر).
- الـ bulk بيزامن `WFEmployee.ManagerId` لكل الموظفين المختارين حتى لو المدير ما اتغيرش، فلو صلحت بيانات WF وأعدت النقل بتتزامن.
- فشل المزامنة تنبيه مش خطأ (WF مش إلزامي لكل التينانتس)، والنتيجة بتعرض لكل موظف الكود والاسم والسبب:
  `EmployeeMissingCodeOrBranch` / `EmployeeNoWfEmployee` / `ManagerNotFound` / `ManagerMissingCodeOrBranch` / `ManagerNoWfEmployee`.
- `GET api/v1/Employee/GetWfLinkIssue?employeeId=`: بيرجع string فاضي لو المدير مربوط بـ WF، وإلا كود السبب. الشاشة بتناديه لما تختار المدير الجديد وتعرض تنبيه.
- الـ response فيه `wfSynced` = عدد اللي اتزامنوا مع WF، وكل رقم في النتيجة عليه tooltip بيشرحه.
