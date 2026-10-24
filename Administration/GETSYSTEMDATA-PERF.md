# تحسين أداء GetSystemData (Administration / Security)

**الملف:** `Administration/src/TABMS.Adminstration.Application/Services/Security/TABSystemsService.cs`
**الـ Endpoint:** `GET api/v1/TABSystems/GetSystemData?userId=` (بيتنده من الفرونت لعرض أنظمة اليوزر في الصفحة الرئيسية)

## الدالة بتعمل إيه
1. بتجيب أكواد الأنظمة المسموحة لليوزر من `TABUserPermission` (Access=true) ومن صلاحيات الـ roles بتاعته (`TABUserRoles` → `TABTenantRolePermission`).
2. الأنظمة الخارجية (`PageUrl` بيبدأ بـ http) بتتسمح بس لو فيه ABP permission عنده `ExtraProperties.SystemId = Code` ومتدّية لليوزر (`U`) أو لأي role من رولاته (`R`، الـ key هو اسم الـ role).
3. بترجّع `TABSystemsDtoWithIconPath` (مع signed URL للأيقونة) والترجمات من `AbpLanguageTexts` (Resource = `TAB-system`).
4. كل ده جوه `DataFilter.Disable<IMultiTenant>()`.

## التعديلات (من غير cache ولا جداول ولا migrations)
| الجزء | قبل | بعد |
|---|---|---|
| صلاحيات الـ roles | `ToList()` لـ role ids وبعدين query تانية بـ `Contains` | الـ role ids بقت subquery، يعني round trip واحد |
| الترجمات | تحميل **كل** نصوص `TAB-system` والفلترة في الذاكرة | فلترة في الـ DB على الاسم بعد الـ normalize (`Replace` CRLF/CR ثم `Trim`)، وسبنا فلترة الذاكرة زي ما هي كـ safety net |
| صلاحيات ABP للأنظمة الخارجية | `FindAsync` لكل permission × (اليوزر + كل role)، يعني N+1 ممكن يوصل لمئات الـ queries | `IPermissionGrantRepository.GetListAsync(names[], provider, key)` مرة لليوزر ومرة لكل role، وبعدين المطابقة بـ `HashSet` في الذاكرة |

## ليه النتيجة زي ما هي
- نفس الـ predicates، والـ permission بيتحسب لو متدّي لليوزر أو لأي role بالظبط زي الأول.
- الترتيب والـ DTO والـ projection متغيروش.

## ملاحظات ومخاطر
- لأن الـ IMultiTenant filter مقفول، الـ grants بتتجاب من كل الـ tenants بنفس اسم الـ role (السلوك ده كان موجود من قبل، ومتغيرش).
- فيه فرق نظري صغير: `Trim()` في PostgreSQL بيشيل whitespace ASCII بس، أما .NET `Trim` فبيشيل Unicode whitespace كمان. لو فيه اسم ترجمة فيه مسافات Unicode غريبة في أوله أو آخره، ممكن ميرجعش.
- الـ backup الأصلي موجود في `%TEMP%\sysdata\orig\TABSystemsService.cs`.
---

# تحسينات أداء إضافية (13-10-2026)

## 1) الإشعارات: request واحد بدل اتنين وقت فتح الصفحة الرئيسية
**الملف:** `Tab-MS-Front/src/app/tabms/components/global/notifications/notifications.component.ts`
- **قبل:** وقت التحميل، ومع فتح المنيو، ومع إشعار SignalR، ومع "قراءة الكل"، كان بيضرب `showAll(true)` و`showUnRead(true)` مع بعض، فبيطلع طلبين `TABNotificationsUsers/GetalldatabyfilterWithCount` في نفس الوقت (واحد بـ `Read=false` وواحد من غيره).
- **بعد:** فيه دالة جديدة `refreshLists()` بتجيب الـ unread بس، لأنه هو اللي بيطلّع رقم الـ badge وهو التاب الافتراضي. قائمة "الكل" بتتجاب بس لو التاب بتاعها هو المفتوح. لو مش مفتوح، بنفضّي القائمة، و`onTabChange()` بتجيبها لما اليوزر يدوس على التاب.
- **الـ UI مش هيتغير:** رقم الـ badge وقائمة غير المقروء زي ما هما. قائمة "الكل" بتظهر بس لما تابها يتفتح (`@for ... selectedTab === 'unRead' ? ... : allNotifications`).

