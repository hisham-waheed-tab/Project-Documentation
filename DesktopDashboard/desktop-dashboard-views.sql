-- Desktop Dashboard: web_ views for a TAB desktop (SQL Server) customer database.
-- Run on the customer database. Safe to re-run (CREATE OR ALTER). Needs SQL Server 2016 SP1 or later.
-- Base views first (documents, cash vouchers, GL lines, account tree, AR aging), then the chart views.

CREATE OR ALTER VIEW dbo.web_TrxDocs AS
SELECT h.BranchCode, h.Trxtype, h.TrxYear, h.TrxSerial, h.TrxDate, h.TargetType, h.TargetCode,
       ISNULL(h.NetPrice, 0) AS NetPrice, ISNULL(h.TotalTax, 0) AS TotalTax,
       c.TrxArbName AS TrxTypeName,
       CASE WHEN c.TrxType = 1 AND c.TrxTypeID = 2 THEN 'S'   -- sales / revenue invoice
            WHEN c.TrxType = 1 AND c.TrxTypeID = 1 THEN 'SR'  -- sales return
            WHEN c.TrxType = 2 AND c.TrxTypeID = 1 THEN 'P'   -- purchase / service invoice
            WHEN c.TrxType = 2 AND c.TrxTypeID = 2 THEN 'PR'  -- purchase return
       END AS DocKind
FROM dbo.TrxInvH h
JOIN dbo.trxtypeConfig c ON c.BranchCode = h.BranchCode AND c.trxtypecode = h.Trxtype
WHERE ISNULL(h.Canceled, 0) = 0 AND c.TrxType IN (1, 2)
GO

-- Cash/bank vouchers only (kind 1); nature 1 = receipt, 2 = payment, per the desktop TypeTrxSafe setup.
CREATE OR ALTER VIEW dbo.web_CashDocs AS
SELECT h.BranchCode, h.TypeTrxSafeCode, h.Year, h.Serial, h.TrxDate,
       LTRIM(RTRIM(h.AccCode)) AS CashAccCode,
       t.SafeTrxTypeAraName AS TypeName,
       CASE t.KindNature WHEN 1 THEN 'R' WHEN 2 THEN 'P' END AS DocKind,
       CASE t.KindNature WHEN 1 THEN ISNULL(h.TotalCredit, 0) ELSE ISNULL(h.TotalDebit, 0) END AS Amount
FROM dbo.TrxHeaderSafe h
JOIN dbo.TypeTrxSafe t ON t.BranchCode = h.BranchCode AND t.SafeTrxTypeCode = h.TypeTrxSafeCode
WHERE t.SafeTrxKindCode = 1 AND t.KindNature IN (1, 2)
GO

-- Document-level web_ views: every row carries TrxDate + BranchCode so the dashboard date/branch filter applies.
-- Charts aggregate by their category (SUM by default), so the totals match the former pre-grouped views.
-- Top-N/ranked views keep their ranking over the whole history (SortNo); the filter narrows the amounts.

CREATE OR ALTER VIEW dbo.web_GLMovements AS
SELECT h.GLTrxDate AS TrxDate, LTRIM(RTRIM(f.AccountCode)) AS AccCode,
       ISNULL(f.Debit, 0) AS Debit, ISNULL(f.Credit, 0) AS Credit, h.BranchCode
FROM dbo.GLTrxFooter f
JOIN dbo.GLTrxHeader h ON h.BranchCode = f.BranchCode AND h.TrxYear = f.TrxYear AND h.TrxType = f.TrxType
  AND h.TrxJorCode = f.TrxJorCode AND h.TrxPeriod = f.TrxPeriod AND h.TrxSerial = f.TrxSerial
WHERE ISNULL(h.closingRec, 0) = 0 AND ISNULL(h.OpeningRec, 0) = 0
GO

