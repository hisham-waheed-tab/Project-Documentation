# تعيين مواقع الحضور GPS (TABGPSLocationAssign)

## الهدف
ربط مواقع الحضور (`TABGPSLocation`) بالفروع أو الإدارات أو الموظفين **كقاعدة**، بحيث يأخذ الموظف الجديد أو المنقول مواقع فرعه وإدارته تلقائياً من غير ما حد يرجع للشاشة.

## الجدول `TABGPSLocationAssign`
| العمود | النوع | ملاحظات |
|---|---|---|
| id, tenantid + حقول BaseEntity | | audit و soft delete و `notactive` |
| tabgpslocationid | uuid NOT NULL | FK -> `TABGPSLocation` (Cascade) |
| scopetype | smallint | `GPSLocationScopeType`: 1 فرع، 2 إدارة، 3 موظف |
| branchid | uuid NULL | FK -> `Branches` (Cascade) |
| departmentid | uuid NULL | FK -> `Departments` (Cascade) |
| empid | uuid NULL | FK -> `Employee` (Cascade) |
| fromdate / todate | date NULL | فترة السريان (NULL = مفتوحة) |

- عمود واحد بس من `branchid / departmentid / empid` بيتملى، وهو اللي بيطابق `scopetype`. الـ service هي اللي بتضمن ده (`SetScope`).
- مفيش `MySource/MyKey`.
- الـ Cascade بيشتغل بس مع الحذف الفعلي (hard delete). التطبيق بيستخدم soft delete، فالموقع المحذوف بيتشال من النتائج عن طريق الـ query (الموقع لازم يكون موجود ونشط).
- الـ indexes: `tabgpslocationid`، و`(tenantid, empid)`، و`(tenantid, departmentid)`، و`(tenantid, branchid)`، و index على كل FK.
- مفيش unique index، لأن الفترات ممكن تتداخل أو تتتابع، ومع soft delete هيبوظ. منع التكرار بيحصل في الـ service.
- Migration: `20261011160000_Add_TABGPSLocationAssign` (مكتوبة يدوياً و idempotent، **لم تُطبق**).

## القاعدة: مواقع الموظف
المواقع الفعالة للموظف في تاريخ معين هي اللي:
- فيها تعيين `notactive != true` والتاريخ داخل `[fromdate, todate]`،
- ومطابق لواحد من دول: `empid = الموظف` أو `departmentid = إدارة الموظف` أو `branchid = فرع الموظف`،
- والموقع نفسه نشط ومش محذوف.

**لو مفيش أي تعيين فعال، بيرجع كل المواقع النشطة** (نفس السلوك القديم).
المنطق موجود في مكان واحد: `TABGPSLocationAssignAppService.ResolveLocationsAsync`.

## الـ Endpoints (`api/v1/TABGPSLocationAssign/...`)
| Endpoint | الوصف |
|---|---|
| `GET GetalldatabyfilterWithCount` | قائمة بالصفحات، وفلاتر: `TABGPSLocationId`، `ScopeType`، `BranchId`، `DepartmentId`، `EmpId`، `NotActive`، `ActiveOnDate`. كل صف بيرجع اسم الموقع واسم النطاق (عربي وإنجليزي) |
| `GET Getbyid?id=` | صف واحد |
| `POST Create` | `{ tabgpslocationids[], scopetype, scopeids[], fromdate, todate, notactive }`، بيعمل صف لكل (موقع × نطاق). بيتخطى المكرر الفعال المتداخل، وبيرجع `{ requested, created, skippedduplicates, skipped[] }` |
| `POST Update?id=` | `{ tabgpslocationid, scopetype, scopeid, fromdate, todate, notactive }`، وبيرفض لو فيه تداخل مكرر |
| `POST Delete?id=` | حذف صف |
| `POST DeleteMany` | body: `[ids]` |
| `GET GetEmployeeLocations?empId=&date=` | مواقع موظف بالقاعدة (والتاريخ الافتراضي النهارده) |
| `GET GetScopeLookups?scopeType=&filter=` | lookup للفروع أو الإدارات أو الموظفين (أقصى 50 موظف لكل بحث) |

التحقق في Create و Update: `scopetype` صحيح، و`fromdate <= todate`، والمواقع والنطاقات موجودة في نفس الـ tenant، وأقصى 5000 صف في الطلب الواحد.

