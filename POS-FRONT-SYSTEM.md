# نظام POS في Tab-MS-Front (أساسي)

## الشاشات

### إعدادات (simple form — قابلة للتعديل)
| Route | Resource | المجلد |
|---|---|---|
| `/pos-system/pos-terminal/:id` | `PosTerminal` | `pages/pos-system/setup/pos-terminal` |
| `/pos-system/pos-payment-method/:id` | `PosPaymentMethod` | `pages/pos-system/setup/pos-payment-method` |
| `/pos-system/pos-policy-value/:id` | `PosPolicyValue` | `pages/pos-system/setup/pos-policy-value` |

### تقارير (قراءة فقط)
| Route | نوع | Resource |
|---|---|---|
| `/pos-system/pos-sale/:id` | header + footer | `PosSaleH` / `PosSaleF` (`headerKey=saleid`) |
| `/pos-system/pos-return/:id` | header + footer | `PosReturnH` / `PosReturnF` (`headerKey=returnid`) |
| `/pos-system/pos-shift/:id` | simple form readonly | `PosShift` |

## API

- Local: `environment.baseUrlPOS` = `https://localhost:44349/api/v1/`
- Scope: أُضيف `POS` إلى `environment.scope`
- `GridList` مضاف مؤقتًا عبر `PosSimpleGridListHelper` (بدون Field Dictionary) حتى تسجيل الشاشات في القائمة

## تسجيل القائمة + Field Dictionary (محلي)

تم على قاعدة `Dev-TABMS.Administration` (localhost) بـ `syscode = 70`:

| MenuId | MenuKey | PageUrl | CRUD |
|---|---|---|---|
| `a5700000-…0001` | PosSetupFolder | (مجلد) | — |
| `a5700000-…0010` | PosTerminal | pos-system/pos-terminal | نعم |
| `a5700000-…0011` | PosPaymentMethod | pos-system/pos-payment-method | نعم |
| `a5700000-…0012` | PosPolicyValue | pos-system/pos-policy-value | نعم |
| `a5700000-…0002` | PosReportsFolder | (مجلد) | — |
| `a5700000-…0020` | PosSaleH | pos-system/pos-sale | قراءة فقط (+ PosSaleF فوتر) |
| `a5700000-…0021` | PosReturnH | pos-system/pos-return | قراءة فقط (+ PosReturnF فوتر) |
| `a5700000-…0022` | PosShift | pos-system/pos-shift | قراءة فقط |

Field Dictionary مُعبَّأ من أعمدة جداول POS. السكربتات: `tmp/pos-menus.sql`, `tmp/pos-field-dict.sql`.

> إن كان Front على **cloud** (`dev-host`) وليس Admin المحلي، يجب تكرار التسجيل على بيئة السحابة أو مزامنة القاعدة.

صلاحيات المستخدم (`TABUserPermission`) خطوة منفصلة — لم تُضف تلقائيًا.

## اختبار

`http://localhost:4200/pos-system/pos-terminal/{menuId}`
أو من القائمة بعد منح صلاحية Access على الشاشات.