-- Each account with its level-1 and level-3 ancestors, walked through ParentCode so it does not depend on code patterns.
CREATE OR ALTER VIEW dbo.web_GLAccountTree AS
WITH acc AS (
    SELECT LTRIM(RTRIM(AccCode)) AS AccCode, AccAraName, CAST(ParentCode AS varchar(30)) AS ParentCode, LevelCode FROM dbo.Accounts
),
walk AS (
    SELECT a.AccCode AS LeafCode, a.AccCode, a.ParentCode, a.LevelCode, a.AccAraName FROM acc a
    UNION ALL
    SELECT w.LeafCode, p.AccCode, p.ParentCode, p.LevelCode, p.AccAraName
    FROM walk w JOIN acc p ON p.AccCode = w.ParentCode
    WHERE w.LevelCode > 1
)
SELECT l.AccCode, l.AccAraName, l.LevelCode,
       MAX(CASE WHEN w.LevelCode = 1 THEN w.AccCode END) AS L1Code,
       MAX(CASE WHEN w.LevelCode = 1 THEN w.AccAraName END) AS L1Name,
       MAX(CASE WHEN w.LevelCode = 3 THEN w.AccCode END) AS L3Code,
       MAX(CASE WHEN w.LevelCode = 3 THEN w.AccAraName END) AS L3Name
FROM acc l JOIN walk w ON w.LeafCode = l.AccCode
GROUP BY l.AccCode, l.AccAraName, l.LevelCode
GO

-- Customer_Aging leaves most receipts unallocated, so receipts and credit notes are applied FIFO to the oldest invoices here.
CREATE OR ALTER VIEW dbo.web_ARInvoiceAging AS
WITH inv AS (
    SELECT ID, CustomerCode, InvDate, InvValue,
           SUM(InvValue) OVER (PARTITION BY CustomerCode ORDER BY InvDate, ID ROWS UNBOUNDED PRECEDING) AS Cum
    FROM dbo.Customer_Aging
    WHERE AgingType = 1 AND Type = 1 AND InvValue > 0 AND InvDate >= '2000-01-01'
),
paid AS (
    SELECT CustomerCode,
           SUM(CASE WHEN Type = 2 THEN ISNULL(MoneyValue, 0) WHEN Type = 1 AND InvValue < 0 THEN -InvValue ELSE 0 END) AS Paid
    FROM dbo.Customer_Aging WHERE AgingType = 1
    GROUP BY CustomerCode
),
asof AS (SELECT MAX(InvDate) AS AsOf FROM inv)
SELECT i.CustomerCode, i.InvDate, i.InvValue,
       CASE WHEN i.Cum <= ISNULL(p.Paid, 0) THEN 0
            WHEN i.Cum - i.InvValue >= ISNULL(p.Paid, 0) THEN i.InvValue
            ELSE i.Cum - ISNULL(p.Paid, 0) END AS Remaining,
       DATEDIFF(day, i.InvDate, a.AsOf) AS AgeDays
FROM inv i CROSS JOIN asof a LEFT JOIN paid p ON p.CustomerCode = i.CustomerCode
GO

CREATE OR ALTER VIEW dbo.web_ARAgingBuckets AS
WITH b AS (
    SELECT CASE WHEN AgeDays <= 30 THEN 1 WHEN AgeDays <= 60 THEN 2 WHEN AgeDays <= 90 THEN 3
                WHEN AgeDays <= 180 THEN 4 WHEN AgeDays <= 365 THEN 5 ELSE 6 END AS SortNo,
           Remaining
    FROM dbo.web_ARInvoiceAging WHERE Remaining > 0
)
SELECT SortNo,
       CASE SortNo WHEN 1 THEN N'حتى 30 يوم' WHEN 2 THEN N'31 - 60 يوم' WHEN 3 THEN N'61 - 90 يوم'
                   WHEN 4 THEN N'91 - 180 يوم' WHEN 5 THEN N'181 - 365 يوم' ELSE N'أكثر من سنة' END AS BucketName,
       CAST(SUM(Remaining) AS decimal(18, 2)) AS Outstanding,
       COUNT(*) AS InvoiceCount
FROM b GROUP BY SortNo
GO

