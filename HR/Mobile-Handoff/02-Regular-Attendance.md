# 2) الحضور العادي (بالموقع)

> نفس الأسلوب: routes بالصيغة `api/v1/...`، والردود `{ statuscode, message, result, success }`، و`Bearer token`.

## الخطوات على الشاشة

1. المستخدم **لا يختار موقعًا**. المواقع المسندة له تأتي من `GetMyActiveLocations`، ويحسب الموبايل أقرب موقع وهل هو داخل النطاق.
2. قبل الإرسال حسب الخيارات (من الملف الأول):
   - `att_require_biometric`: اطلب بصمة أو وجه من الأنواع المسموحة، ولو فشلت أوقف العملية.
   - `att_require_photo`: افتح الكاميرا فقط (بدون معرض الصور).
   - خذ موقعًا جديدًا. و`att_reject_mock`: ارفض الموقع الوهمي.
3. أرسل `SubmitAttendance`.
4. لو اترفض وكان `att_allow_exception` أو `att_allow_manual_request` مفعّلًا، اعرض زر الطلب المناسب.

> البصمة والصورة والموقع الوهمي يتحقق منها الموبايل فقط. السيرفر يتحقق من الموقع أو الـ QR وقت الحفظ.

## Endpoints

### `GET TABGPSLocation/GetMyActiveLocations`
- المواقع المسندة للموظف اليوم، سواء عليه مباشرة أو على قسمه أو فرعه.
- الـ result: قائمة فيها الاسم والإحداثيات ونصف القطر.

### `POST TAEmpMachineAttendance/SubmitAttendance`
- الـ Body:
```json
{
  "attendanceTypeCode": 1,
  "tabgpsLocationId": "guid",
  "latitude": 30.0444,
  "longitude": 31.2357,
  "notes": null
}
```
- `attendanceTypeCode`: 1 حضور، 2 انصراف، 3 أخرى. `empId` اختياري (الافتراضي موظف المستخدم الحالي).
- ممكن بدل الموقع إرسال `tabQrCodeId` و`scannedQrValue` للـ QR.
- الوقت يسجله السيرفر (UTC) والمصدر `Mobile`.
- الـ result: `id` و`attendanceDate` و`attendanceTime` و`attendanceTypeCode` وبيانات الموقع.
- الأخطاء: رسالة واضحة (`UserFriendlyException`) لو النوع خارج 1 إلى 3، أو الموقع أو الـ QR غير صحيح.

### `GET TAEmpMachineAttendance/GetActivities`
- الـ params: `empId` و`fromDate` و`toDate` و`skipCount=0` و`maxResultCount=20`. يرجع سجل الحركات.

### `POST TAEmpMachineAttendance/CreateManualEntry`
- طلب حضور يدوي، يُرسل `multipart/form-data` (`[FromForm]`) ومعه `photo` اختيارية.

### `GET TAEmpDailyAttendance/GetByEmpId`
- الحضور اليومي المحسوب للعرض في الموبايل.