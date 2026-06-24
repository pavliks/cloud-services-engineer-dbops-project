-- Оптимизация схемы: слияние таблиц 1:1, добавление PK и FK

ALTER TABLE product ADD COLUMN price double precision;
-- переносим цену из product_info перед удалением таблицы
UPDATE product AS p
SET price = pi.price
FROM product_info AS pi
WHERE pi.product_id = p.id;

ALTER TABLE orders ADD COLUMN date_created date DEFAULT CURRENT_DATE;

UPDATE orders AS o
SET date_created = od.date_created
FROM orders_date AS od
WHERE od.order_id = o.id;

DROP TABLE product_info;

DROP TABLE orders_date;

-- identity-колонки из V001 первичный ключ не создают, добавляем явно
ALTER TABLE product ADD CONSTRAINT product_pk PRIMARY KEY (id);

ALTER TABLE orders ADD CONSTRAINT orders_pk PRIMARY KEY (id);

ALTER TABLE order_product 
  ADD CONSTRAINT order_product_product_fk FOREIGN KEY (product_id) REFERENCES product(id), 
  ADD CONSTRAINT order_product_order_fk FOREIGN KEY (order_id) REFERENCES orders(id);
