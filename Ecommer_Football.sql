-- Tạo Database
IF DB_ID(N'E_commerce') IS NULL
    EXEC(N'CREATE DATABASE E_commerce');
GO

USE E_commerce;
GO

-- TỔNG QUAN

-- Q1: Số lượng đơn hàng đã bán ra của cửa hàng 
SELECT COUNT(DISTINCT(Order_id)) AS Total_Order FROM fact_orders

-- Q2: Tổng doanh thu của cửa hàng
SELECT SUM(CAST(order_revenue AS DECIMAL(18,2))) AS Total_Revenue FROM fact_orders

-- Q3: Tổng lợi nhuận hàng đã bán của cửa hàng
SELECT SUM(CAST(order_profit AS DECIMAL(18,2))) AS Total_Profit FROM fact_orders

-- Q4: Tổng số lượng hàng đã bán của cửa hàng
SELECT SUM(CAST(order_units AS INT)) AS Total_Units FROM fact_orders

-- Q5: AOV (Gía trị trung bình của 1 đơn hàng)
SELECT ROUND(SUM(CAST(order_revenue AS DECIMAL(18,2)))/COUNT(DISTINCT Order_id),2) AS AOV FROM fact_orders

-- Q6: Biên lợi nhuận của doanh nghiệp
SELECT ROUND(
    SUM(CAST(order_profit AS DECIMAL(18,2))) * 100.0
    / NULLIF(SUM(CAST(order_revenue AS DECIMAL(18,2))), 0),
    2
) AS Profit_Margin_Percent
FROM fact_orders

-- PHÂN TÍCH XU HƯỚNG VÀ TĂNG TRƯỞNG CỦA DOANH NGHIỆP

--Q1: Phân tích các chỉ số xu hướng của doanh nghiệp
SELECT YEAR(order_datetime) AS YEAR, 
SUM(CAST(order_revenue AS DECIMAL(18,2))) AS Total_Revenue,
SUM(CAST(order_profit AS DECIMAL(18,2))) AS Total_Profit,
SUM(CAST(order_units AS INT)) AS Total_Units,
ROUND(SUM(CAST(order_revenue AS DECIMAL(18,2)))/COUNT(DISTINCT Order_id),2) AS AOV,
ROUND(
    SUM(CAST(order_profit AS DECIMAL(18,2))) * 100.0
    / NULLIF(SUM(CAST(order_revenue AS DECIMAL(18,2))), 0),
    2
) AS Profit_Margin_Percent
FROM fact_orders
GROUP BY YEAR(order_datetime)
ORDER BY YEAR ASC

-- Q2: Phân tích xu hướng YoY

-- Tính tổng doanh thu từng năm
WITH YearlyRevenue AS (
    SELECT
        YEAR(order_datetime) AS order_year,
        SUM(CAST(order_revenue AS DECIMAL(18,2))) AS revenue
    FROM fact_orders
    GROUP BY YEAR(order_datetime)
),

-- Lấy doanh thu của năm trước
RevenueComparison AS (
    SELECT
        order_year,
        revenue,
        LAG(revenue) OVER (ORDER BY order_year) AS previous_year_revenue
    FROM YearlyRevenue
)

-- Tính tỷ lệ tăng trưởng YoY
SELECT
    order_year,
    revenue,
    previous_year_revenue,

    revenue - previous_year_revenue AS revenue_change,

    ROUND(
        100.0 * (revenue - previous_year_revenue)
        / NULLIF(previous_year_revenue, 0),
        2
    ) AS yoy_growth_pct

FROM RevenueComparison
ORDER BY order_year;

-- PHÂN TÍCH PHÂN KHÚC KHÁCH HÀNG

-- Q1: Hiệu quả của từng phân khúc
SELECT DC.segment_id, segment_description, 
COUNT(DISTINCT(DC.customer_id)) AS Total_Customer, 
COUNT(DISTINCT F.order_id) AS Total_Order,
SUM(CAST(order_revenue AS DECIMAL(18,2))) AS Total_Revenue,
SUM(CAST(order_profit AS DECIMAL(18,2))) AS Total_Profit,
SUM(CAST(order_units AS INT)) AS Total_Units,
ROUND(SUM(CAST(order_revenue AS DECIMAL(18,2)))/COUNT(DISTINCT F.order_id),2) AS AOV
FROM fact_orders AS F INNER JOIN dim_customers_private AS DC
ON F.customer_id = DC.customer_id INNER JOIN dim_segments AS DS 
ON DC.segment_id = DS.segment_id
GROUP BY DC.segment_id, segment_description
ORDER BY Total_Revenue DESC

-- Q2: Khách mua một lần và khách quay lại
WITH Customer_Orders AS (
SELECT customer_id,COUNT(*) AS Order_count FROM fact_orders
GROUP BY customer_id
)
SELECT 
	CASE WHEN Order_count = 1 THEN N'Khách hàng mua 1 lần'
	ELSE N'Khách mua trên 1 lần'
	END AS Customer_type,
COUNT(*) AS Total_Customer,
ROUND( CAST(COUNT(*) AS FLOAT) * 100 / SUM(COUNT(*)) OVER () ,2) AS Customer_Percentage
FROM Customer_Orders
GROUP BY CASE 
        WHEN Order_count = 1 
            THEN N'Khách hàng mua 1 lần'
        ELSE N'Khách mua trên 1 lần'
    END;

