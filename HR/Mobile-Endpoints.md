# Endpoints الجوال: الدخول والحضور

> مستند مرجعي مختصر. كل ما فيه مأخوذ من الكود الفعلي بتاريخ 2026-10-23.
> كل الـ routes بالصيغة `api/v1/{Controller}/{Action}`، وكل الردود مغلّفة في `ApiResponse` (`data`، `statusCode`، `message`).
> كل الـ endpoints تحتاج `Bearer token` (OpenIddict).

## 0. ترتيب الاستدعاء عند الدخول (Login flow)

1. OpenIddict token (`connect/token`).
2. Admin: `Account/GetUserLoginWithRoleData?userId=`، ويضبط الفرع الافتراضي في الـ session.
3. Admin: `WFEmployee/GetWFEmpIdByUser?userId=`.
4. Admin: `GeneralSettingSide/GetEffectiveValuesByKeys?keys=att_...` لقراءة كل خيارات `att_*` في نداء واحد.
5. HR: `TAEmpMobile/GetMyLoginContext?deviceId=`.
6. إذا كانت `att_require_device = true` و`deviceStatus = NotRegistered`، يُستدعى HR: `TAEmpDevice/Register`.
7. قرار الدخول (Approved، أو Pending، أو Revoked/Suspended) يتخذه الجوال بناءً على الخيارات وحالة الجهاز.

---

## 1. Administration

### 1.1 `GET api/v1/Account/GetUserLoginWithRoleData`
- **الغرض:** بيانات المستخدم وأدواره وفرعه الافتراضي.
- **Params:** `userId` (Guid).
- **Response:** `List<UserLoginMetaData>` (roles، `DefaultBranchId`، `PofileImage` كـ signed URL، `DefaultBranchLogoPath`).
- **ملاحظات:**
  - تضبط `ConfigSession.CurrentBranchId` على الفرع الافتراضي، فيجب استدعاؤها قبل قراءة الخيارات.
  - إذا لم توجد أدوار ترجع قائمة فارغة مع 200.
- **من يستدعيها:** الجوال والويب.

### 1.2 `GET api/v1/WFEmployee/GetWFEmpIdByUser`
- **Params:** `userId` (Guid).
- **Response:** `Guid`، وهو `Guid.Empty` إذا لم يوجد WF employee.
- **من يستدعيها:** الجوال والويب.

### 1.3 `GET api/v1/GeneralSettingSide/GetEffectiveValueBySetting`
- **الغرض:** القيمة الفعلية لإعداد واحد.
- **Params:** `generalSettingAbb` (string).
- **ترتيب الحساب:** user ثم roles ثم branch ثم `DefaultValue`.
- **Response:** `string?`.
- **Errors:** 400 إذا كان المفتاح فارغًا، و404 إذا كان غير موجود، و500.
- **من يستدعيها:** الويب (`general-setting-side.service.ts`). لم تتغير.

### 1.4 `GET api/v1/GeneralSettingSide/GetEffectiveValuesByKeys` (جديد)
- **الغرض:** نسخة مجمّعة من 1.3 لعدة مفاتيح في نداء واحد، بنفس ترتيب الحساب ونفس الدالة الداخلية (`ResolveEffectiveValuesAsync`).
- **Params:** `keys` مكررة: `?keys=att_require_device&keys=att_max_devices&...`
- **Response:** `Dictionary<string, string?>`. المفتاح غير الموجود يرجع `null` (وليس 404)، والقائمة الفارغة ترجع `{}`.
- **Errors:** 500.
- **من يستدعيها:** الجوال عند الدخول.

### 1.5 المرفقات: `TABAttachements` (Admin)
- `POST api/v1/TABAttachements/GenaricAttachByNumber`: الرفع الذي يستخدمه الجوال حاليًا.
  - Params: `Description`، `_MenuKey`، `_pageParameter?`، `RecordId`، `folderNumber=0`، و`file` كـ `IFormFile` (multipart).
  - Response: `TABAttachements` ومنه `Id`.