## 2) Response Compression (Brotli + Gzip)
**الملفات:** `Administration/.../AdminstrationHttpApiHostModule.cs` و`hr/.../HRHttpApiHostModule.cs`
- في `ConfigureServices`: ضفنا `AddResponseCompression` بـ `EnableForHttps = true`، وBrotli الأول وبعده Gzip، والـ MimeTypes هي الافتراضية + `application/json` و`application/problem+json` و`text/json`، ومستوى الضغط `Fastest`.
- في `OnApplicationInitialization`: حطينا `app.UseResponseCompression()` في أول الـ pipeline، قبل `UseRouting` والـ endpoints.
- **المكسب المتوقع:** حجم ردود الـ JSON الكبيرة (المنيو، الأنظمة، الـ grids) يقل غالبًا 70–90%، وده بيفرق جدًا على النت البطيء أو الموبايل، وتكلفة الـ CPU قليلة لأننا مستخدمين `Fastest`.
- **ملاحظة:** EnableForHttps فيه مخاطرة نظرية (BREACH)، بس على ردود فيها أسرار مع مدخلات من اليوزر في نفس الرد. الـ APIs بتاعتنا Bearer token في الـ header، فالمخاطرة ضعيفة.
---

# GetUserSysMenuPermission: فلترة sysCode في الـ DB (13-10-2026)
**الملفات:**
- `ITABSystemMenuRepository.cs`: ضفنا overload جديد `GetUserPermission(Guid userId, int? sysCode)`. الـ overload القديم زي ما هو، يعني إضافة بس.
- `TABSystemMenuRepository.cs`: الـ overload القديم بقى بينادي الجديد بـ `null`. والجديد بيضيف `WHERE sys_code = N` على نتيجة `get_user_pages_permission` لو فيه sysCode.
- `TABSystemMenuAppService.cs`:
  - `BuildUserSysMenuPermissionListAsync` بقت بتبعت `sysCode` للـ repository.
  - `MergeUserRolePermissionsAsync` بقت بتجيب صلاحيات الـ roles بتاعة المنيوهات اللي في النتيجة بس (`itemMenuIds.Contains`).

| | قبل | بعد |
|---|---|---|
| صلاحيات اليوزر | كل الأنظمة بتتجاب وبعدين نفلتر في الذاكرة | الـ DB بيرجّع صفوف النظام المطلوب بس |
| صلاحيات الـ roles | كل صلاحيات رولات اليوزر | صلاحيات المنيوهات اللي هتتعرض بس |

**ليه النتيجة زي ما هي:**
- كانت فيه فلترة بالـ sysCode في الذاكرة على الصفوف دي أصلًا، ولسه موجودة كـ safety net.
- الـ merge مكانش بيلمس إلا المنيوهات الموجودة في القائمة.
- الـ ByFilter من غير sysCode بيبعت `null`، فبيرجّع كل الأنظمة زي الأول.
- `AttachRelatedMenusAsync` بتقرأ صفوف عناصر القائمة بس (الـ RelatedMenus مجرد GUIDs)، ومش بتجيب منيوهات من أنظمة تانية.

**ملاحظة:** الـ SQL function نفسها لسه بتحسب كل الأنظمة جواها. المكسب الحالي إن نقل البيانات وقراءتها وتحويلها وجلب صلاحيات الـ roles بقى أقل. المكسب الأكبر هيبقى لو بعتنا `sys_code` كـ parameter للـ function، بس ده محتاج تعديل في الـ DB، وده مؤجل.
---

# المنيو: منع جلبها في صفحة اختيار الأنظمة (13-10-2026)
**الملفات:** `tabms/services/menu/tab-system-menu.service.ts` و`demo/layout/admin/admin.component.ts`
- **قبل:** constructor الـ service كان بينادي `getMenuData()` أول ما الأبلكيشن يفتح، حتى في صفحة الأنظمة (`/`)، فكان بيجيب منيو آخر syscode متسجل في الـ session من غير لازمة.
- **بعد:**
  - `isOnSystemsHome()` بتتحقق من المسار (`''`، `/systems`، `/default`، `/auth-callback`). لو إحنا في واحد منهم، الـ constructor وتغيير اللغة مش بيجيبوا المنيو.
  - ضفنا `ensureLoaded()`: بتجيب المنيو مرة واحدة بس، ومفيهاش تكرار لأن فيه flag اسمه `menuLoading`، ومش بتعمل حاجة لو المنيو اتحمّلت أو لسه بتتحمّل أو `menuCompleted` اتحدد. بتتنده في `AdminComponent.ngOnInit` (اللي هو الـ layout بتاع كل صفحات الأنظمة).
  - اختيار نظام (`refreshMenuForNewSystem`) والهيكل التنظيمي شغالين زي ما هما.
