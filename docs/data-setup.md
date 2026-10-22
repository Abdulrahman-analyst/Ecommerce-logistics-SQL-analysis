# Data setup

## SQLite

Download and extract the Olist dataset from the source linked in the main README. In DB Browser for SQLite, create a database and import the following CSV files as tables. Keep the first row as column names and preserve IDs as text.

| Source CSV | SQLite table |
|---|---|
| olist_customers_dataset.csv | customers |
| olist_orders_dataset.csv | orders |
| olist_order_items_dataset.csv | order_items |
| olist_order_payments_dataset.csv | payments |
| olist_order_reviews_dataset.csv | reviews |
| olist_products_dataset.csv | products |
| olist_sellers_dataset.csv | sellers |
| product_category_name_translation.csv | category_translation |

Store `price`, `freight_value`, and `payment_value` as numeric values, and `review_score` as an integer. Import timestamps as text; the SQL views parse them. Do not use geolocation data for this analysis.

Run the view definitions in `sql/analysis.sql` before running Q1–Q5. The script recreates three views: `clean_orders`, `order_analysis`, and `monthly_summary`. It does not modify the source tables. Run the analysis queries separately to inspect each result.

`order_analysis` contains one row per order. Items, payments, and reviews are aggregated by `order_id` before joining. Delivery timestamps are compared at calendar-day level.

## Power BI input

Export these five tables/views as CSV with headers: `order_analysis`, `order_items`, `customers`, `products`, and `category_translation`. Import them individually through Text/CSV.

In Power Query:

- Keep identifiers as Text; use Whole Number for counts and the delivery flag.
- Use Date/Time for purchase and delivery timestamps.
- Use Decimal Number with English (United States) locale for prices, freight, payments, and review averages.
- Merge `customers[customer_id]` into `order_analysis[customer_id]` with a left join; expand `customer_unique_id` only.
- Merge `category_translation` into `products` by `product_category_name`; expand the English category name and rename it `category_name`. Replace underscores with spaces and capitalize words.
- Disable load for the two lookup queries used only by merges: `customers` and `category_translation`.

Use `powerbi/measures.dax` to create the calculated objects and measures one at a time. Set rates to Percentage with two decimals, counts to Whole Number, and review averages to two decimals.

## Relationships

Create active one-to-many relationships with single-direction filtering:

- `DimDate[Date]` → `order_analysis[order_date]`
- `order_analysis[order_id]` → `order_items[order_id]`
- `products[product_id]` → `order_items[product_id]`

Use `Group Eligible Deliveries`, `Group Late Orders`, and `Group Late Delivery Rate` for category and seller delivery tables. These measures pass distinct order IDs back to the order-level table without changing relationships to bidirectional.

## Report filters

- Use `DimDate[Date]` as the purchase-date slicer.
- Apply `DimDate[TrendPeriod] = 1` to monthly charts only, and sort `YearMonth` ascending.
- Commercial category chart: Top 10 by `Category Revenue`.
- Non-delivered status chart: exclude `delivered`.
- Review comparison: exclude blank `Delivery Group`.
- Delivery tables: Top 10 by `Group Eligible Deliveries`.
- The Date slicer filters all visuals. The delivery-page charts and tables do not filter the other visuals.

Raw files and local database paths stay outside version control. If opening a PBIX built on another computer, update its CSV paths in Power Query before refreshing.
