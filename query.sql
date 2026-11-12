-- Golive cohort x week-since-golive (W0-W10) x seller class: Meta spend and ad-attributed GMV on video vs other creatives
-- Database: 3 (BigQuery). Same logic as card 17607, with these changes:
--   1. rows are split by seller_class (outlier / normal), so the dashboard can switch outliers on and off
--   2. additive sums (spend, GMV, impressions, clicks, orders) are returned for video and other creatives, so
--      S/GMV, CPM, CTR, CVR (orders / clicks) and AOV (GMV / orders) can be recomputed for any combination
--   3. rows are also split by category: the seller's top-level (L1) category with the most orders
--      (same rule as the "seller level category mapping - L1" question); sellers without one are 'Uncategorised'
--
-- Sellers with no products, or no store / website, are excluded (they cannot sell, so their spend has no GMV).
-- Only purchase campaigns are counted: sales objective (OUTCOME_SALES, plus the older CONVERSIONS / PRODUCT_CATALOG_SALES)
-- optimised for OFFSITE_CONVERSIONS, RETURN_ON_AD_SPEND or ONSITE_CONVERSIONS. Engagement, leads, traffic, awareness,
-- messages and sales ads optimised for clicks, replies or calls are excluded from all spend, GMV and seller_class numbers.
--
-- seller_class is decided once per seller from its W0 (golive week) Meta numbers, then applied to W0-W10:
--   outlier   = W0 GMV > 0 and W0 spend / W0 GMV < 5% (sellers with no W0 GMV are not outliers)
--   normal    = everyone else

WITH golive AS (
  SELECT seller_id, MIN(CAST(year_week AS INT64)) AS golive_week
  FROM `blitzscale-prod-project.nushop.gc_view_3`
  WHERE marketing_spend >= 1000
    AND team_mapping = 'HIT'
    AND seller_id != 'Shopdeck'
  GROUP BY 1
),

-- sellers that have set up a shop: at least one product, and a store/website config or profile
shop_products AS (
  SELECT DISTINCT seller_id
  FROM `blitzscale-prod-project.nushop.customer_products`
  WHERE created_at >= TIMESTAMP('2015-01-01')
    AND seller_id IN (SELECT seller_id FROM golive)
),

shop_store AS (
  SELECT seller_id FROM `blitzscale-prod-project.nushop.web_configs`
  WHERE created_at >= TIMESTAMP('2015-01-01') AND seller_id IN (SELECT seller_id FROM golive)
  UNION DISTINCT
  SELECT seller_id FROM `blitzscale-prod-project.nushop.website_seller_profile`
  WHERE created_at >= TIMESTAMP('2015-01-01') AND seller_id IN (SELECT seller_id FROM golive)
),

cohort AS (
  SELECT g.seller_id, g.golive_week,
         MIN(DATE_TRUNC(DATE(v.start_date), ISOWEEK)) AS w0_mon
  FROM golive g
  JOIN `blitzscale-prod-project.nushop.gc_view_3` v
    ON v.seller_id = g.seller_id
   AND CAST(v.year_week AS INT64) = g.golive_week
  WHERE g.golive_week >= CAST(FORMAT_DATE('%G%V', DATE_SUB(CURRENT_DATE('Asia/Kolkata'), INTERVAL 52 WEEK)) AS INT64)
    AND g.seller_id IN (SELECT seller_id FROM shop_products)   -- sellers with no products,
    AND g.seller_id IN (SELECT seller_id FROM shop_store)      -- or no store / website, are left out
  GROUP BY 1, 2
),

seller_category AS (
  SELECT seller_id, l1 FROM (
    SELECT oi.seller_id, ct.l1,
           ROW_NUMBER() OVER (PARTITION BY oi.seller_id ORDER BY COUNT(oi.seller_group_id) DESC, ct.l1) AS rk
    FROM `blitzscale-prod-project.nushop.orderitems` oi
    JOIN `blitzscale-prod-project.nushop.category_tagged` ct ON ct.product_id = oi.customer_product_short_id
    WHERE oi.seller_id IN (SELECT seller_id FROM cohort)
      AND oi.seller_last_status NOT IN ('invalid', 'initiated', 'enqueued')
      AND DATE(oi.createdat) BETWEEN '2023-01-01' AND CURRENT_DATE()
      AND ct.l1 IS NOT NULL AND ct.l1 != ''
    GROUP BY 1, 2)
  WHERE rk = 1
),

ads AS (
  SELECT c.golive_week, a.seller_id, a.ad_id,
         DATE_DIFF(DATE_TRUNC(DATE(a.date_start), ISOWEEK), c.w0_mon, WEEK) AS wk,
         a.spend, a.impressions, a.clicks,
         IFNULL(a.is_catalog_ad, FALSE)                                    AS is_cat,
         (a.video_id IS NOT NULL OR a.object_type = 'VIDEO')               AS is_vid,
         (a.image_hash IS NOT NULL OR a.image_url IS NOT NULL
            OR a.object_type = 'PHOTO')                                    AS is_img
  FROM `blitzscale-prod-project.fb_marketings.fb_ads_insights` a
  JOIN cohort c ON a.seller_id = c.seller_id
  WHERE DATE(a.date_start) >= DATE_SUB(CURRENT_DATE('Asia/Kolkata'), INTERVAL 56 WEEK)
    AND DATE(a.date_start) BETWEEN c.w0_mon AND DATE_ADD(c.w0_mon, INTERVAL 76 DAY)
    AND a.objective IN ('OUTCOME_SALES', 'CONVERSIONS', 'PRODUCT_CATALOG_SALES')                  -- purchase campaigns only: sales objective ...
    AND a.optimization_goal IN ('OFFSITE_CONVERSIONS', 'RETURN_ON_AD_SPEND', 'ONSITE_CONVERSIONS')  -- ... optimised for conversions, not clicks, replies or calls
),

