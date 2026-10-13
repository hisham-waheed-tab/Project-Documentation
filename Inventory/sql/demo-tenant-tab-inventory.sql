-- =====================================================================================
-- Demo data for tenant "Tab" — Inventory DB (Dev only)
-- Idempotent: safe to run more than once.
--
-- Tenant  3a1b1fcd-3ee3-9230-84db-f6f6c448063b  (user Hisham)
-- Branch  3a1ba66a-f2eb-9ce3-12a1-c19e93e7cd42  ("new test", default branch of the POS users)
-- Store   ad1b4c3f-90b9-45ff-9ba3-58e2f6924a25  ("مخزن نقطة البيع")
-- Currency 2 = SAR (Administration "Currency")
--
-- 1) Transaction types: POS sales (SystemUsage 1), POS return (SystemUsage 2), opening balance.
-- 2) Price list RETAIL (SAR) + default list of the branch.
-- 3) Prices for every item except non-EAN codes (left without price to demo the POS block).
-- 4) Barcode = item code for EAN-13 codes (default SKU, main unit).
-- 5) Opening balance in the POS store (0..39 per item; zero for some items to demo the stock warning).
-- =====================================================================================
BEGIN;

CREATE TEMP TABLE demo_ctx ON COMMIT DROP AS
SELECT '3a1b1fcd-3ee3-9230-84db-f6f6c448063b'::uuid AS t,
       '3a1ba66a-f2eb-9ce3-12a1-c19e93e7cd42'::uuid AS b,
       'ad1b4c3f-90b9-45ff-9ba3-58e2f6924a25'::uuid AS s,
       2 AS cur;

-- 1) transaction types
INSERT INTO "TrxtypeConfig" (id, tenantid, branchid, trxkind, trxtypecode, trxaraname, trxlatname, typeabb,
                             inout, operatingtype, systemusage, notactive, isdeleted, creationtime)
SELECT gen_random_uuid(), c.t, NULL, 1, v.code, v.araname, v.latname, v.abb, v.inout, v.optype, v.usage, false, false, now()
FROM demo_ctx c
CROSS JOIN (VALUES (1,  'رصيد افتتاحي',             'Opening Balance',  'OB',   1, 5, NULL::int),
                   (50, 'مبيعات نقطة البيع',         'POS Sales',        'POS',  2, 1, 1),
                   (51, 'مرتجع مبيعات نقطة البيع',   'POS Sales Return', 'POSR', 1, 1, 2))
           AS v(code, araname, latname, abb, inout, optype, usage)
WHERE NOT EXISTS (SELECT 1 FROM "TrxtypeConfig" x
                  WHERE x.tenantid = c.t AND x.trxtypecode = v.code AND x.isdeleted = false);

-- 2) price list + branch default
INSERT INTO "InvPriceLists" (id, tenantid, pricelistcode, pricelistaraname, pricelistlatname, currencycode, isdeleted, creationtime)
SELECT gen_random_uuid(), c.t, 'RETAIL', 'قطاعي', 'Retail', c.cur, false, now()
FROM demo_ctx c
WHERE NOT EXISTS (SELECT 1 FROM "InvPriceLists" x WHERE x.tenantid = c.t AND x.pricelistcode = 'RETAIL' AND x.isdeleted = false);

INSERT INTO "InvBranchPriceLists" (id, tenantid, branchid, pricelistid, isdeleted, creationtime)
SELECT gen_random_uuid(), c.t, c.b, p.id, false, now()
FROM demo_ctx c
JOIN "InvPriceLists" p ON p.tenantid = c.t AND p.pricelistcode = 'RETAIL' AND p.isdeleted = false
WHERE NOT EXISTS (SELECT 1 FROM "InvBranchPriceLists" x WHERE x.tenantid = c.t AND x.branchid = c.b AND x.isdeleted = false);

-- 3) prices (main unit, all SKUs of the item): 25..170 SAR, stable per item code
INSERT INTO "InvItemPrices" (id, tenantid, itemid, variantid, unitid, pricelistid, currencycode, price, fromdate, isdeleted, creationtime)
SELECT gen_random_uuid(), c.t, i.id, NULL, i.mainunitid, p.id, c.cur,
       25 + (abs(hashtext(i.itemcode)) % 30) * 5, date '2026-01-01', false, now()
