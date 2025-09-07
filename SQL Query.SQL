CREATE VIEW PBI_Inventory
AS 

WITH LatestPOLine AS (
    SELECT StockItemID, ExpectedUnitPricePerOuter
        , ROW_NUMBER() OVER (PARTITION BY StockItemID ORDER BY PurchaseOrderID DESC) rn
    FROM Purchasing.PurchaseOrderLines
)
-- Retrieves the most recent purchase order line for each stock item by ranking them using ROW_NUMBER() -> the view displays the latest order unit price

, StockGroupsPerItem AS (
    SELECT sisg.StockItemID
        , STRING_AGG(sg.StockGroupName, ', ') StockGroupNames
    FROM Warehouse.StockItemStockGroups sisg
    JOIN Warehouse.StockGroups sg
        ON sisg.StockGroupID = sg.StockGroupID
    GROUP BY sisg.StockItemID
)
-- Aggregates all the stock group names associated with each item into one string -> simplifies reporting and filtering in dashboard

, IncomingStockPipeline AS (
    SELECT pol.StockItemID
        , SUM(pol.OrderedOuters) IncomingQuantity
        , MAX(po.ExpectedDeliveryDate) LatestExpectedDelivery
        , AVG(pol.ExpectedUnitPricePerOuter) AvgExpectedUnitPrice
    FROM Purchasing.PurchaseOrderLines pol
    JOIN Purchasing.PurchaseOrders po ON pol.PurchaseOrderID = po.PurchaseOrderID
    WHERE po.IsOrderFinalized = 0
    GROUP BY pol.StockItemID
)
-- Calculates the incoming stock qualities, expected delivery date and average expected price for each item -> these can be used in visuals designed for inventory management and forecasting stock levels

SELECT si.StockItemID
    , si.StockItemName
    , sgpi.StockGroupNames
    , s.SupplierName
    , si.LeadTimeDays
    , sih.QuantityOnHand
    , sih.BinLocation
    , sih.LastCostPrice
    , pol.ExpectedUnitPricePerOuter
    , isp.IncomingQuantity
    , isp.LatestExpectedDelivery
    , isp.AvgExpectedUnitPrice
    , sih.ReorderLevel
    , sih.TargetStockLevel
    , CASE WHEN sih.QuantityOnHand < sih.ReorderLevel THEN 'Reorder Needed'
           WHEN sih.QuantityOnHand < sih.TargetStockLevel THEN 'Stock Low'
           ELSE 'Sufficient'
       END StockStatus
    , sih.QuantityOnHand * sih.LastCostPrice InventoryValue
FROM Warehouse.StockItems si
LEFT JOIN Warehouse.StockItemHoldings sih
    ON si.StockItemID = sih.StockItemID
LEFT JOIN StockGroupsPerItem sgpi
    ON si.StockItemID = sgpi.StockItemID
LEFT JOIN Purchasing.Suppliers s
    ON si.SupplierID = s.SupplierID
LEFT JOIN LatestPOLine pol
    ON si.StockItemID = pol.StockItemID AND pol.rn = 1
LEFT JOIN IncomingStockPipeline isp
    ON si.StockItemID = isp.StockItemID
GO
-- Combines all CTE's into one view


CREATE VIEW PBI_SupplierRelability
AS 
SELECT Purchasing.Suppliers.SupplierName
, Purchasing.Suppliers.SupplierID
, Warehouse.StockItems.LeadTimeDays
, AVG(DATEDIFF(DAY, Purchasing.PurchaseOrders.OrderDate, Purchasing.PurchaseOrders.ExpectedDeliveryDate)) AvgLeadTime
FROM Purchasing.Suppliers
LEFT JOIN Purchasing.PurchaseOrders
    ON Purchasing.Suppliers.SupplierID = Purchasing.PurchaseOrders.SupplierID
LEFT JOIN Warehouse.StockItems
    ON Purchasing.Suppliers.SupplierID = Warehouse.StockItems.SupplierID
GROUP BY Purchasing.Suppliers.SupplierName
    , Purchasing.Suppliers.SupplierID
    , Warehouse.StockItems.LeadTimeDays
-- Creates a view analysing supplier reliability and actual lead time performance compared to expected lead time