ad_type AS (
  SELECT ad_id,
         CASE WHEN LOGICAL_OR(is_cat) THEN 'catalogue'
              WHEN LOGICAL_OR(is_vid) THEN 'video'
              WHEN LOGICAL_OR(is_img) THEN 'banner'
              ELSE 'other' END AS creative
  FROM ads
  GROUP BY 1
),

spend AS (
  SELECT a.golive_week, a.wk, a.seller_id, a.ad_id, t.creative,
         SUM(a.spend) AS spend, SUM(a.impressions) AS imp, SUM(a.clicks) AS clk
  FROM ads a
  JOIN ad_type t USING (ad_id)
  GROUP BY 1, 2, 3, 4, 5
),

orders AS (
  SELECT c.golive_week, o.utm_content AS ad_id,
         DATE_DIFF(DATE_TRUNC(o.order_date_ist, ISOWEEK), c.w0_mon, WEEK) AS wk,
         SUM(o.gmv) AS gmv, SUM(o.order_count) AS ord
  FROM `blitzscale-prod-project.csv_upload.fb_ads_order_summary_daily` o
  JOIN cohort c ON o.seller_id = c.seller_id
  WHERE o.order_date_ist >= DATE_SUB(CURRENT_DATE('Asia/Kolkata'), INTERVAL 56 WEEK)
    AND o.order_date_ist BETWEEN c.w0_mon AND DATE_ADD(c.w0_mon, INTERVAL 76 DAY)
  GROUP BY 1, 2, 3
),

base AS (
  SELECT s.*, IFNULL(o.gmv, 0) AS gmv, IFNULL(o.ord, 0) AS ord
  FROM spend s
  LEFT JOIN orders o
    ON o.ad_id = s.ad_id AND o.wk = s.wk AND o.golive_week = s.golive_week
),

seller_w0 AS (
  SELECT golive_week, seller_id, SUM(spend) AS w0_spend, SUM(gmv) AS w0_gmv
  FROM base
  WHERE wk = 0
  GROUP BY 1, 2
),

seller_cls AS (
  SELECT c.golive_week, c.seller_id,
         CASE WHEN IFNULL(w.w0_gmv, 0) > 0 AND w.w0_spend / w.w0_gmv < 0.05 THEN 'outlier'
              ELSE 'normal' END AS seller_class,
         IFNULL(k.l1, 'Uncategorised') AS category
  FROM cohort c
  LEFT JOIN seller_w0 w USING (golive_week, seller_id)
  LEFT JOIN seller_category k ON k.seller_id = c.seller_id
),

golive_counts AS (
  SELECT golive_week, seller_class, category, COUNT(*) AS golives FROM seller_cls GROUP BY 1, 2, 3
)

SELECT
  b.golive_week,
  CONCAT('W', CAST(b.wk AS STRING))                                        AS week_since_golive,
  sc.seller_class,
  sc.category,
  gc.golives,
  COUNT(DISTINCT b.seller_id)                                              AS sellers_spending,
  COUNT(DISTINCT IF(b.creative = 'video', b.seller_id, NULL))              AS sellers_on_video,
  ROUND(SUM(b.spend))                                                      AS total_spend,
  ROUND(SUM(IF(b.creative = 'video', b.spend, 0)))                         AS video_spend,
  ROUND(SUM(IF(b.creative != 'video', b.spend, 0)))                        AS other_spend,
  ROUND(SUM(IF(b.creative = 'video', b.gmv, 0)))                           AS video_gmv,
  ROUND(SUM(IF(b.creative != 'video', b.gmv, 0)))                          AS other_gmv,
  SUM(IF(b.creative = 'video', b.imp, 0))                                  AS video_imp,
  SUM(IF(b.creative != 'video', b.imp, 0))                                 AS other_imp,
  SUM(IF(b.creative = 'video', b.clk, 0))                                  AS video_clk,
  SUM(IF(b.creative != 'video', b.clk, 0))                                 AS other_clk,
  SUM(IF(b.creative = 'video', b.ord, 0))                                  AS video_orders,
  SUM(IF(b.creative != 'video', b.ord, 0))                                 AS other_orders,
  ANY_VALUE(DATE_ADD(c.w0_mon, INTERVAL b.wk * 7 + 6 DAY)) >= CURRENT_DATE('Asia/Kolkata') AS partial_week
FROM base b
JOIN seller_cls sc USING (golive_week, seller_id)
JOIN golive_counts gc USING (golive_week, seller_class, category)
JOIN (SELECT golive_week, MIN(w0_mon) AS w0_mon FROM cohort GROUP BY 1) c USING (golive_week)
WHERE b.wk BETWEEN 0 AND 10
GROUP BY b.golive_week, b.wk, sc.seller_class, sc.category, gc.golives
ORDER BY b.golive_week, b.wk, sc.seller_class, sc.category
