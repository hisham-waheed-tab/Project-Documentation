# فريقي اليوم - GPS والموقع (TeamDay)

## الفكرة
- كل موقع مشروع `TDLocation` يتربط اختياريًا بموقع جغرافي `TABGPSLocation` - من غير تكرار خطوط الطول والعرض.
- الهيدر هو دليل حضور المشرف نفسه: مكانه ووقت تسجيله. الفوتر: مكان كل موظف عند الحضور والانصراف.
- كل حقول الموقع اختيارية بالكامل - لا يوجد أي إلزام، وأي Tenant يقدر يسجل من غير موقع أو صورة.

## الجداول
| الجدول | الحقول الجديدة (كلها NULL) |
|---|---|
| `TDLocation` | `tabgpslocationid` FK -> `TABGPSLocation`، و `diametermeters` int اختياري (تجاوز لقطر/مسافة الموقع؛ لو فاضي نستخدم `TABGPSLocation.radiusmeters`) |
| `TDAttendanceH` | `supervisorid` FK -> `TDSupervisor`، `latitude/longitude`، `locationaccuracymeters`، `locationrecordedat` |
| `TDAttendanceF` | `inlatitude/inlongitude` + دقة ووقت، و `outlatitude/outlongitude` + دقة ووقت |

لا يوجد جدول صور جديد. الصور تستخدم المرفقات العامة: `TABAttachements` مع `MenuKey = 'TeamDay'` و `RecordId` = Id سطر الموظف `TDAttendanceF` لصور الموظف، أو Id الهيدر `TDAttendanceH` لصورة إغلاق اليوم.

## Endpoints (TDProject)
| Endpoint | الاستخدام |
|---|---|
| `POST /api/v1/TDProject/RecordTeamDayHeader` | تسجيل الهيدر وحده: ينشئ/يضمن الهيدر (مشروع/يوم/موقع/وردية) + موقع المشرف. يرجع الهيدر وتحذير geofence |
| `POST /api/v1/TDProject/RecordTeamDayFooter` | تسجيل سطور الفوتر وحدها (upsert لكل موظف): أوقات حضور/انصراف + موقع In/Out. يرجع السطور وتحذيرات geofence لكل نقطة |

- الـ geofence تحذير فقط (`isoutsidegeofence` + المسافة + المسافة المسموحة) - لا يمنع الحفظ أبدًا.
- الـ endpoints القديمة `SaveCrewAttendance` / `PostCrewAttendance` كما هي بدون تغيير.
- شاشة الويب `td-project`: قسم المواقع فيه اختيار GPS Location + قطر اختياري. شاشة TeamDay على الويب لا تعرض موقع الهيدر/الفوتر (للموبايل فقط).

## Migration
`20261019130813_Add_TeamDay_GPS_Locations` - مكتوبة و idempotent، **لم تُطبق**. التطبيق يحتاج تأكيد الفرع أولًا (development = Dev-TABMS، و main = إنتاج Google) لأن لكل فرع قاعدة بياناته.

## لاحقًا (غير منفذ الآن)
- خيارات GeneralSetting لإلزام/منع الموقع أو الصورة حسب الـ Tenant.
- التحقق من الجهاز المعتمد والبصمة الحيوية (تاسك منفصلة).