-- Q3: Phân tích RFM
WITH CustomerRFM AS (
    SELECT
        customer_id,
        DATEDIFF(
            DAY,
            MAX(order_datetime),
            '2025-01-01'
        ) AS recency,
        -- Tổng số đơn hàng
        COUNT(order_id) AS frequency,
        -- Tổng số tiền khách hàng đã chi
        SUM(CAST(order_revenue AS DECIMAL(18,2))) AS monetary
    FROM fact_orders
    GROUP BY customer_id
)

SELECT
    customer_id,
    recency,
    frequency,
    monetary,

    6 - NTILE(5) OVER (
        ORDER BY recency
    ) AS r_score,

    NTILE(5) OVER (
        ORDER BY frequency
    ) AS f_score,

    NTILE(5) OVER (
        ORDER BY monetary
    ) AS m_score

FROM CustomerRFM
ORDER BY customer_id;

-- PHÂN TÍCH SẢN PHẨM

-- Q1: Phân tích nhóm sản phẩm 
WITH CategorySummary AS (
    SELECT
        DC.category_id,
        DC.category_name,
        COUNT(DISTINCT FOI.order_id) AS Total_Order,
        SUM(
            CAST(FOI.quantity AS DECIMAL(18, 2))
            * CAST(FOI.unit_price AS DECIMAL(18, 2))
        ) AS Total_Revenue,
        SUM(
            CAST(FOI.quantity AS DECIMAL(18, 2))
            * (
                CAST(FOI.unit_price AS DECIMAL(18, 2))
                - CAST(FOI.unit_cost AS DECIMAL(18, 2))
            )
        ) AS Total_Profit,

        SUM(
            CAST(FOI.quantity AS DECIMAL(18, 2))
        ) AS Total_Units
    FROM fact_order_items AS FOI
    INNER JOIN dim_products AS DP
        ON FOI.product_id = DP.product_id
    INNER JOIN dim_categories AS DC
        ON DP.category_id = DC.category_id
    GROUP BY
        DC.category_id,
        DC.category_name
)
SELECT
    category_id,
    category_name,
    Total_Order,
    Total_Revenue,
    Total_Profit,
    Total_Units,
    ROUND(
        100.0 * Total_Profit / NULLIF(Total_Revenue, 0),
        2
    ) AS Profit_Margin_Percent

FROM CategorySummary
ORDER BY Total_Revenue DESC;

-- Q2: Top 10 sản phẩm có doanh thu cao nhất
-- Tính ở cấp dòng sản phẩm để tránh nhân doanh thu cấp đơn sau JOIN.
SELECT TOP 10
    P.product_id,
    P.product_name,
    SUM(
        CAST(I.quantity AS DECIMAL(18,2))
        * CAST(I.unit_price AS DECIMAL(18,2))
    ) AS Total_Revenue,
    SUM(CAST(I.quantity AS INT)) AS Total_Units,
    SUM(
        CAST(I.quantity AS DECIMAL(18,2))
        * (
            CAST(I.unit_price AS DECIMAL(18,2))
            - CAST(I.unit_cost AS DECIMAL(18,2))
        )
    ) AS Total_Profit
FROM fact_order_items AS I
INNER JOIN dim_products AS P
    ON I.product_id = P.product_id
GROUP BY
    P.product_id,
    P.product_name
ORDER BY Total_Revenue DESC;

-- PHÂN TÍCH MÙA VỤ

-- Q1: Phân tích theo khung giờ bán
WITH Analysis_Hour AS (
    SELECT
        CAST(order_datetime AS DATE) AS Order_Date,
        DATEPART(HOUR, order_datetime) AS Order_Hour,
        SUM(TRY_CAST(order_revenue AS DECIMAL(18, 2))) AS Total_Revenue,
        SUM(TRY_CAST(order_units AS DECIMAL(18, 2))) AS Total_Quantity
    FROM fact_orders
    WHERE order_datetime IS NOT NULL
    GROUP BY
        CAST(order_datetime AS DATE),
        DATEPART(HOUR, order_datetime)
)

SELECT
    CASE Order_Hour
        WHEN 8  THEN '08:00-08:59'
        WHEN 9  THEN '09:00-09:59'
        WHEN 10 THEN '10:00-10:59'
        WHEN 11 THEN '11:00-11:59'
        WHEN 12 THEN '12:00-12:59'
        WHEN 13 THEN '13:00-13:59'
        WHEN 14 THEN '14:00-14:59'
        WHEN 15 THEN '15:00-15:59'
        WHEN 16 THEN '16:00-16:59'
        WHEN 17 THEN '17:00-17:59'
        WHEN 18 THEN '18:00-18:59'
        WHEN 19 THEN '19:00-19:59'
        WHEN 20 THEN '20:00-20:59'
        WHEN 21 THEN '21:00-21:59'
        WHEN 22 THEN '22:00-22:59'
        WHEN 23 THEN '23:00-23:59'
    END AS Hour_Range,

    ROUND(
        AVG(Total_Revenue) / 1000000.0,
        2
    ) AS AVG_Revenue_Million_VND,

    ROUND(
        AVG(Total_Quantity),
        2
    ) AS AVG_Quantity_SKUs

FROM Analysis_Hour
WHERE Order_Hour BETWEEN 8 AND 23
GROUP BY Order_Hour
ORDER BY Order_Hour;
