-- 第一步：识别核心企业和上下游供应链企业 (按总采购金额排序)
-- 1.1 按照订单总额、订单次数、平均订单价值、供应商数量来识别核心企业
SELECT 
    Buyer_ID,
    COUNT(DISTINCT `Order_ID`) AS Order_Count, -- 订单总数，反映业务频繁度
    SUM(`Order_Value_USD`) AS Total_Purchased, -- 总采购金额，核心指标
    AVG(`Order_Value_USD`) AS Avg_Order_Value, -- 平均订单价值
    COUNT(DISTINCT `Supplier_ID`) AS Supplier_Count -- 供应商数量，反映供应链广度
FROM raws
GROUP BY Buyer_ID
HAVING COUNT(DISTINCT `Order_ID`) >= 30 and SUM(`Order_Value_USD`) > 80000
ORDER BY 
Total_Purchased DESC; -- 按总采购额降序排列，排名最高的就是最核心的企业
-- 至此我们找到两个关键的核心企业，b12和b40

-- 还要检查供应商是否同时有买家和供应商双重身份，从而决定下一步是否梳理多级供应商
SELECT Supplier_ID
FROM raws
WHERE Supplier_ID IN (SELECT DISTINCT Buyer_ID FROM raws);
-- 这里的buyers和suppliers是带前缀编码的字符串，所以肯定不会重复。

-- 1.2 查询核心企业(B12和B40)的主要供应商及合作情况
SELECT 
    `Supplier_ID`,
    SUM(`Order_Value_USD`) AS Total_Contract_Value, -- 与该供应商的总交易额
    COUNT(`Order_ID`) AS Transaction_Count, -- 交易次数
    AVG(`Order_Value_USD`) AS Avg_Transaction_Value, -- 平均交易额
    MIN(`Order_Date`) AS First_Transaction_Date, -- 首次合作时间
    MAX(`Order_Date`) AS Last_Transaction_Date, -- 最近合作时间
    AVG(`Delay_Days`) AS Avg_Delay_Days -- 平均交付延迟天数(评估供应稳定性)
FROM 
    raws
WHERE 
    Buyer_ID = 'B12' -- 指定核心企业ID
GROUP BY 
    `Supplier_ID`
ORDER BY 
    SUM(`Order_Value_USD`) DESC; -- 按交易总额降序，排名最高的就是最重要的战略供应商即S16和S8


SELECT 
    `Supplier_ID`,
    SUM(`Order_Value_USD`) AS Total_Contract_Value, -- 与该供应商的总交易额
    COUNT(`Order_ID`) AS Transaction_Count, -- 交易次数
    AVG(`Order_Value_USD`) AS Avg_Transaction_Value, -- 平均交易额
    MIN(`Order_Date`) AS First_Transaction_Date, -- 首次合作时间
    MAX(`Order_Date`) AS Last_Transaction_Date, -- 最近合作时间
    AVG(`Delay_Days`) AS Avg_Delay_Days -- 平均交付延迟天数(评估供应稳定性)
FROM 
    raws
WHERE 
    Buyer_ID = 'B40' 
GROUP BY 
    `Supplier_ID`
ORDER BY 
    SUM(`Order_Value_USD`) DESC; -- 按交易总额降序，排名最高的就是最重要的战略供应商即S10和S5


-- 1.3 评估所有供应商的可靠性，这里设置简单规则，如果主供应商平均可靠性分数低于0.70，则要求企业增信
-- 1.3 评估所有供应商的可靠性
SELECT 
    `Buyer_ID`,
    `Supplier_ID`,
    AVG(`Supplier_Reliability_Score`) AS Avg_Reliability_Score,
    COUNT(CASE WHEN `Disruption_Type` IS NOT NULL THEN 1 END) AS Disruption_Count,
    MAX(`Disruption_Severity`) AS Worst_Disruption_Severity,
    -- 增加一个简单规则
    CASE 
        WHEN AVG(`Supplier_Reliability_Score`) < 0.7 THEN '要求增信，或提高'
        ELSE '无需增信'
    END AS Enhancement_Advice
