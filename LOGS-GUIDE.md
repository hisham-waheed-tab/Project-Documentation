# دليل متابعة اللوج (Google Cloud Run)

دليل مختصر لقراءة لوجات السيرفيسات للتحقيق في بطء أو أخطاء. **قراءة فقط، ممنوع أي تعديل.**

## 1. التجهيز
- لازم يكون عندك `gcloud` ومسجل بحساب له صلاحية قراءة على المشروع `tab-solutions-461514`.
```bash
gcloud auth login
gcloud config set project tab-solutions-461514
```

## 2. اعرف اسم السيرفيس
```bash
gcloud run services list
```
| الدومين | السيرفيس |
|---|---|
| host.tab-erp.com | admin-api-service |
| auth.tab-erp.com | admin-auth-service |
| hr-api.tab-erp.com | hr-api-service |
| app.tab-erp.com | admin-front-prod |

- آخر الاسم `-dev` أو `-staging` = البيئة دي، ومن غير لاحقة = production.

## 3. أوامر جاهزة
> الأوقات في اللوج بالـ UTC = توقيت القاهرة **ناقص 3 ساعات**.

**أخطاء آخر 30 دقيقة:**
```bash
gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="admin-api-service-dev" AND httpRequest.status>=400' --freshness=30m --limit=20 --format='value(timestamp,httpRequest.status,httpRequest.requestUrl)'
```

**كل الطلبات في فترة معينة:**
```bash
gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="SERVICE" AND timestamp>="2026-10-13T15:00:00Z" AND timestamp<="2026-10-13T15:10:00Z"' --order=asc --limit=100 --format='value(timestamp,httpRequest.status,httpRequest.latency,httpRequest.remoteIp,httpRequest.requestUrl)'
```

**طلبات endpoint معين (مثلا بطيء):**
```bash
gcloud logging read 'resource.type="cloud_run_revision" AND httpRequest.requestUrl:"GetSystemData"' --freshness=1h --limit=50 --format='value(timestamp,httpRequest.latency,httpRequest.remoteIp)'
```

**مين بيبعت طلبات كتير (IP معين):**
```bash
gcloud logging read 'resource.type="cloud_run_revision" AND httpRequest.remoteIp="1.2.3.4"' --freshness=2h --limit=200 --format='value(timestamp,httpRequest.userAgent,httpRequest.requestUrl)'
```

**إعدادات السيرفيس (CPU / RAM / min instances):**
```bash
gcloud run services describe admin-api-service --region us-central1
```

## 4. نصايح سريعة
- فلتر على `WRN` و`ERR` و`rror` واستبعد سطور `Volo.Abp` و`GCSFuse` عشان تقلل الضوضاء.
- `httpRequest.latency` = وقت السيرفر. لو المتصفح أبطأ بكتير يبقى المشكلة شبكة/preflight مش السيرفر.
- طلبات كتير بنفس الـ IP وUser-Agent `node` = سكريبت أو لوب عند مطوّر. اعرف صاحب الـ IP من: `https://ipinfo.io/IP`.
- أول طلب بعد فترة سكون ممكن يبقى بطيء (cold start) لأن min instances = 0.

## 5. تتبع IP مشبوه (مين ده وشغال على إيه)
1. **هات أكتر IPs بتبعت طلبات** على سيرفيس في آخر ساعة:
```bash
gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="admin-api-service-dev"' --freshness=1h --limit=2000 --format='value(httpRequest.remoteIp)' | sort | uniq -c | sort -rn | head
```
2. **اعرف صاحب الـ IP** (شركة/بلد): افتح `https://ipinfo.io/IP`.
3. **شوف الـ IP ده بيكلم أنهي سيرفيسات** (يكشف هو شغال على أنهي سيستم):
```bash
gcloud logging read 'resource.type="cloud_run_revision" AND httpRequest.remoteIp="IP"' --freshness=1d --limit=5000 --format='value(resource.labels.service_name)' | sort | uniq -c | sort -rn
```
4. **شوف نوع الـ client والصفحات**: `httpRequest.userAgent` (`node` = سكريبت، Chrome/Firefox = متصفح) و`httpRequest.referer` (`localhost` = مطوّر شغال لوكال).