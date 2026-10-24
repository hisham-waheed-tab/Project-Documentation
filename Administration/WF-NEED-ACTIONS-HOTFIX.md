# إصلاح سريع: طلبات "تحتاج إجراء" بتظهر بعد الموافقة عليها (2026-10-14)

**الملف:** `Administration/src/TABMS.Adminstration.Application/Services/WorkFlow/WFRequestTrxProcessAppService.cs`، الدالة `GetRequestsNeedActions`، السطر 443.

## المشكلة
بعد ما المدير بيوافق على خطوة في الـ workflow، الطلب كان بيفضل ظاهر عنده في شاشة "طلبات تحتاج إجراء". حالة الطلب نفسه 1 (انتظار)، وصف الـ process اللي معاه حالته 2 (تمت الموافقة).

## السبب
- `GetRequestsNeedActions` كانت بتجيب كل صفوف `WFRequestTrxProcess` من غير ما تفلتر على `ActionCode == 1`.
- فأي صف قديم الموافقة عليه خلصت لسه بيطابق المدير (بالـ position أو بالـ `WFEmpId`). والطلب حالته لسه 1 لأنه شغال وراح للخطوة اللي بعدها، فكان بيعدّي فلتر `requestStatusCode`.
- أما دالة العدد `GetRequestsNeedActionsCount` فكانت بتفلتر على `ActionCode == 1`، فالعدد والقائمة مكانوش متطابقين.

## الإصلاح
```csharp
// قبل
var processNeed = await _wfRequestTrxProcessRepository.GetListAsync();
// بعد
var processNeed = (await _wfRequestTrxProcessRepository.GetListAsync()).Where(p => p.ActionCode == 1).ToList();
```
دلوقتي القائمة بتعرض الصفوف اللي لسه مستنية إجراء بس، زي دالة العدد بالظبط. و`wfprocesstrxid` بيشاور على صف الخطوة الحالية.

## ملاحظات
- سطر واحد اتغير، ومفيش تغيير في الـ DB.
- لسه فيه مشكلة أداء: الدالة بتحمّل كل الجداول في الذاكرة. وكمان لسه محتاجين نمنع إن نفس الصف يتعمله Accept مرتين في `AcceptAsync`.
## تحديث (2026-10-14 مساءً)
فلترة صفوف الـ process على `ActionCode == 1` بقت مشروطة:
- لو `requestStatusCode` مش مبعوت (null) أو قيمته 1 (انتظار): بنفلتر على الصفوف اللي لسه مستنية إجراء.
- لو اليوزر اختار حالة تانية من الفلتر (مثلاً 2 موافقة): بنجيب كل صفوف الـ process عشان الطلبات دي تظهر.

```csharp
var processNeed = await _wfRequestTrxProcessRepository.GetListAsync();
if (!requestStatusCode.HasValue || requestStatusCode.Value == 1)
{
    processNeed = processNeed.Where(p => p.ActionCode == 1).ToList();
}
```

**سلوك الباراميتر:** فلتر الحالة على مستوى الطلب (`request.ActionCode == requestStatusCode`) بيتطبق بس لو الباراميتر موجود (`!requestStatusCode.HasValue` → الفلتر بيتساب، يعني كل الحالات).