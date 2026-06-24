# dbops-project
Исходный репозиторий для выполнения проекта дисциплины "DBOps"

## Создадим базу данных и пользователя для миграций

Создание базы данных `store`:

```sql
CREATE DATABASE store;
```

## Создадим пользователя для подключения к базе данных и запуска автотестов и миграций и дадим ему права на создание

```sql
CREATE USER store_user WITH PASSWORD 'store_password';
\c store
GRANT CREATE ON SCHEMA public TO store_user;
```

## Заполнены значения secrets для GitHub Actions для базы на полученной виртуальной машине с полученными данными для миграций:

```text
DB_HOST
DB_PORT
DB_NAME
DB_USER
DB_PASSWORD
```

## Миграция V001__create_tables.sql

Миграция `V001__create_tables.sql` создаёт структуру таблиц, которая повторяет схему базы данных после выполнения скрипта `insert-data.sh`, а именно:
- `product(id, name, picture_url)`;
- `product_info(product_id, name, price)`;
- `orders(id, status)`;
- `orders_date(order_id, status, date_created)`;
- `order_product(quantity, order_id, product_id)`.

## Миграция V002__change_schema.sql

Миграция `V002__change_schema.sql` приводит исходную схему к оптимизированной структуре, убирая две таблицы:
- добавляет `product.price`;
- переносит цену из `product_info.price` в `product.price`;
- добавляет `orders.date_created`;
- переносит дату заказа из `orders_date.date_created` в `orders.date_created`;
- удаляет неиспользуемые таблицы `product_info` и `orders_date`;
- добавляет отсутствовавшие первичные ключи на `product.id` и `orders.id` (identity колонки из `V001` primary key не создают);
- добавляет внешние ключи из `order_product.product_id` в `product.id` и из `order_product.order_id` в `orders.id`.

## Миграция V003__insert_data.sql

Миграция `V003__insert_data.sql` заполняет таблицы `product`, `orders` и `order_product` данными:
- товары вставляются сразу с ценой в `product.price`;
- заказы вставляются сразу с датой в `orders.date_created`;
- состав заказов вставляется в `order_product`;
- sequence для identity-колонок `product.id` и `orders.id` обновляются после вставки явных идентификаторов, чтобы последующие вставки с `DEFAULT` не конфликтовали по id.

## Запрос для отображения какое количество сосисок было продано за последние 7 дней:

```sql
SELECT o.date_created,
       SUM(op.quantity)
FROM orders AS o
JOIN order_product AS op ON o.id = op.order_id
WHERE o.status = 'shipped'
  AND o.date_created > NOW() - INTERVAL '7 DAY'
GROUP BY o.date_created
ORDER BY o.date_created;
```

Результат выполнения

```text
 date_created |  sum   
--------------+--------
 2026-06-18   | 946845
 2026-06-19   | 942823
 2026-06-20   | 943287
 2026-06-21   | 945231
 2026-06-22   | 941353
 2026-06-23   | 946523
 2026-06-24   | 622772
(7 rows)

Time: 1921.365 ms (00:01.921)
```

## Индексы для оптимизации запроса

Миграция `V004__create_index.sql` создаёт индексы:

```sql
CREATE INDEX order_product_order_id_idx ON order_product(order_id);

CREATE INDEX orders_status_date_idx ON orders(status, date_created);
```

- `orders_status_date_idx` на `orders(status, date_created)` — покрывает фильтр `orders.status = 'shipped'` и `orders.date_created > NOW() - INTERVAL '7 DAY'`; ведущий столбец `status` обслуживает условие равенства, `date_created` — последующий диапазон по дате;
- `order_product_order_id_idx` на `order_product(order_id)` — индекс по внешнему ключу `order_product.order_id` (PostgreSQL индекс на FK автоматически не создаёт); полезен для точечных выборок состава конкретного заказа.

Результат выполнения того же запроса после создания индексов (установившееся значение на прогретом кэше):
 
```text
 date_created |  sum   
--------------+--------
 2026-06-18   | 946845
 2026-06-19   | 942823
 2026-06-20   | 943287
 2026-06-21   | 945231
 2026-06-22   | 941353
 2026-06-23   | 946523
 2026-06-24   | 622772
(7 rows)
 
Time: 1372.689 ms (00:01.373)
```
 
После создания индексов время запроса снижается с ~1921 мс (последовательное сканирование `orders`) до ~1370 мс на прогретом кэше. План (`EXPLAIN (ANALYZE, BUFFERS)`) показывает, что выборка отгруженных заказов за неделю теперь идёт через индекс:
 
```text
Parallel Bitmap Heap Scan on orders o   (rows=82183)
  Recheck Cond: status = 'shipped' AND date_created > now() - '7 days'
  ->  Bitmap Index Scan on orders_status_date_idx   (rows=246550)
        Index Cond: status = 'shipped' AND date_created > now() - '7 days'
...
Parallel Hash Join (Hash Cond: op.order_id = o.id)
  ->  Parallel Seq Scan on order_product op
```
 
То есть `orders_status_date_idx` задействован (Bitmap Index Scan) — это и даёт основной выигрыш, заменяя последовательное сканирование 10 млн строк `orders` на чтение ~246k подходящих. Соединение с `order_product` планировщик выполняет через Hash Join с параллельным последовательным сканированием: при текущих объёмах (после фильтра остаётся ~246k заказов) и стоимостной модели по умолчанию это дешевле, чем nested loop с индексными обращениями, поэтому `order_product_order_id_idx` данным запросом не используется. Индекс по внешнему ключу при этом остаётся обоснованным: он ускоряет точечные выборки по конкретному заказу.
 
Первый запрос сразу после создания индексов выполнялся ~12.3 с — это эффект холодного кэша (страницы heap и новых индексов читаются с диска); начиная со второго прогона время выходит на установившиеся за несколько запросов ~1300–1640 мс.