- **المكسب:** طلب `GetUserSysMenuPermission` واحد أقل في كل مرة صفحة الأنظمة تفتح.
- **المخاطر:** الـ guards اللي بتقرأ `originalMenuData` بشكل synchronous، زي `EngagementChildGuard`، كانت أصلًا بتلاقيها فاضية في الـ deep link لأن الطلب كان لسه شغال، فسلوكها متغيرش.
---

# SignalR: حل مؤقت لمشكلة 414 (14-10-2026)
**الملف:** `tabms/services/global/signalr-manager.service.ts`
- **السبب:** الـ JWT حجمه حوالي 9.4KB، منهم حوالي 5.9KB claims صلاحيات (163 `permission`). الـ token بيتبعت في `?access_token=`، فالـ URL بيعدّي حد الـ 8KB، والطلب بيترفض بـ 414 على Cloud Run وعلى Kestrel لوكال.
- **قبل:** `skipNegotiation: true` و`transport: WebSockets`، يعني WebSocket بس ومفيش أي بديل.
- **بعد:** شيلنا `skipNegotiation`، و`transport = WebSockets | LongPolling`:
  - الـ negotiate بقى POST والـ token في `Authorization` header، فبيعدّي.
  - بعده الكلاينت بيجرب WebSocket. لو اتعمله 414 بيرجع لـ LongPolling، والـ token فيه بيتبعت في الـ header.
  - شيلنا ServerSentEvents عمدًا، لأن EventSource بيحط الـ token في الـ URL هو كمان.
- **الباك:** الـ JwtBearer بيقرأ الـ header عادي. `OnMessageReceived` بيحط الـ token من الـ query بس لو موجود هناك.
- **مخاطر:**
  - الـ Cloud Run services (dev/staging/prod) من غير session affinity، والـ maxScale بتاعهم 5. لو اشتغل أكتر من instance، الـ negotiate والـ polls ممكن يروحوا لـ instances مختلفة، فيطلع "No Connection with that ID" ويحصل reconnect.
  - الـ LongPolling بيعمل network requests أكتر.
- **الحل النهائي:** نشيل الـ permission claims من الـ access token في الـ auth server.
> **تحديث (14-10-2026): رجّعنا التعديل ده.** الملف رجع لنسخته الأصلية: WebSocket بس، و`skipNegotiation: true`. المستخدم رفض الـ LongPolling لأنه بيسيب الطلبات مفتوحة. الحل المعتمد إننا نصغّر الـ access token (نشيل الـ permission claims).

## إزالة صلاحيات الـ permission من الـ Access Token (إصلاح 414 في SignalR)
- تم تعطيل (تعليق) تسجيل `CommunicationPermissionClaimsHandler` و `RealEstatePermissionClaimsHandler` في `AdminstrationAuthServerModule.cs` مع الإبقاء على ملفات الـ handlers كما هي.
- السبب: التوكن كان ~9.4KB (163 claim صلاحية) فتجاوز رابط WebSocket الخاص بـ SignalR حد ~8KB وأعاد 414.
- المتوقع: حجم التوكن ~1.6KB. يلزم إعادة تسجيل الدخول/تجديد التوكن للمستخدمين. للتراجع: إزالة التعليق عن الكتلتين.

## تراجع مؤقت عن nginx في Dockerfile الواجهة (Tab-MS-Front)
- تمت إعادة Dockerfile القديم (http-server) مؤقتاً لأن docker compose على Hetzner ما زال يشغّل الأمر `http-server` (فشل النشر: sh: http-server: not found).
- نسخة nginx محفوظة في %TEMP%\nginxkeep وملف nginx/default.conf باقٍ دون استخدام. يُعاد تفعيل nginx بعد حذف الأمر من compose على Hetzner.
