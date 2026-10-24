# 1) ما بعد تسجيل الدخول وتسجيل الجهاز

> مرجع مختصر مأخوذ من الكود الفعلي. كل الـ routes بالصيغة `api/v1/{Controller}/{Action}`، وكل الردود مغلّفة في `{ statuscode, message, result, success }`. كل الـ endpoints تحتاج `Bearer token`.
> مسار الدخول نفسه (OpenIddict) يعمله مطوّر الموبايل بنفسه. هذا الملف يشرح ما يُستدعى بعده.

## الترتيب

1. `connect/token` (OpenIddict) للحصول على الـ token.
2. Admin: `GET Account/GetUserLoginWithRoleData?userId=` يرجع الأدوار والفرع الافتراضي. **لازم يُستدعى قبل قراءة الخيارات** لأنه يضبط الفرع الحالي في الـ session.
3. Admin: `GET WFEmployee/GetWFEmpIdByUser?userId=` يرجع `Guid` (وهو `Guid.Empty` لو مفيش موظف).
4. Admin: `GET GeneralSettingSide/GetEffectiveValuesByKeys?keys=att_require_location&keys=att_require_device&...` يقرأ كل خيارات `att_*` في نداء واحد.
5. HR: `GET TAEmpMobile/GetMyLoginContext?deviceId=` يرجع بيانات الموظف وحالة الجهاز.
6. لو `att_require_device = true` وحالة الجهاز `NotRegistered`: HR `POST TAEmpDevice/Register`.
7. الموبايل يقرر: لو الجهاز `Approved` تفتح أزرار الحضور. لو `Pending` أو `Revoked` أو `Suspended` تتقفل أزرار الحضور وتظهر رسالة، وباقي التطبيق يشتغل عادي.

## تفاصيل الـ endpoints

### قراءة الخيارات `GetEffectiveValuesByKeys`
- الـ params: `keys` مكررة. الرد `Dictionary<string, string?>`.
- المفتاح غير الموجود يرجع `null` (مش 404). القيمة بترجع string، والموبايل يحوّلها (`"true"` إلى bool، `"1"` إلى int). و`null` تعني استخدام الـ default.
- الترتيب: المستخدم ثم الأدوار ثم الفرع ثم `DefaultValue`.

| الخيار | الافتراضي | المعنى |
|---|---|---|
| `att_require_location` | false | الموقع إجباري |
| `att_inside_location` | false | لازم يكون داخل نطاق موقع معيّن |
| `att_reject_mock` | false | رفض الموقع الوهمي |
| `att_require_device` | false | جهاز مسجّل ومعتمد |
| `att_max_devices` | 1 | أقصى عدد أجهزة للموظف |
| `att_require_biometric` | false | بصمة أو وجه قبل الحفظ |
| `att_biometric_types` | `fingerprint,face` | الأنواع المسموحة |
| `att_require_photo` | false | صورة بالكاميرا |
| `att_allow_exception` | false | السماح بالاستثناء |
| `att_allow_manual_request` | false | السماح بالطلب اليدوي |

> **مهم:** تطبيق هذه الخيارات على الموبايل. السيرفر لا يقرأ `att_*`.

### `GetMyLoginContext`
- الـ result: `empId`، و`employee` (الكود والاسم عربي وإنجليزي والفرع والإدارة)، و`paySlipId`، و`deviceStatus`، و`deviceRecordId`، و`serverTime`.
- `deviceStatus`: `NotRegistered` أو `Pending` أو `Approved` أو `Revoked` أو `Suspended`.
- `NotRequired` لا يرجعه السيرفر. الموبايل يقرره لما `att_require_device = false`.
- بدون موظف أو بدون `deviceId` الحالة `NotRegistered`. و401 لو لا يوجد مستخدم.

### `POST TAEmpDevice/Register`
- الـ Body: `{ "deviceId": "...", "deviceName": "...", "platform": "android" }` (`deviceId` إجباري).
- يرجع `TAEmpDeviceDto` فيه `id` و`status`.
- لو نفس الموظف سجّل نفس الجهاز قبل كده يرجع نفس السجل ويحدّث `lastUsedAt`.
- السجل الجديد **دائمًا `Pending`**. الاعتماد من شاشة «أجهزة الموظفين» في الويب، والحد `att_max_devices` يتطبّق وقت الاعتماد هناك.
- الأخطاء: 400 بدون `deviceId`، و401، و404 لو لا يوجد موظف للمستخدم.