CREATE OR ALTER VIEW dbo.web_ARBilledVsCollected AS
SELECT YEAR(TrxDate) * 100 + MONTH(TrxDate) AS SortNo, CONVERT(char(7), TrxDate, 126) AS MonthName, TrxDate, BranchCode,
       CAST(NetPrice AS decimal(18, 2)) AS Billed, CAST(0 AS decimal(18, 2)) AS Collected
FROM dbo.web_TrxDocs WHERE DocKind = 'S'
UNION ALL
SELECT YEAR(TrxDate) * 100 + MONTH(TrxDate), CONVERT(char(7), TrxDate, 126), TrxDate, BranchCode,
       CAST(0 AS decimal(18, 2)), CAST(Amount AS decimal(18, 2))
FROM dbo.web_CashDocs WHERE DocKind = 'R'
GO

CREATE OR ALTER VIEW dbo.web_ARSummary AS
SELECT 1 AS SortNo, N'غير مستحق بعد (حتى 90 يوم)' AS Measure, CAST(SUM(CASE WHEN AgeDays <= 90 THEN Remaining ELSE 0 END) AS decimal(18, 2)) AS Amount
FROM dbo.web_ARInvoiceAging
UNION ALL
SELECT 2, N'متأخر أكثر من 90 يوم', CAST(SUM(CASE WHEN AgeDays > 90 THEN Remaining ELSE 0 END) AS decimal(18, 2))
FROM dbo.web_ARInvoiceAging
GO

CREATE OR ALTER VIEW dbo.web_ARTopDebtors AS
WITH c AS (
    SELECT CustomerCode, SUM(Remaining) AS Outstanding,
           SUM(CASE WHEN AgeDays > 90 THEN Remaining ELSE 0 END) AS Overdue90
    FROM dbo.web_ARInvoiceAging WHERE Remaining > 0
    GROUP BY CustomerCode
),
r AS (SELECT TOP (10) ROW_NUMBER() OVER (ORDER BY Outstanding DESC) AS SortNo, * FROM c ORDER BY Outstanding DESC)
SELECT r.SortNo, ISNULL(cu.CustName, CAST(r.CustomerCode AS nvarchar(20))) AS CustomerName,
       CAST(r.Outstanding - r.Overdue90 AS decimal(18, 2)) AS Current90,
       CAST(r.Overdue90 AS decimal(18, 2)) AS Overdue90,
       CAST(r.Outstanding AS decimal(18, 2)) AS Outstanding
FROM r LEFT JOIN dbo.Customers cu ON cu.CustCode = r.CustomerCode
GO

CREATE OR ALTER VIEW dbo.web_CashByAccount AS
WITH d AS (
    SELECT CashAccCode, TrxDate, BranchCode,
           CASE WHEN DocKind = 'R' THEN Amount ELSE 0 END AS Receipts,
           CASE WHEN DocKind = 'P' THEN Amount ELSE 0 END AS Payments
    FROM dbo.web_CashDocs
),
rk AS (SELECT CashAccCode, ROW_NUMBER() OVER (ORDER BY SUM(Receipts + Payments) DESC) AS SortNo FROM d GROUP BY CashAccCode)
SELECT rk.SortNo, ISNULL(ac.AccAraName, d.CashAccCode) AS AccountName, d.TrxDate, d.BranchCode,
       CAST(d.Receipts AS decimal(18, 2)) AS Receipts, CAST(d.Payments AS decimal(18, 2)) AS Payments
FROM d JOIN rk ON rk.CashAccCode = d.CashAccCode LEFT JOIN dbo.Accounts ac ON LTRIM(RTRIM(ac.AccCode)) = d.CashAccCode
GO

CREATE OR ALTER VIEW dbo.web_CashKpi AS
WITH last_ AS (SELECT MAX(TrxDate) AS MaxDate FROM dbo.web_CashDocs),
p AS (
    SELECT d.DocKind, d.Amount, CASE WHEN d.TrxDate > DATEADD(month, -12, l.MaxDate) THEN 1 ELSE 0 END AS IsCurrent
    FROM dbo.web_CashDocs d CROSS JOIN last_ l WHERE d.TrxDate > DATEADD(month, -24, l.MaxDate)
)
SELECT 1 AS SortNo, N'المقبوضات' AS Measure,
       CAST(SUM(CASE WHEN DocKind = 'R' AND IsCurrent = 1 THEN Amount ELSE 0 END) AS decimal(18, 2)) AS CurrentPeriod,
       CAST(SUM(CASE WHEN DocKind = 'R' AND IsCurrent = 0 THEN Amount ELSE 0 END) AS decimal(18, 2)) AS PreviousPeriod
