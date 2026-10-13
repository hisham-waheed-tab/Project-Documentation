-- =====================================================================================
-- POS → Inventory posting – permissions  (Administration DB)
-- Idempotent: safe to run more than once.
--
-- Why: at shift close the POS API calls Inventory  POST api/v1/InvPosPosting/Post  with the
--   cashier's token. TabEntityAuthorizationFilter requires  Adminstration.Entities.InvPosPosting.Create.
--   (InvPosCatalog/Get is excluded from the filter: any authenticated user can read the sales catalog.)
--   1) Add InvPosPosting to the PosCashier menu "relatedentities" so future permission saves grant it.
--   2) Grant it now to everyone who can close a shift (PosShift.Update).
-- =====================================================================================
BEGIN;

-- 1) related entities
UPDATE "TABSystemMenu"
SET relatedentities = CASE WHEN coalesce(relatedentities, '') = '' THEN 'InvPosPosting'
                           ELSE relatedentities || ',InvPosPosting' END
WHERE menukey = 'PosCashier' AND (',' || coalesce(relatedentities, '') || ',') NOT LIKE '%,InvPosPosting,%';

-- 2) grants  PosShift.Update  ->  InvPosPosting / InvPosPosting.Create
INSERT INTO "AbpPermissionGrants" ("Id", "TenantId", "Name", "ProviderName", "ProviderKey")
SELECT gen_random_uuid(), g."TenantId", p.name, g."ProviderName", g."ProviderKey"
FROM "AbpPermissionGrants" g
CROSS JOIN (VALUES ('Adminstration.Entities.InvPosPosting'),
                   ('Adminstration.Entities.InvPosPosting.Create')) AS p(name)
WHERE g."Name" = 'Adminstration.Entities.PosShift.Update'
  AND NOT EXISTS (
      SELECT 1 FROM "AbpPermissionGrants" x
      WHERE x."Name" = p.name
        AND x."ProviderName" = g."ProviderName"
        AND x."ProviderKey" = g."ProviderKey"
        AND x."TenantId" IS NOT DISTINCT FROM g."TenantId");

COMMIT;
