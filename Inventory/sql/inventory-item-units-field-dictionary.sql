-- Dev-TABMS.Administration: field dictionary rows for the item-units additions (idempotent).
INSERT INTO "TABFieldDictionary"
    (id, tenantid, menukey, fieldname, displayaraname, displaylatname, fieldtype, fielddisplayon,
     filter, required, stopduplicate, printable, infofield, tablename, sort, enable, displaylist, creationtime, isdeleted)
SELECT gen_random_uuid(), NULL, v.menukey, v.fieldname, v.displayaraname, v.displaylatname, v.fieldtype, v.fielddisplayon,
       true, false, false, true, false, v.tablename, v.sort, true, B'1', now(), false
FROM (VALUES
    ('InvItems', 'allowsale',             'يسمح بالبيع',          'AllowSale',           'bit',  2, 'InvItemOtherUnits', 4),
    ('InvItems', 'allowpurchase',         'يسمح بالشراء',         'AllowPurchase',       'bit',  2, 'InvItemOtherUnits', 5),
    ('InvItems', 'defaultsalesunitid',    'وحدة البيع الافتراضية',  'DefaultSalesUnitId',  'uuid', 0, 'InvItems',          524),
    ('InvItems', 'defaultpurchaseunitid', 'وحدة الشراء الافتراضية', 'DefaultPurchaseUnitId','uuid', 0, 'InvItems',          525),
    ('InvUnits', 'decimalplaces',         'عدد الخانات العشرية',    'DecimalPlaces',       'int',  0, 'InvUnits',          4)
) AS v(menukey, fieldname, displayaraname, displaylatname, fieldtype, fielddisplayon, tablename, sort)
WHERE NOT EXISTS (
    SELECT 1 FROM "TABFieldDictionary" f
    WHERE f.menukey = v.menukey AND f.fieldname = v.fieldname AND f.fielddisplayon = v.fielddisplayon
      AND f.tenantid IS NULL AND f.isdeleted = false
);
