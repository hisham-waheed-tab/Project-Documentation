# 3) فريقي اليوم (المشرف)

> الـ routes بالصيغة `api/v1/TDProject/...`، والردود `{ statuscode, message, result, success }`، و`Bearer token`.
> **المرجع:** شاشة الويب `self-services/team-day`. افتحها وراقب الـ Network في F12 وانسخ نفس النداءات بنفس الترتيب والـ bodies.

## الفكرة

المشرف هو اللي بيسجّل لكل الفريق (العمال بدون موبايل). موبايل المشرف يبعت موقعه وقت التسجيل وصورة كل عامل. المسافة من موقع المشروع تتحسب في السيرفر، وإذا كانت خارج النطاق يرجع **تنبيه فقط، مش منع**.

## الخطوات

1. اختيار المشروع والموقع والوردية: `GET CurrentUserProjects`، ثم `GET ProjectTeam?ProjectId=&day=` لتحميل الفريق.
2. **بدء اليوم (الهيدر لوحده):** `POST RecordTeamDayHeader`، وموقع المشرف هو حضوره.
3. **حضور وانصراف كل موظف (الفوتر لوحده):** `POST RecordTeamDayFooter` لكل سطر، ثم رفع الصورة.
4. **إنهاء اليوم:** `POST CloseTeamDayHeader`، وموقع المشرف هو انصرافه.
5. تحميل يوم محفوظ سابقًا: `GET ProjectCrewAttendance?ProjectId=&day=&locationId=&shiftId=`.
6. الترحيل: **لا يعمله الموبايل** إلا لو الخيار `td_post_from_admin = false`. وفي الحالة الافتراضية (true) الترحيل من شاشة المراجعة في الويب.

> الخيارات اللي تهم الشاشة (من الملف الأول): `att_require_location` و`att_require_photo` و`att_allow_exception` و`td_post_from_admin`. تطبيقها على الموبايل. لو الموقع أو الصورة تعذّر وكان الاستثناء مسموحًا، اطلب تأكيد المتابعة كاستثناء، وإلا ارفض العملية.

## Endpoints

### `POST RecordTeamDayHeader`
```json
{
  "projectId": "guid", "day": "2026-10-24", "locationId": "guid", "shiftId": "guid",
  "supervisorId": null,
  "latitude": 30.0444, "longitude": 31.2357,
  "locationAccuracyMeters": 10, "locationRecordedAt": "2026-10-24T07:55:00Z"
}
```
- `locationId` هو موقع المشروع (`TDLocation`). حقول الموقع كلها اختيارية.
- الـ result: `{ header, locationWarning }`، و`header.id` مهم للصورة والإنهاء.

### `POST RecordTeamDayFooter`
```json
{
  "projectId": "guid", "day": "2026-10-24", "locationId": "guid", "shiftId": "guid",
  "lines": [
    { "empId": "guid", "supervisorId": null, "inTime": "08:05:00", "outTime": null,
      "status": 1, "notes": null,
      "inLatitude": 30.0445, "inLongitude": 31.2358,
      "inLocationAccuracyMeters": 8, "inLocationRecordedAt": "2026-10-24T08:05:00Z" }
  ]
}
```
- الإرسال سطر بسطر حسب ما المشرف بيسجّل. وتسجيل السطر نفسه تاني يحدّثه (upsert).
- الانصراف بنفس الطلب بـ `outTime` وحقول `out*` (`outLatitude` و`outLongitude` و`outLocationAccuracyMeters` و`outLocationRecordedAt`).
- `status`: 0 غير محدد، 1 حاضر، 2 غائب، 3 منقول.
- الـ result: `{ header, items[], warnings[] }`. و`items[].id` هو رقم سطر الفوتر المطلوب للصورة. و`warnings[]` فيها `empId` و`point` (`In` أو `Out`) و`isOutsideGeofence` و`distanceMeters` و`allowedDistanceMeters`.

### `POST CloseTeamDayHeader`
```json
{ "headerId": "guid", "latitude": 30.04, "longitude": 31.23, "locationAccuracyMeters": 9, "recordedAt": "2026-10-24T16:00:00Z" }
```
- يسجّل انصراف المشرف وتبقى حالة الهيدر `Closed` (5). الحالات: 1 Open، 2 Prepared، 3 Sent، 4 Approved، 5 Closed.
- الـ result: `{ headerId, status, supervisorOutTime, out, locationWarning }`.

### رفع الصورة
`POST TABAttachements/GenaricAttachByNumber` (على Administration host) بـ `multipart/form-data`:

| الحقل | القيمة |
|---|---|
| `_MenuKey` | `TeamDay` |
| `_pageParameter` | `header` لصورة بداية اليوم، `in` لصورة حضور موظف، `out` لصورة انصرافه |
| `RecordId` | `header.id` للهيدر، أو `items[].id` للسطر |
| `Description` | أي وصف قصير |
| `folderNumber` | `0` |
| `file` | الصورة (من الكاميرا فقط) |

- الصورة تُرفع بعد نجاح الحفظ، لأن `RecordId` يأتي من ردّه.

## ملاحظات

- الهيدر المقفول (Closed) ما زال ممكنًا ترحيله من الويب.
- السطر المرفوض في المراجعة لا يترحّل أبدًا، والمترحّل لا يتراجع.
- المراجعة والاعتماد (`TeamDayReviewHeaders` و`TeamDayReviewDetail` و`ReviewTeamDayLines`) على الويب فقط، والموبايل لا يستدعيها.