FROM p
UNION ALL
SELECT 2, N'المدفوعات',
       CAST(SUM(CASE WHEN DocKind = 'P' AND IsCurrent = 1 THEN Amount ELSE 0 END) AS decimal(18, 2)),
       CAST(SUM(CASE WHEN DocKind = 'P' AND IsCurrent = 0 THEN Amount ELSE 0 END) AS decimal(18, 2))
FROM p
GO

CREATE OR ALTER VIEW dbo.web_CashMonthly AS
SELECT YEAR(d.TrxDate) * 100 + MONTH(d.TrxDate) AS SortNo, CONVERT(char(7), d.TrxDate, 126) AS MonthName,
       d.TrxDate, d.BranchCode,
       CAST(CASE WHEN d.DocKind = 'R' THEN d.Amount ELSE 0 END AS decimal(18, 2)) AS Receipts,
       CAST(CASE WHEN d.DocKind = 'P' THEN d.Amount ELSE 0 END AS decimal(18, 2)) AS Payments,
       CAST(CASE WHEN d.DocKind = 'R' THEN d.Amount ELSE -d.Amount END AS decimal(18, 2)) AS NetCash
FROM dbo.web_CashDocs d
GO

-- Where the money goes: debit lines of payment vouchers, by account, top 10.
CREATE OR ALTER VIEW dbo.web_CashTopPaymentAccounts AS
WITH l AS (
    SELECT LTRIM(RTRIM(ft.AccCode)) AS AccCode, d.TrxDate, d.BranchCode, ISNULL(ft.Debit, 0) - ISNULL(ft.Credit, 0) AS Paid
    FROM dbo.TrxFooterSafe ft
    JOIN dbo.web_CashDocs d ON d.BranchCode = ft.BranchCode AND d.TypeTrxSafeCode = ft.TypeTrxSafeCode AND d.Year = ft.Year AND d.Serial = ft.Serial
    WHERE d.DocKind = 'P'
),
rk AS (SELECT TOP (10) AccCode, ROW_NUMBER() OVER (ORDER BY SUM(Paid) DESC) AS SortNo FROM l GROUP BY AccCode ORDER BY SUM(Paid) DESC)
SELECT rk.SortNo, ISNULL(ac.AccAraName, l.AccCode) AS AccountName, l.TrxDate, l.BranchCode, l.Paid
FROM l JOIN rk ON rk.AccCode = l.AccCode LEFT JOIN dbo.Accounts ac ON LTRIM(RTRIM(ac.AccCode)) = l.AccCode
GO

CREATE OR ALTER VIEW dbo.web_CashYearly AS
SELECT YEAR(TrxDate) AS SortNo, CAST(YEAR(TrxDate) AS varchar(4)) AS YearName, TrxDate, BranchCode,
       CAST(CASE WHEN DocKind = 'R' THEN Amount ELSE 0 END AS decimal(18, 2)) AS Receipts,
       CAST(CASE WHEN DocKind = 'P' THEN Amount ELSE 0 END AS decimal(18, 2)) AS Payments,
       CAST(CASE WHEN DocKind = 'R' THEN Amount ELSE -Amount END AS decimal(18, 2)) AS NetCash
FROM dbo.web_CashDocs
GO