## التغيير في `TABGPSLocation/GetMyActiveLocations`
- **قبل:** كان بيرجع كل المواقع النشطة في الـ tenant.
- **بعد:** بيجيب موظف اليوزر الحالي (`Employee.UserId = CurrentUser.Id`)، وبيرجع `ResolveLocationsAsync` لتاريخ النهارده.
- لو اليوزر ملوش موظف، أو الموظف ملوش أي تعيين فعال، بيرجع كل المواقع النشطة زي الأول.
- نوع الرجوع زي ما هو `List<TABGPSLocationDto>`، فالموبايل مش هيتأثر.
- قبل التعديل اتراجع إن مفيش أي شاشة ويب بتنده عليه. الدالة `getMyActiveLocations` معرّفة في `tab-gps-location.service.ts` بس، ومحدش بيستخدمها.

## الفرونت (داخل شاشة مواقع GPS)
- **مفيش شاشة منفصلة.** التعيينات بتتدار من جوه فورم الموقع (`time-attendence/locations/{menuId}`)، تحت الفورم الأساسي.
- **الكومبوننت:** `time-attendence-locations-form/gps-location-assignments/` (standalone، grid مخصص).
  - بيظهر بس لما يكون للموقع Id (تعديل، أو بعد أول حفظ).
  - التحميل: في التعديل من `baseService.editForm` (بيتبعت بعد `getById`)، وبعد الحفظ من `afterSaveWork(id)`. و`baseService.clearForm` بيخفيه.
  - الأعمدة: النوع (فرع / إدارة / موظف)، الاسم، من تاريخ، إلى تاريخ. الترتيب بالنوع ثم الاسم.
  - فوقه بحث بالاسم وفلتر نوع (الكل / فروع / إدارات / موظفين)، والفلترة في الفرونت.
  - **إضافة بس، مفيش تعديل (حتى التواريخ):** زرار «إضافة» بيفتح خطوتين (MatDialog):
    1. `gps-location-assign-type-dialog/`: اختيار النوع، «إدارة» أو «موظفين محددين». نوع «فرع» **مخفي حاليًا** في الواجهة بس، والـ enum والباك زي ما هما، وصفوف الفروع القديمة لسه بتظهر في الـ grid.
    2. `gps-location-assign-dialog/`: جدول `mat-table` فيه بحث بالاسم أو الكود، و«تحديد الكل»، واختيار متعدد. الإدارات بتيجي من `DepartmentsService.getAll()`. الموظفين بييجوا من `Employee/GetalldatabyfilterWithCount`، وفوقهم فلتر «إدارة» بـ `app-auto-complete` بيبعت `departmentid`.
    - مفيش أي اختيار أو فلترة للفرع في الفرونت. الفرع الحالي بيتبعت في الهيدر `X-Branch-Id` والباك بيفلتر بيه مركزيًا.
    - التواريخ (من / إلى) اختيارية. اللي متخصص قبل كده بيظهر معلَّم ومقفول، ومش بيتبعت تاني. زرار الحفظ اسمه «تم»، وكل المختارين بيتحفظوا بـ `createAssignments` سطر لكل واحد من نفس النوع.
    - الموظفين المختارين مش بيورثوا التعيينات الجديدة، يعني اللي يتعيّن بعد كده في الإدارة مش بياخد الموقع (فيه تنبيه في الشاشة). عشان التعيينات الجديدة تتشمل، اختار نوع «إدارة».
  - **المصطلح:** «قسم» اتغيّر لـ «إدارة» في الترجمة العربي للخاصية دي.
  - **الحذف:** لكل صف بتأكيد (`Delete`)، أو المحدد كله (`DeleteMany`).
- **الـ Service:** `services/hr-system/attendance-absence/time-attendence/tab-gps-location-assign.service.ts`.
  - بيستخدم الـ service الموجود في development زي ما هو: `getList` و`createAssignments` و`deleteMany` و`getScopeLookups`، والموديلات من `tab-gps-location-assign.models.ts`. الحذف الفردي بيتم بـ `deleteMany([id])`.
  - القايمة من `GetalldatabyfilterWithCount?TABGPSLocationId=` (بترجع اسم النطاق)، ومفيش endpoint جديد في الباك.
- **الترجمات:** مفتاح `gpsAssign` في ar.json و en.json.
- **الشاشة المنفصلة القديمة `locations-assign` اتشالت:** الـ route `time-attendence/locations-assign/:id` اتشال، وملفاتها (الصفحة والـ service والموديل `time-attendence-locations-assign.ts`) ومفتاح `gpsLocationAssign` اتمسحوا. مش محتاجة عنصر في القايمة ولا Field Dictionary.

## الصلاحيات
الموديول مش بيعرّف صلاحيات لكل شاشة في TA (`TABGPSLocation` نفسها مفيهاش). الحماية بتيجي من `[Authorize]` في `BaseAppService`، ومن `PermissionGuard` على المسار في الفرونت.