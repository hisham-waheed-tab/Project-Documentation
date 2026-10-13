-- =====================================================================================
-- Item Management Center – permissions & menu  (Administration DB)
-- Idempotent: safe to run more than once.
--
-- Why: TabEntityAuthorizationFilter maps every API controller to an entity permission
--   GET -> Adminstration.Entities.<Entity>, POST -> .Create, PUT -> .Update, DELETE -> .Delete
-- The new screen calls two new controllers: InvItemCenter, InvItemBarcodes.
--   1) Add them to the InvItems menu "relatedentities" so future permission saves (Admin
--      TabUserPermissionAbpSyncService) grant them automatically.
--   2) Copy current InvItems grants to the new entity names so existing users keep access.
--   3) Point the "Items" menu to the new center page (old page stays reachable at inventory/items).
-- =====================================================================================
BEGIN;

-- 1) related entities
UPDATE "TABSystemMenu"
SET relatedentities = CASE WHEN coalesce(relatedentities, '') = '' THEN 'InvItemCenter'
                           ELSE relatedentities || ',InvItemCenter' END
WHERE menukey = 'InvItems' AND (',' || coalesce(relatedentities, '') || ',') NOT LIKE '%,InvItemCenter,%';

UPDATE "TABSystemMenu"
SET relatedentities = CASE WHEN coalesce(relatedentities, '') = '' THEN 'InvItemBarcodes'
                           ELSE relatedentities || ',InvItemBarcodes' END
WHERE menukey = 'InvItems' AND (',' || coalesce(relatedentities, '') || ',') NOT LIKE '%,InvItemBarcodes,%';

-- 2) copy grants  InvItems[.X]  ->  InvItemCenter[.X] / InvItemBarcodes[.X]
INSERT INTO "AbpPermissionGrants" ("Id", "TenantId", "Name", "ProviderName", "ProviderKey")
SELECT gen_random_uuid(), g."TenantId",
       replace(g."Name", 'Adminstration.Entities.InvItems', 'Adminstration.Entities.' || e.entity),
       g."ProviderName", g."ProviderKey"
FROM "AbpPermissionGrants" g
CROSS JOIN (VALUES ('InvItemCenter'), ('InvItemBarcodes')) AS e(entity)
WHERE g."Name" IN ('Adminstration.Entities.InvItems',
                   'Adminstration.Entities.InvItems.Create',
                   'Adminstration.Entities.InvItems.Update',
                   'Adminstration.Entities.InvItems.Delete')
  AND NOT EXISTS (
      SELECT 1 FROM "AbpPermissionGrants" x
      WHERE x."Name" = replace(g."Name", 'Adminstration.Entities.InvItems', 'Adminstration.Entities.' || e.entity)
        AND x."ProviderName" = g."ProviderName"
        AND x."ProviderKey" = g."ProviderKey"
        AND x."TenantId" IS NOT DISTINCT FROM g."TenantId");

-- 3) menu -> new center
UPDATE "TABSystemMenu" SET pageurl = 'inventory/items-center'
WHERE menukey = 'InvItems' AND pageurl = 'inventory/items';

COMMIT;

-- ----------------------------------------------------------------------------- rollback
-- UPDATE "TABSystemMenu" SET pageurl = 'inventory/items' WHERE menukey = 'InvItems' AND pageurl = 'inventory/items-center';
-- (grants / related entities can stay; they are harmless if the screen is not used)