FROM demo_ctx c
JOIN "InvPriceLists" p ON p.tenantid = c.t AND p.pricelistcode = 'RETAIL' AND p.isdeleted = false
JOIN "InvItems" i ON i.tenantid = c.t AND i.isdeleted = false AND i.mainunitid IS NOT NULL
WHERE i.itemcode ~ '^[0-9]{13}$'
  AND NOT EXISTS (SELECT 1 FROM "InvItemPrices" x
                  WHERE x.itemid = i.id AND x.unitid = i.mainunitid AND x.pricelistid = p.id AND x.isdeleted = false);

-- 4) barcodes
INSERT INTO "InvItemBarcodes" (id, tenantid, itemid, variantid, unitid, barcode, barcodetype, isprimary, isdeleted, creationtime)
SELECT gen_random_uuid(), c.t, i.id, v.id, i.mainunitid, i.itemcode, 'EAN13', true, false, now()
FROM demo_ctx c
JOIN "InvItems" i ON i.tenantid = c.t AND i.isdeleted = false AND i.mainunitid IS NOT NULL
JOIN "InvItemVariants" v ON v.itemid = i.id AND v.isdefault AND v.isdeleted = false
WHERE i.itemcode ~ '^[0-9]{13}$'
  AND NOT EXISTS (SELECT 1 FROM "InvItemBarcodes" x WHERE x.tenantid = c.t AND x.barcode = i.itemcode AND x.isdeleted = false);

-- 5) opening balance (one document, MySource DEMO-OB)
CREATE TEMP TABLE demo_ob ON COMMIT DROP AS
SELECT gen_random_uuid() AS id,
       (SELECT coalesce(max(trxserial), 0) + 1 FROM "TrxInvH") AS serial,
       (SELECT x.id FROM "TrxtypeConfig" x, demo_ctx c
        WHERE x.tenantid = c.t AND x.trxtypecode = 1 AND x.inout = 1 AND x.isdeleted = false LIMIT 1) AS typeid
WHERE NOT EXISTS (SELECT 1 FROM "TrxInvH" h, demo_ctx c WHERE h.tenantid = c.t AND h.mysource = 'DEMO-OB' AND h.isdeleted = false);

INSERT INTO "TrxInvH" (id, tenantid, branchid, trxtypeconfigid, trxyear, trxserial, trxdate, storeid, notes,
                       autogeneration, mysource, isdeleted, creationtime)
SELECT o.id, c.t, c.b, o.typeid, 2026, o.serial, date '2026-01-01', c.s, 'Demo opening balance',
       true, 'DEMO-OB', false, now()
FROM demo_ob o, demo_ctx c;

INSERT INTO "TrxInvF" (id, tenantid, branchid, trxtypeconfigid, trxinvhid, linenum, itemid, variantid, unitid,
                       factor, mainunitisgreater, displayqty, quantity, storeid, isdeleted, creationtime)
SELECT gen_random_uuid(), c.t, c.b, o.typeid, o.id, row_number() OVER (ORDER BY i.itemcode), i.id, v.id, i.mainunitid,
       1, false, q.qty, q.qty, c.s, false, now()
FROM demo_ob o, demo_ctx c
JOIN "InvItems" i ON i.tenantid = c.t AND i.isdeleted = false AND i.mainunitid IS NOT NULL AND coalesce(i.trackinventory, true)
JOIN "InvItemVariants" v ON v.itemid = i.id AND v.isdefault AND v.isdeleted = false
CROSS JOIN LATERAL (SELECT (abs(hashtext(i.itemcode || '#ob')) % 40)::numeric AS qty) q
WHERE q.qty > 0;

COMMIT;

-- ----------------------------------------------------------------------------- check
-- SELECT count(*) FROM "InvItemPrices" p JOIN "InvPriceLists" l ON l.id = p.pricelistid
--  WHERE l.tenantid = '3a1b1fcd-3ee3-9230-84db-f6f6c448063b' AND l.pricelistcode = 'RETAIL';
