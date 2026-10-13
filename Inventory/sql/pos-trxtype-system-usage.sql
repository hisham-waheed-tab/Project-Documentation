-- =====================================================================================
-- POS transaction types  (Inventory DB)
-- Idempotent: safe to run more than once.
--
-- Creates, for every tenant that has none yet, two branch-less transaction types used by
-- InvPosPosting at POS shift close:
--   SystemUsage 1 = POS sales issue  (TrxKind 1 transaction, OperatingType 1 sales, InOut 2 out)
--   SystemUsage 2 = POS sales return (TrxKind 1 transaction, OperatingType 1 sales, InOut 1 in)
-- A branch can get its own type later from the transaction types screen (same SystemUsage + BranchId).
-- Codes 50 / 51: change them if they are already used by the tenant.
-- =====================================================================================
BEGIN;

INSERT INTO "TrxtypeConfig" (id, tenantid, branchid, trxkind, trxtypecode, trxaraname, trxlatname, typeabb,
                             inout, operatingtype, systemusage, notactive, isdeleted, creationtime)
SELECT gen_random_uuid(), t.tenantid, NULL, 1, u.code, u.araname, u.latname, u.abb,
       u.inout, 1, u.usage, false, false, now()
FROM (SELECT DISTINCT tenantid FROM "TrxtypeConfig") t
CROSS JOIN (VALUES (1, 50, 'مبيعات نقطة البيع', 'POS Sales', 'POS', 2),
                   (2, 51, 'مرتجع مبيعات نقطة البيع', 'POS Sales Return', 'POSR', 1))
           AS u(usage, code, araname, latname, abb, inout)
WHERE NOT EXISTS (
    SELECT 1 FROM "TrxtypeConfig" x
    WHERE x.tenantid IS NOT DISTINCT FROM t.tenantid
      AND x.branchid IS NULL
      AND x.systemusage = u.usage
      AND x.isdeleted = false);

COMMIT;