CREATE OR ALTER VIEW dbo.web_GLExpensesByGroup AS
WITH l AS (
    SELECT LTRIM(RTRIM(ISNULL(t.L3Name, t.AccAraName))) AS GroupName, m.TrxDate, m.BranchCode, m.Debit - m.Credit AS Amount
    FROM dbo.web_GLMovements m JOIN dbo.web_GLAccountTree t ON t.AccCode = m.AccCode
    WHERE LEFT(t.L1Code, 1) = '5'
),
rk AS (SELECT GroupName, ROW_NUMBER() OVER (ORDER BY SUM(Amount) DESC) AS SortNo FROM l GROUP BY GroupName HAVING SUM(Amount) > 0)
SELECT rk.SortNo, l.GroupName, l.TrxDate, l.BranchCode, l.Amount
FROM l JOIN rk ON rk.GroupName = l.GroupName
GO

CREATE OR ALTER VIEW dbo.web_GLIncomeYearly AS
WITH l AS (
    SELECT g.TrxDate, g.BranchCode,
           CASE WHEN LEFT(t.L1Code, 1) = '4' THEN g.Credit - g.Debit ELSE 0 END AS Revenue,
           CASE WHEN LEFT(t.L1Code, 1) = '5' THEN g.Debit - g.Credit ELSE 0 END AS Expenses
    FROM dbo.web_GLMovements g JOIN dbo.web_GLAccountTree t ON t.AccCode = g.AccCode
    WHERE LEFT(t.L1Code, 1) IN ('4', '5')
)
SELECT YEAR(TrxDate) AS SortNo, CAST(YEAR(TrxDate) AS varchar(4)) AS YearName, TrxDate, BranchCode,
       Revenue, Expenses, Revenue - Expenses AS NetProfit
FROM l
GO

CREATE OR ALTER VIEW dbo.web_GLMonthlyRevExp AS
SELECT YEAR(g.TrxDate) * 100 + MONTH(g.TrxDate) AS SortNo, CONVERT(char(7), g.TrxDate, 126) AS MonthName,
       g.TrxDate, g.BranchCode,
       CASE WHEN LEFT(t.L1Code, 1) = '4' THEN g.Credit - g.Debit ELSE 0 END AS Revenue,
       CASE WHEN LEFT(t.L1Code, 1) = '5' THEN g.Debit - g.Credit ELSE 0 END AS Expenses
FROM dbo.web_GLMovements g JOIN dbo.web_GLAccountTree t ON t.AccCode = g.AccCode
WHERE LEFT(t.L1Code, 1) IN ('4', '5')
GO

CREATE OR ALTER VIEW dbo.web_GLTopExpenseAccounts AS
WITH l AS (
    SELECT t.AccCode, LTRIM(RTRIM(t.AccAraName)) AS AccountName, m.TrxDate, m.BranchCode, m.Debit - m.Credit AS Amount
    FROM dbo.web_GLMovements m JOIN dbo.web_GLAccountTree t ON t.AccCode = m.AccCode
    WHERE LEFT(t.L1Code, 1) = '5'
),
rk AS (SELECT TOP (10) AccCode, ROW_NUMBER() OVER (ORDER BY SUM(Amount) DESC) AS SortNo FROM l GROUP BY AccCode ORDER BY SUM(Amount) DESC)
SELECT rk.SortNo, l.AccountName, l.TrxDate, l.BranchCode, l.Amount
FROM l JOIN rk ON rk.AccCode = l.AccCode
GO

CREATE OR ALTER VIEW dbo.web_PurchasesByItemGroup AS
WITH l AS (
    SELECT ISNULL(ig.ItemGroupAraName, N'غير مصنف') AS GroupName, d.TrxDate, d.BranchCode,
           ISNULL(f.Quantity, 0) * ISNULL(f.Price, 0) AS PurchaseValue
    FROM dbo.TrxInvF f
    JOIN dbo.web_TrxDocs d ON d.BranchCode = f.BranchCode AND d.Trxtype = f.Trxtype AND d.TrxYear = f.TrxYear AND d.TrxSerial = f.TrxSerial
    LEFT JOIN dbo.Items i ON i.ItemCode = f.ItemCode
    LEFT JOIN dbo.ItemGroups ig ON ig.ItemGroupCode = i.ItemGroupCode
    WHERE d.DocKind = 'P'
),
rk AS (SELECT GroupName, ROW_NUMBER() OVER (ORDER BY SUM(PurchaseValue) DESC) AS Rn FROM l GROUP BY GroupName)
SELECT CASE WHEN rk.Rn <= 8 THEN rk.Rn ELSE 9 END AS SortNo,
       CASE WHEN rk.Rn <= 8 THEN l.GroupName ELSE N'أخرى' END AS GroupName,
       l.TrxDate, l.BranchCode, l.PurchaseValue
