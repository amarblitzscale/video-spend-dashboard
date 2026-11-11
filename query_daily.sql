-- Daily video share of Meta spend, last 61 days, by golive cohort x seller class x hit-1 flag
-- Database: 3 (BigQuery). Same cohort, creative and seller_class logic as query.sql.
--
-- hit1 = 1 when the seller ever had two consecutive weeks with team_mapping = 'HIT',
--        marketing_spend > 3500 and profit_loss_perc2 > 5 (gc_view_3). It applies to the whole period.
-- seller_class: outlier = W0 GMV > 0 and W0 spend / W0 GMV < 5%, otherwise normal (as in query.sql).
-- Engagement campaigns (objective OUTCOME_ENGAGEMENT / POST_ENGAGEMENT) are excluded.
-- Days before the cohort's W0 Monday are left out; today is left out because it is still running.

WITH golive AS (
  SELECT seller_id, MIN(CAST(year_week AS INT64)) AS golive_week
  FROM `blitzscale-prod-project.nushop.gc_view_3`
  WHERE marketing_spend >= 1000
    AND team_mapping = 'HIT'
    AND seller_id != 'Shopdeck'
  GROUP BY 1
),

cohort AS (
  SELECT g.seller_id, g.golive_week,
         MIN(DATE_TRUNC(DATE(v.start_date), ISOWEEK)) AS w0_mon
  FROM golive g
  JOIN `blitzscale-prod-project.nushop.gc_view_3` v
    ON v.seller_id = g.seller_id
   AND CAST(v.year_week AS INT64) = g.golive_week
  WHERE g.golive_week >= CAST(FORMAT_DATE('%G%V', DATE_SUB(CURRENT_DATE('Asia/Kolkata'), INTERVAL 52 WEEK)) AS INT64)
  GROUP BY 1, 2
),

-- seller class from W0
w0_spend AS (
  SELECT c.golive_week, a.seller_id, a.ad_id, SUM(a.spend) AS spend
  FROM `blitzscale-prod-project.fb_marketings.fb_ads_insights` a
  JOIN cohort c ON a.seller_id = c.seller_id
  WHERE DATE(a.date_start) >= DATE_SUB(CURRENT_DATE('Asia/Kolkata'), INTERVAL 56 WEEK)
    AND DATE(a.date_start) BETWEEN c.w0_mon AND DATE_ADD(c.w0_mon, INTERVAL 6 DAY)
    AND IFNULL(a.objective, '') NOT IN ('OUTCOME_ENGAGEMENT', 'POST_ENGAGEMENT')   -- engagement campaigns are left out of every number
  GROUP BY 1, 2, 3
),

w0_orders AS (
  SELECT c.golive_week, o.utm_content AS ad_id, SUM(o.gmv) AS gmv
  FROM `blitzscale-prod-project.csv_upload.fb_ads_order_summary_daily` o
  JOIN cohort c ON o.seller_id = c.seller_id
  WHERE o.order_date_ist >= DATE_SUB(CURRENT_DATE('Asia/Kolkata'), INTERVAL 56 WEEK)
    AND o.order_date_ist BETWEEN c.w0_mon AND DATE_ADD(c.w0_mon, INTERVAL 6 DAY)
  GROUP BY 1, 2
),

seller_w0 AS (
  SELECT s.golive_week, s.seller_id, SUM(s.spend) AS w0_spend, SUM(IFNULL(o.gmv, 0)) AS w0_gmv
  FROM w0_spend s
  LEFT JOIN w0_orders o USING (golive_week, ad_id)
  GROUP BY 1, 2
),

seller_cls AS (
  SELECT c.golive_week, c.seller_id,
         CASE WHEN IFNULL(w.w0_gmv, 0) > 0 AND w.w0_spend / w.w0_gmv < 0.05 THEN 'outlier'
              ELSE 'normal' END AS seller_class
  FROM cohort c
  LEFT JOIN seller_w0 w USING (golive_week, seller_id)
),

-- hit 1: two consecutive qualifying weeks, ever
qual_weeks AS (
  SELECT seller_id, DATE(start_date) AS d
  FROM `blitzscale-prod-project.nushop.gc_view_3`
  WHERE team_mapping = 'HIT' AND marketing_spend > 3500 AND profit_loss_perc2 > 5
),

hit1 AS (
  SELECT DISTINCT a.seller_id
  FROM qual_weeks a
  JOIN qual_weeks b
    ON a.seller_id = b.seller_id
   AND DATE_DIFF(b.d, a.d, DAY) = 7
),

-- daily spend
ads AS (
  SELECT c.golive_week, a.seller_id, a.ad_id, DATE(a.date_start) AS day, a.spend,
         IFNULL(a.is_catalog_ad, FALSE)                                    AS is_cat,
         (a.video_id IS NOT NULL OR a.object_type = 'VIDEO')               AS is_vid,
         (a.image_hash IS NOT NULL OR a.image_url IS NOT NULL
            OR a.object_type = 'PHOTO')                                    AS is_img
  FROM `blitzscale-prod-project.fb_marketings.fb_ads_insights` a
  JOIN cohort c ON a.seller_id = c.seller_id
  WHERE DATE(a.date_start) >= DATE_SUB(CURRENT_DATE('Asia/Kolkata'), INTERVAL 61 DAY)
    AND DATE(a.date_start) <  CURRENT_DATE('Asia/Kolkata')
    AND DATE(a.date_start) >= c.w0_mon
    AND IFNULL(a.objective, '') NOT IN ('OUTCOME_ENGAGEMENT', 'POST_ENGAGEMENT')   -- engagement campaigns are left out of every number
),

ad_type AS (
  SELECT ad_id,
         CASE WHEN LOGICAL_OR(is_cat) THEN 'catalogue'
              WHEN LOGICAL_OR(is_vid) THEN 'video'
              WHEN LOGICAL_OR(is_img) THEN 'banner'
              ELSE 'other' END AS creative
  FROM ads
  GROUP BY 1
)

SELECT
  CAST(a.day AS STRING)                                          AS day,
  a.golive_week,
  sc.seller_class,
  IF(h.seller_id IS NULL, 0, 1)                                  AS hit1,
  COUNT(DISTINCT a.seller_id)                                    AS sellers,
  ROUND(SUM(a.spend))                                            AS total_spend,
  ROUND(SUM(IF(t.creative = 'video', a.spend, 0)))               AS video_spend
FROM ads a
JOIN ad_type t USING (ad_id)
JOIN seller_cls sc ON sc.golive_week = a.golive_week AND sc.seller_id = a.seller_id
LEFT JOIN hit1 h ON h.seller_id = a.seller_id
GROUP BY a.day, a.golive_week, sc.seller_class, hit1
ORDER BY a.day, a.golive_week, sc.seller_class, hit1
