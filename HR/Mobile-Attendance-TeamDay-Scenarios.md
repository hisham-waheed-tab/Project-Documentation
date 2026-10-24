# سيناريوهات الموبايل: الحضور باللوكيشن + فريقي اليوم (DRAFT)

> كل endpoint عليه tag: **[موجود]** أو **[جديد]**. الـ responses كلها شكلها `{ statuscode, message, result, success }`، والأمثلة تحت فيها `result` بس.

## إعداد الأوبشنات (مرة واحدة بواسطة المبرمج)
1. نعمل Group من شاشة GeneralSettingGroup: `admin/GeneralSettingGroup/:id` أو `tab-administration/GeneralSettingGroup/:id`.
2. نعمل كل Setting بالـ ABB والـ DefaultValue بتوعه من شاشة GeneralSetting: `admin/GeneralSetting/:id` أو `tab-administration/GeneralSetting/:id`.
3. الـ tenant بيغير القيمة أو بيعمل استثناء لفرع أو دور أو يوزر من شاشة GeneralSettingSide: `admin/GeneralSettingSide/:id`. الخطوة دي مش شغلنا.

| ABB | النوع | Default | المعنى |
|---|---|---|---|
| `att_require_location` | bool | true | الموقع إجباري |
| `att_inside_location` | bool | true | لازم يكون جوه نطاق موقع معين. لو false الموقع بيتسجل بس |
| `att_reject_mock` | bool | true | رفض الـ mock location |
| `att_require_device` | bool | false | الجهاز لازم يكون معتمد |
| `att_max_devices` | int | 1 | أقصى عدد أجهزة معتمدة لكل يوزر |
| `att_require_biometric` | bool | false | طلب بصمة الموبايل قبل الحفظ |
| `att_biometric_types` | csv | fingerprint,face | الأنواع المسموحة: fingerprint/face/voice/palm/photo |
| `att_require_photo` | bool | false | صورة بالكاميرا فقط، من غير gallery أو ملفات |
| `att_allow_exception` | bool | false | السماح بطلب استثناء |
| `att_allow_manual_request` | bool | false | السماح بطلب حضور يدوي |

السيرفر (HR) بيقرا نفس الأوبشنات دي وقت الحفظ ويطبقها بنفسه، ومش بيعتمد على اللي الموبايل بيقوله.

---

## A) بعد الـ Login
1. الـ Login عادي (OpenIddict / flutter_appauth).
2. نقرا الأوبشنات (A1) ونعملها cache.
3. لو `att_require_device` = true: نسجل الجهاز أو نتأكد من حالته (A2/A3).
4. لو حالة الجهاز مش `Approved`: أزرار الحضور تتقفل وتظهر رسالة، وباقي التطبيق شغال عادي.

### A1. قراءة أوبشن: [موجود]
`GET /api/v1/GeneralSettingSide/GetEffectiveValueBySetting?generalsettingabb=att_require_location`
على Administration host. الكود في `GeneralSettingSideService.cs`.
```json
{ "result": "true" }
```
- القيمة بتتحدد بالترتيب ده: اليوزر الحالي ← أدواره ← الفرع الحالي ← DefaultValue، وكله في حدود الـ tenant.
- القيمة بترجع string دايماً، والموبايل بيحولها لـ bool أو int أو list.

**[جديد، اختياري]** نسخة batch عشان ما نعملش 10 calls:
`GET /api/v1/GeneralSettingSide/GetEffectiveValuesBySettings?abbs=att_require_location,att_max_devices,...`
```json
{ "result": { "att_require_location": "true", "att_max_devices": "1", "att_biometric_types": "fingerprint,face" } }
```

### A2. تسجيل الجهاز: [جديد]
`POST /api/v1/TAEmpDevice/Register`
```json
// request
{ "deviceId": "android-id-or-idfv", "platform": "android", "model": "SM-A366B", "osVersion": "15", "appVersion": "1.4.0", "biometricEnrollmentHash": "opaque" }
// result
{ "status": "Approved", "deviceRecordId": "guid" }
```
- `status` واحدة من: Approved / Pending / Revoked / Suspended.
- أول جهاز بيتعمل Approved تلقائي. أي جهاز زيادة عن `att_max_devices` بيبقى Pending.
- `biometricEnrollmentHash`: قيمة بتتغير لما بصمات الجهاز تتغير. لو اتغيرت الجهاز بيبقى Suspended لحد ما يتعمله re-approval.
- `deviceId` بيتبعت في header اسمه `X-Device-Id` مع كل طلبات الحضور.