FROM l JOIN rk ON rk.GroupName = l.GroupName
GO

CREATE OR ALTER VIEW dbo.web_PurchasesMonthly AS
SELECT YEAR(d.TrxDate) * 100 + MONTH(d.TrxDate) AS SortNo, CONVERT(char(7), d.TrxDate, 126) AS MonthName,
       d.TrxDate, d.BranchCode,
       CAST(CASE WHEN d.DocKind = 'P' THEN d.NetPrice ELSE 0 END AS decimal(18, 2)) AS Purchases,
       CAST(CASE WHEN d.DocKind = 'PR' THEN d.NetPrice ELSE 0 END AS decimal(18, 2)) AS PurchaseReturns,
       CASE WHEN d.DocKind = 'P' THEN 1 ELSE 0 END AS InvoiceCount
FROM dbo.web_TrxDocs d
WHERE d.DocKind IN ('P', 'PR')
GO

CREATE OR ALTER VIEW dbo.web_SalesByType AS
WITH d AS (SELECT LTRIM(RTRIM(TrxTypeName)) AS TypeName, TrxDate, BranchCode, NetPrice FROM dbo.web_TrxDocs WHERE DocKind = 'S'),
rk AS (SELECT TypeName, ROW_NUMBER() OVER (ORDER BY SUM(NetPrice) DESC) AS SortNo FROM d GROUP BY TypeName)
SELECT rk.SortNo, d.TypeName, d.TrxDate, d.BranchCode, CAST(d.NetPrice AS decimal(18, 2)) AS NetSales
FROM d JOIN rk ON rk.TypeName = d.TypeName
GO

-- Latest 12 months vs the 12 before them, one row per measure for a compact comparison chart.
CREATE OR ALTER VIEW dbo.web_SalesKpi AS
WITH last_ AS (SELECT MAX(TrxDate) AS MaxDate FROM dbo.web_TrxDocs),
p AS (
    SELECT d.DocKind,
           CASE WHEN d.TrxDate > DATEADD(month, -12, l.MaxDate) THEN 1 ELSE 0 END AS IsCurrent,
           d.NetPrice
    FROM dbo.web_TrxDocs d CROSS JOIN last_ l
    WHERE d.TrxDate > DATEADD(month, -24, l.MaxDate)
)
SELECT 1 AS SortNo, N'صافي المبيعات' AS Measure,
       CAST(SUM(CASE WHEN IsCurrent = 1 THEN CASE DocKind WHEN 'S' THEN NetPrice WHEN 'SR' THEN -NetPrice ELSE 0 END ELSE 0 END) AS decimal(18, 2)) AS CurrentPeriod,
       CAST(SUM(CASE WHEN IsCurrent = 0 THEN CASE DocKind WHEN 'S' THEN NetPrice WHEN 'SR' THEN -NetPrice ELSE 0 END ELSE 0 END) AS decimal(18, 2)) AS PreviousPeriod
FROM p
UNION ALL
SELECT 2, N'صافي المشتريات',
       CAST(SUM(CASE WHEN IsCurrent = 1 THEN CASE DocKind WHEN 'P' THEN NetPrice WHEN 'PR' THEN -NetPrice ELSE 0 END ELSE 0 END) AS decimal(18, 2)),
       CAST(SUM(CASE WHEN IsCurrent = 0 THEN CASE DocKind WHEN 'P' THEN NetPrice WHEN 'PR' THEN -NetPrice ELSE 0 END ELSE 0 END) AS decimal(18, 2))
FROM p
GO