- `GET api/v1/TABAttachements/GetFileDataWithStream?_MenuKey=&_pageParameter=&RecordId=`: قراءة مرفقات سجل.
- `POST api/v1/TABAttachements/DeleteFile?fileId=`: حذف مرفق.
- **ملاحظة:** صور فريق اليوم ستُرفع بنفس هذه الـ endpoints. الفرونت أو الجوال هو المسؤول عن الرفع وربطه بالسجل عبر `RecordId`.

---

## 2. HR

### 2.1 `GET api/v1/TAEmpMobile/GetMyLoginContext`
- **الغرض:** نداء واحد بعد الدخول يرجع بيانات الموظف وحالة الجهاز.
- **Params:** `deviceId?` (string).
- **Response:** `TAEmpMobileLoginContextDto`:
  - `empId`
  - `employee`: `empId`، `empCode`، `empFullAraName`، `empFullLatName`، `branchId`، `branchAraName`، `branchLatName`، `departmentId`، `depAraName`، `depLatName`
  - `paySlipId`: أول قسيمة نشطة حسب `PaySlipPriority`.
  - `deviceStatus`: `NotRegistered`، أو `Pending`، أو `Approved`، أو `Revoked`، أو `Suspended`.
  - `deviceRecordId`
  - `serverTime`
- **Errors:** 401 إذا لم يوجد مستخدم.
- **ملاحظات:**
  - لا يوجد `options` في الرد؛ الخيارات تُقرأ من 1.4.
  - `NotRequired` لا يرجعه السيرفر، بل يقرره الجوال إذا كانت `att_require_device = false`.
  - إذا لم يوجد موظف أو `deviceId`، ترجع الحالة `NotRegistered`.
- **من يستدعيها:** الجوال عند الدخول وفي الـ splash.

### 2.2 `TAEmpDevice` (أجهزة الموظف)
| Method | Route | Params / Body | Response | Errors |
|---|---|---|---|---|
| POST | `api/v1/TAEmpDevice/Register` | Body: `{ deviceId, deviceName?, platform? }` | `TAEmpDeviceDto` | 400 بدون deviceId، 401، 404 لا يوجد موظف للمستخدم |
| GET | `api/v1/TAEmpDevice/GetList` | `empId?`، `status?` (Pending/Approved/Revoked/Suspended) | `List<TAEmpDeviceDto>` | - |
| POST | `api/v1/TAEmpDevice/Approve` | `id` | `TAEmpDeviceDto` | 404 |
| POST | `api/v1/TAEmpDevice/Revoke` | `id` | `TAEmpDeviceDto` | 404 |
| POST | `api/v1/TAEmpDevice/Suspend` | `id` | `TAEmpDeviceDto` | 404 |

- **`TAEmpDeviceDto`:** `id`، `empId`، `identityUserId`، `deviceId`، `deviceName`، `platform`، `status`، `approvedBy`، `approvedAt`، `lastUsedAt`، `creationTime`، `empCode`، `empFullAraName`، `empFullLatName`.
- **Register:**
  - idempotent: نفس الموظف مع نفس `deviceId` يرجع السجل الموجود ويحدّث `lastUsedAt` و`deviceName` و`platform`.
  - السجل الجديد يكون **دائمًا `Pending`** حاليًا.
  - حدّ الأجهزة `att_max_devices` تقرؤه شاشة «أجهزة الموظفين» وتمرّره لـ `Approve?maxDevices=` فيرفض الزيادة (409). لا يوجد اعتماد تلقائي للأجهزة.
- `Register` يستدعيها الجوال. `GetList` و`Approve` و`Revoke` و`Suspend` يستدعيها الويب من شاشة اعتماد الأجهزة.
- **ملاحظة:** هذه الـ endpoints محمية بـ `[Authorize]` فقط، ولا توجد permissions مخصصة بعد.