### A3. حالة الجهاز: [جديد]
`GET /api/v1/TAEmpDevice/GetMyDeviceStatus?deviceId=` بيرجع نفس result بتاع A2. بننادي عليه عند فتح أي شاشة حضور.

---

## B) شاشة الحضور باللوكيشن
1. اليوزر **مش بيختار موقع**. فيه icon (i) اختياري بيفتح dialog فيه المواقع المتاحة: الاسم والعنوان والنطاق، ولينك خريطة خارجي `https://maps.google.com/?q=lat,lng` بيفتح تطبيق الخرائط بره تطبيقنا. الـ dialog بيجيب البيانات من B0.
2. عند فتح الشاشة: نجيب الموقع ونبعته لـ B1، ونعرض أقرب موقع وهل اليوزر جوه النطاق. زرار "اختبار" بيعيد الفحص ده بس.
3. زرار الحضور/الانصراف:
   1. لو `att_require_biometric`: نطلب بصمة من الأنواع المسموحة اللي الجهاز يدعمها، ولو فشلت نوقف.
   2. لو `att_require_photo`: نفتح الكاميرا.
   3. ناخد موقع جديد.
   4. نبعت B2، والسيرفر بيعيد كل الفحوصات.
4. لو اترفض وكان `att_allow_exception` مفعل: يظهر زرار "طلب استثناء" (B3). ولو `att_allow_manual_request` مفعل: يظهر "طلب حضور يدوي".

### B0. المواقع المتاحة: [موجود]
`GET /api/v1/TABGPSLocation/GetMyActiveLocations`
```json
[ { "id": "guid", "name": "Head Office", "address": "...", "latitude": 30.045, "longitude": 31.236, "radiusMeters": 150 } ]
```
بيرجع المواقع المعينة للموظف على مستوى الفرع أو القسم أو الموظف نفسه، في حدود الفترة.

### B1. فحص الموقع: [جديد]
`POST /api/v1/TAEmpMachineAttendance/CheckMyLocation`
```json
// request
{ "latitude": 30.0444, "longitude": 31.2357, "accuracyMeters": 12.5, "recordedAt": "2026-10-22T08:01:10Z", "isMock": false }
// result
{ "nearestLocation": { "id": "guid", "name": "Head Office", "radiusMeters": 150 }, "distanceMeters": 72.4, "isInside": true, "issues": [] }
```
- `issues` ممكن يكون فيها: `OUT_OF_RANGE` / `STALE_LOCATION` / `LOW_ACCURACY` / `MOCK_LOCATION` / `NO_ASSIGNED_LOCATION` / `DEVICE_NOT_APPROVED`.
- السيرفر هو اللي بيحسب المسافة من المواقع المعينة للموظف.

### B2. حفظ الحضور: [موجود، بإضافة حقول]
`POST /api/v1/TAEmpMachineAttendance/SubmitAttendance`
```json
// request
{ "attendanceTypeCode": 1, "latitude": 30.0444, "longitude": 31.2357, "accuracyMeters": 9.0, "recordedAt": "2026-10-22T08:02:00Z",
  "isMock": false, "biometricVerified": true, "biometricType": "fingerprint", "notes": null }
// result
{ "id": "guid", "attendanceTypeCode": 1 }
```
- `attendanceTypeCode`: 1 حضور، 2 انصراف، 3 أخرى.
- الحقول الجديدة: `accuracyMeters` و`recordedAt` و`isMock` و`biometricVerified` و`biometricType`.
- الموقع بيحدده السيرفر، أقرب موقع معين.
- الصورة (لو مطلوبة) بتتبعت multipart في نفس الطلب.
- الأخطاء: `OUT_OF_RANGE` / `STALE_LOCATION` / `LOW_ACCURACY` / `MOCK_LOCATION` / `DEVICE_NOT_APPROVED` / `BIOMETRIC_REQUIRED` / `PHOTO_REQUIRED`.

