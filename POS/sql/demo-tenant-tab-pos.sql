-- =====================================================================================
-- Demo data for tenant "Tab" — POS DB (Dev only). Idempotent.
--
-- Terminal POS-01 gets the POS store (balances shown + inventory posting at shift close).
-- Price list left empty → the branch default list (RETAIL) is used.
-- =====================================================================================
BEGIN;

UPDATE "PosTerminal"
SET defaultstoreid = 'ad1b4c3f-90b9-45ff-9ba3-58e2f6924a25', lastmodificationtime = now()
WHERE tenantid = '3a1b1fcd-3ee3-9230-84db-f6f6c448063b'
  AND id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2'
  AND defaultstoreid IS DISTINCT FROM 'ad1b4c3f-90b9-45ff-9ba3-58e2f6924a25';

COMMIT;