### 2.3 الحضور الفردي: `TAEmpMachineAttendance`
- `POST api/v1/TAEmpMachineAttendance/SubmitAttendance`
  - Body (`TABSubmitAttendanceRequestDto`): `empId?`، `attendanceTypeCode` (1=CheckIn، 2=CheckOut، 3=Other)، `tabgpsLocationId?`، `tabQrCodeId?`، `scannedQrValue?`، `latitude?`، `longitude?`، `notes?`
  - Response (`TABAttendanceActivityDto`): `id`، `empId`، `attendanceDate`، `attendanceTime`، `attendanceTypeCode`، `attendanceWayCode`، `taSource`، `durationMinutes`، `notes`، `tabgpsLocationId` مع الاسم، `tabQrCodeId` مع الاسم، `latitude`، `longitude`، `isManualEntry`
  - Errors: `UserFriendlyException` إذا كان النوع خارج 1..3، أو فشل التحقق من الموقع أو الـ QR.
  - الوقت يُسجَّل بتوقيت `UtcNow` والمصدر `Mobile`.
- `GET api/v1/TAEmpMachineAttendance/GetActivities?empId=&fromDate=&toDate=&skipCount=0&maxResultCount=20`: سجل الحركات.
- `POST api/v1/TAEmpMachineAttendance/CreateManualEntry`: طلب يدوي (`[FromForm]` مع `photo?`).
- `GET api/v1/TAEmpDailyAttendance/GetByEmpId`: الحضور اليومي المحسوب، ويستخدمه الجوال للعرض.
- **ملاحظة:** البصمة (biometric) والصورة يتحقق منهما الجوال قبل الإرسال، والسيرفر لا يتحقق منهما.

### 2.4 `GET api/v1/TABGPSLocation/GetMyActiveLocations`
- **الغرض:** المواقع المسندة لموظف المستخدم الحالي اليوم، عبر `TABGPSLocationAssign` (موظف، أو قسم، أو فرع).
- **Response:** `List<TABGPSLocationDto>` (الإحداثيات ونصف القطر).
- **من يستدعيها:** الجوال قبل تسجيل الحضور، لحساب داخل أو خارج الدائرة.

### 2.5 فريق اليوم: `TDProject`
> تُضاف حاليًا حقول موقع للهيدر، وموقع للدخول وآخر للخروج لكل فوتر، وصور، و endpoints للمراجعة والترحيل. سيتم تحديث هذا القسم بعد انتهاء التنفيذ.

| Method | Route | Params / Body |
|---|---|---|
| GET | `TDProject/CurrentUserProjects` | - |
| GET | `TDProject/ProjectTeam` | `ProjectId`، `day?` |
| GET | `TDProject/ProjectManagers` | `excludeManagerId?` |
| GET | `TDProject/ProjectCrewAttendance` | `ProjectId`، `day`، `locationId?`، `shiftId?` |
| POST | `TDProject/SaveCrewAttendance` | `{ projectId, day, locationId, shiftId, lines[] }` |
| POST | `TDProject/PostCrewAttendance` | Body `PostCrewAttendanceInput`، و`empId?` في الـ query (ترحيل سطر أو ترحيل عام) |
| POST | `TDProject/RecordTeamDayHeader` | `{ projectId, day, locationId, shiftId, supervisorId?, latitude?, longitude? }` |
| POST | `TDProject/RecordTeamDayFooter` | `{ projectId, day, locationId, shiftId, lines[{ empId, supervisorId?, inTime?, outTime?, status, notes? }] }` |
| GET | `TDProject/TeamDayReviewHeaders` | `day?`، `projectId?`، `shiftId?`، `locationId?` (للمراجعة على الويب) |
| GET | `TDProject/TeamDayReviewDetail` | `headerId` |
| POST | `TDProject/ReviewTeamDayLines` | `{ headerId, lineIds[], reviewStatus (1 اعتماد / 2 رفض), reviewNotes? }`. لو `lineIds` فاضية يتعمل اعتماد جماعي للمعلّق |
| POST | `TDProject/CloseTeamDayHeader` | `{ headerId, latitude?, longitude?, locationAccuracyMeters?, recordedAt? }`: انصراف المشرف وقفل اليوم (Closed) |
| GET | `TDProject/ProjectTeamCalendar` | `ProjectId`، `fromDate`، `toDate`، `coverageTarget?` |