### B3. طلب استثناء / حضور يدوي: [جديد]
`POST /api/v1/TAAttendanceException/Create`
```json
{ "requestType": "Exception", "attendanceTypeCode": 1, "latitude": 30.05, "longitude": 31.25, "accuracyMeters": 20,
  "recordedAt": "...", "requestedTime": null, "reasonCode": "OUT_OF_RANGE", "notes": "في موقع العميل" }
```
- `requestType`: Exception أو Manual. في حالة Manual بنبعت `requestedTime`.
- الطلب بيمشي على الـ workflow، وطول ما هو Pending مش بيتحسب حضور.
- المرفقات صور كاميرا فقط: `_menukey='Requests'` و`recordid` = id الطلب.

---

## C) شاشة فريقي اليوم (المشرف)
1. المشرف يفتح اليوم ويختار المشروع والموقع والوردية، والفريق بيتحمل.
2. يسجل حضوره هو بموقعه الحالي ← C1. الـ header هو دليل حضور المشرف.
3. لكل موظف: حضور أو انصراف بالموقع وصورة كاميرا ← C2 للسطر، وبعده C3 للصورة.
4. يقفل اليوم ويرحله، والصورة اختيارية ← C4.
- المسافة بتتقارن بموقع المشروع `TDLocation`: بـ Diameter لو موجود، ولو مش موجود بـ RadiusMeters بتاع الـ GPS location. لو بره النطاق يظهر **تنبيه بس، مش منع**.

### C1. حفظ الـ header: [موجود]
`POST /api/v1/TDProject/RecordTeamDayHeader`
```json
// request
{ "projectId": "guid", "day": "2026-10-22", "locationId": "guid", "shiftId": "guid", "supervisorId": null,
  "latitude": 30.0444, "longitude": 31.2357, "locationAccuracyMeters": 10, "locationRecordedAt": "2026-10-22T07:55:00Z" }
// result
{ "header": { "id": "guid" }, "locationWarning": { "isOutsideGeofence": true, "distanceMeters": 420.3, "allowedDistanceMeters": 200, "warning": "..." } }
```
- `locationId` = موقع المشروع `TDLocation`.

### C2. حفظ سطر موظف: [موجود] (upsert)
`POST /api/v1/TDProject/RecordTeamDayFooter`
```json
// request
{ "projectId": "guid", "day": "2026-10-22", "locationId": "guid", "shiftId": "guid",
  "lines": [ { "empId": "guid", "inTime": "08:05:00", "outTime": null, "status": 1, "notes": null,
               "inLatitude": 30.0445, "inLongitude": 31.2358, "inLocationAccuracyMeters": 8, "inLocationRecordedAt": "..." } ] }
// result
{ "header": {}, "items": [ { "id": "guid", "empid": "guid" } ],
  "warnings": [ { "empId": "guid", "point": "In", "isOutsideGeofence": true, "distanceMeters": 310, "allowedDistanceMeters": 200 } ] }
```
- `point`: In أو Out.
- الانصراف بنفس الطلب، بـ `outTime` وحقول `out*`.

### C3. صورة الموظف أو المشرف: [موجود]
attachment pattern: `DataWithAttchments` multipart، بحقول `Data.*` و`AttachedFiles`، وبعدها `AddAttachList` في `atttachdoc` بـ `dmsScreen` و`dmsKey`.
- `MenuKey='TeamDay'`.
- `RecordId`: id الـ footer لصورة الموظف، أو id الـ header لصورة المشرف أو الإقفال.

### C4. قفل وترحيل اليوم: [موجود]
`POST /api/v1/TDProject/PostCrewAttendance`. الصورة الاختيارية بتترفع على الـ header زي C3.

---

## نقاط مفتوحة
1. HR يقرا الأوبشنات إزاي بنفس الترتيب (يوزر ← دور ← فرع ← default)؟
2. نعمل الـ batch endpoint ولا لأ؟
3. صورة الحضور: multipart في نفس الطلب ولا upload بعده؟
4. `deviceId` وتغيير البصمات على iOS.
5. مؤجل: Play Integrity / App Attest، OTP للجهاز، فحص Developer Mode.
6. مراجعة الـ defaults.