FROM 
    raws
WHERE 
    `Buyer_ID` IN ('B40', 'B12')
GROUP BY 
    `Buyer_ID`, `Supplier_ID` -- 分别计算给B12和B40供货的供应商是否需要增信
ORDER BY 
    `Buyer_ID`, Avg_Reliability_Score ASC; -- 按分数升序排列，风险高的（分数低的）排在前面

-- 2 简单规则的供应商风险分级与融资策略匹配
SELECT 
    `Buyer_ID` AS Core_Enterprise,
    `Supplier_ID`,
    AVG(`Supplier_Reliability_Score`) AS Avg_Score,
    -- 风险分级
    CASE 
        WHEN AVG(`Supplier_Reliability_Score`) >= 0.85 THEN 'A级'
        WHEN AVG(`Supplier_Reliability_Score`) BETWEEN 0.7 AND 0.84 THEN 'B级'
        ELSE 'C级' 
    END AS Risk_Tier,
    -- 差异化融资方案
    CASE 
        WHEN AVG(`Supplier_Reliability_Score`) >= 0.85 THEN '融资比例100% | 基准-0.25%'
        WHEN AVG(`Supplier_Reliability_Score`) BETWEEN 0.7 AND 0.84 THEN '融资比例90% | 基准+0.25%'
        ELSE '融资比例60% | 利率基准+1% | 需核心企业担保'
    END AS Financing_Terms
FROM raws
WHERE `Buyer_ID` IN ('B12','B40')
GROUP BY `Buyer_ID`, `Supplier_ID`;

-- 3 持续监控核心企业和供应商交易状况
-- 3.1 监控核心企业付款延迟恶化
SELECT 
    Buyer_ID,
    Month,
    Current_Avg_Delay,
    Delay_Increase
FROM (
    SELECT 
        Buyer_ID,
        DATE_FORMAT(Order_Date, '%Y-%m') AS Month,
        AVG(Delay_Days) AS Current_Avg_Delay,
        AVG(Delay_Days) - LAG(AVG(Delay_Days), 1) OVER (
            PARTITION BY Buyer_ID 
            ORDER BY DATE_FORMAT(Order_Date, '%Y-%m')
        ) AS Delay_Increase
    FROM raws
    WHERE Buyer_ID IN ('B12','B40')
    GROUP BY Buyer_ID, DATE_FORMAT(Order_Date, '%Y-%m')
) AS monthly_delays
WHERE Delay_Increase >= 5;  -- 付款延迟按月环比增加超过5天就触发预警

-- 3.2 监控供应商可靠性（简单规则月平均可靠性下降0.25触发）
-- 3.2 监控供应商可靠性
SELECT 
    Supplier_ID,
    Month,
    Current_Score,
    Last_Month_Score,
    Score_Drop,
    -- 核心供应商标识
    CASE 
        WHEN Supplier_ID IN ('S16', 'S8', 'S10', 'S5') THEN '核心供应商'
        ELSE '普通供应商'
    END AS Supplier_Type
FROM (
    SELECT 
        Supplier_ID,
        DATE_FORMAT(Order_Date, '%Y-%m') AS Month,
        AVG(Supplier_Reliability_Score) AS Current_Score,
        LAG(AVG(Supplier_Reliability_Score), 1) OVER (
            PARTITION BY Supplier_ID 
            ORDER BY DATE_FORMAT(Order_Date, '%Y-%m')
        ) AS Last_Month_Score,
        (LAG(AVG(Supplier_Reliability_Score), 1) OVER (
            PARTITION BY Supplier_ID 
            ORDER BY DATE_FORMAT(Order_Date, '%Y-%m')
        ) - AVG(Supplier_Reliability_Score)) AS Score_Drop,
        Buyer_ID
    FROM raws
    WHERE Buyer_ID IN ('B12', 'B40')
    GROUP BY Supplier_ID, DATE_FORMAT(Order_Date, '%Y-%m'), Buyer_ID
) AS supplier_scores
WHERE Score_Drop > 0.25;  -- B12和B40的供应商单月可靠性下降超过0.25触发