- `RecordTeamDayHeader` ترجع `{ header, locationWarning }`.
- `RecordTeamDayFooter` ترجع `{ header, items[], warnings[] }`.
- الـ header بيرجع فيه `distanceMeters` و`insideGeofence`، وكل footer فيه `in/outDistanceMeters` و`in/outInsideGeofence` (بتتحسب في البك اند).
- الصور بتترفع على `TABAttachements/GenaricAttachByNumber` بـ `_menukey=TeamDay`: صورة الـ header `recordid=header.id`، وصورة الحضور أو الانصراف `recordid=footer.id`، و`pageParameter` = `header` أو `in` أو `out`.
- السطر المرفوض (`reviewStatus=2`) مش بيترحّل في `PostCrewAttendance`.
- العمال من غير موبايل: موبايل المشرف بيبعت لوكيشن الحضور والانصراف وصورة كل عامل. لوكيشن الـ header = حضور المشرف (`supervisorInTime`)، و`CloseTeamDayHeader` = انصراف المشرف، والـ header بيرجع فيه `supervisorOutTime` و`outLatitude/outLongitude` و`outDistanceMeters/outInsideGeofence`.
- كل الـ routes بالبادئة `api/v1/`.
- يوجد أيضًا CRUD القياسي لكل من `TDAttendanceH` و`TDAttendanceF` و`TDLocation` و`TDSupervisor` و`TDEmployeeTransfer`: `GetAllData`، `GetalldatabyfilterWithCount`، `GridList`، `Getbyid`، `Create`، `CreateBulkData`، `Update`، `Delete`.

---

## 3. خيارات الحضور `att_*` (General Settings، مجموعة «الحضور عبر الجوال»)

| Key | Default | المعنى |
|---|---|---|
| `att_require_location` | false | يشترط إرسال الموقع |
| `att_inside_location` | false | يشترط أن يكون الموظف داخل دائرة الموقع |
| `att_reject_mock` | false | يرفض المواقع الوهمية (mock) |
| `att_require_device` | false | يشترط جهازًا مسجلًا ومعتمدًا |
| `att_max_devices` | 1 | أقصى عدد أجهزة للموظف |
| `att_require_biometric` | false | يشترط البصمة أو الوجه |
| `att_biometric_types` | `fingerprint,face` | الأنواع المسموح بها |
| `att_require_photo` | false | يشترط صورة |
| `att_allow_exception` | false | يسمح بالاستثناء |
| `att_allow_manual_request` | false | يسمح بالطلب اليدوي |

> **مهم:** الخيارات يطبّقها **الفرونت أو الجوال** وليس السيرفر. السيرفر لا يقرأ `att_*`، وتسجيل الجهاز `Pending` دائمًا حاليًا.
> القيم ترجع كـ string، فيحوّلها العميل (`"true"` إلى bool، و`"1"` إلى int). القيمة `null` تعني استخدام الـ default الموضح أعلاه.

## إدارة أجهزة الموظفين (شاشة الويب «أجهزة الموظفين»)
| الطريقة | المسار | الوصف |
|---|---|---|
| GET | api/v1/TAEmpDevice/GetFilteredList | فلاتر: BranchId, DepartmentId, EmpId, Status (افتراضي Pending في الشاشة)، PageIndex, PageSize (≤500، افتراضي 50). يعيد Items, TotalCount، ولكل عنصر ApprovedDevicesCount |
| POST | api/v1/TAEmpDevice/Approve?id=&maxDevices= | maxDevices اختياري؛ عند تجاوز الحد يعاد الرمز 409 |
| POST | api/v1/TAEmpDevice/BulkApprove | Body: { ids: [], maxDevices? } ← { approvedCount, approved, failed:[{id,code,reason}] }؛ 400 إن كانت القائمة فارغة |
| POST | api/v1/TAEmpDevice/Suspend, Revoke | بلا تغيير |

**الصلاحيات:** عبر مرشح الكيانات العام (TabEntityAuthorizationFilter): القراءة تتطلب Access على TAEmpDevice، والاعتماد/الإيقاف/الإلغاء/الاعتماد الجماعي تتطلب Create. يُستثنى Register و TAEmpMobile/GetMyLoginContext بالسمة HRSkipEntityAuthorization ليبقيا متاحين للموظف.