CREATE OR ALTER VIEW dbo.web_SalesMonthly AS
SELECT YEAR(d.TrxDate) * 100 + MONTH(d.TrxDate) AS SortNo, CONVERT(char(7), d.TrxDate, 126) AS MonthName,
       d.TrxDate, d.BranchCode,
       CAST(CASE WHEN d.DocKind = 'S' THEN d.NetPrice ELSE 0 END AS decimal(18, 2)) AS Sales,
       CAST(CASE WHEN d.DocKind = 'SR' THEN d.NetPrice ELSE 0 END AS decimal(18, 2)) AS Returns,
       CAST(CASE WHEN d.DocKind = 'S' THEN d.NetPrice ELSE -d.NetPrice END AS decimal(18, 2)) AS NetSales,
       CASE WHEN d.DocKind = 'S' THEN 1 ELSE 0 END AS InvoiceCount
FROM dbo.web_TrxDocs d
WHERE d.DocKind IN ('S', 'SR')
GO

CREATE OR ALTER VIEW dbo.web_SalesPurchasesYearly AS
WITH l AS (
    SELECT TrxDate, BranchCode,
           CASE DocKind WHEN 'S' THEN NetPrice WHEN 'SR' THEN -NetPrice ELSE 0 END AS NetSales,
           CASE DocKind WHEN 'P' THEN NetPrice WHEN 'PR' THEN -NetPrice ELSE 0 END AS NetPurchases
    FROM dbo.web_TrxDocs
)
SELECT YEAR(TrxDate) AS SortNo, CAST(YEAR(TrxDate) AS varchar(4)) AS YearName, TrxDate, BranchCode,
       CAST(NetSales AS decimal(18, 2)) AS NetSales, CAST(NetPurchases AS decimal(18, 2)) AS NetPurchases,
       CAST(NetSales - NetPurchases AS decimal(18, 2)) AS GrossMargin
FROM l
GO

CREATE OR ALTER VIEW dbo.web_TopCustomers AS
WITH d AS (
    SELECT TargetCode, TrxDate, BranchCode,
           CASE DocKind WHEN 'S' THEN NetPrice ELSE -NetPrice END AS NetSales,
           CASE WHEN DocKind = 'S' THEN 1 ELSE 0 END AS InvoiceCount
    FROM dbo.web_TrxDocs WHERE DocKind IN ('S', 'SR') AND TargetType = 1
),
rk AS (SELECT TOP (10) TargetCode, ROW_NUMBER() OVER (ORDER BY SUM(NetSales) DESC) AS SortNo FROM d GROUP BY TargetCode ORDER BY SUM(NetSales) DESC)
SELECT rk.SortNo, ISNULL(cu.CustName, CAST(d.TargetCode AS nvarchar(20))) AS CustomerName, d.TrxDate, d.BranchCode,
       CAST(d.NetSales AS decimal(18, 2)) AS NetSales, d.InvoiceCount
FROM d JOIN rk ON rk.TargetCode = d.TargetCode LEFT JOIN dbo.Customers cu ON cu.CustCode = d.TargetCode
GO

CREATE OR ALTER VIEW dbo.web_TopSuppliers AS
WITH d AS (
    SELECT TargetCode, TrxDate, BranchCode,
           CASE DocKind WHEN 'P' THEN NetPrice ELSE -NetPrice END AS NetPurchases,
           CASE WHEN DocKind = 'P' THEN 1 ELSE 0 END AS InvoiceCount
    FROM dbo.web_TrxDocs WHERE DocKind IN ('P', 'PR') AND TargetType = 2
),
rk AS (SELECT TOP (10) TargetCode, ROW_NUMBER() OVER (ORDER BY SUM(NetPurchases) DESC) AS SortNo FROM d GROUP BY TargetCode ORDER BY SUM(NetPurchases) DESC)
SELECT rk.SortNo, ISNULL(su.SuppName, CAST(d.TargetCode AS nvarchar(20))) AS SupplierName, d.TrxDate, d.BranchCode,
       CAST(d.NetPurchases AS decimal(18, 2)) AS NetPurchases, d.InvoiceCount
FROM d JOIN rk ON rk.TargetCode = d.TargetCode LEFT JOIN dbo.Supplier su ON su.SuppCode = d.TargetCode
GO
