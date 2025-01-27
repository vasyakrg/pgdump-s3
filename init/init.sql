-- Создание таблицы клиентов
CREATE TABLE customers (
    id SERIAL PRIMARY KEY,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    email VARCHAR(100),
    phone VARCHAR(20),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Создание таблицы заказов
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    customer_id INTEGER REFERENCES customers(id),
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    total_amount DECIMAL(10,2),
    status VARCHAR(20),
    shipping_address TEXT
);

-- Функция для генерации случайного телефона
CREATE OR REPLACE FUNCTION random_phone() RETURNS VARCHAR AS $$
BEGIN
    RETURN '+7' ||
           LPAD(FLOOR(RANDOM() * 999)::TEXT, 3, '0') ||
           LPAD(FLOOR(RANDOM() * 999)::TEXT, 3, '0') ||
           LPAD(FLOOR(RANDOM() * 9999)::TEXT, 4, '0');
END;
$$ LANGUAGE plpgsql;

-- Функция для генерации случайного email
CREATE OR REPLACE FUNCTION random_email(first_name VARCHAR, last_name VARCHAR) RETURNS VARCHAR AS $$
BEGIN
    RETURN LOWER(first_name || '.' || last_name || '@' ||
           CASE (RANDOM() * 3)::INTEGER
               WHEN 0 THEN 'gmail.com'
               WHEN 1 THEN 'yahoo.com'
               ELSE 'hotmail.com'
           END);
END;
$$ LANGUAGE plpgsql;

-- Заполнение таблицы customers
INSERT INTO customers (first_name, last_name, email, phone)
SELECT
    (ARRAY['John', 'Jane', 'Michael', 'Emma', 'William', 'Olivia', 'James', 'Sophia', 'Alexander', 'Isabella'])[floor(random() * 10 + 1)] as first_name,
    (ARRAY['Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia', 'Miller', 'Davis', 'Rodriguez', 'Martinez'])[floor(random() * 10 + 1)] as last_name,
    'placeholder' as email,
    random_phone() as phone
FROM generate_series(1, 1000);

-- Обновление email на основе имени и фамилии
UPDATE customers
SET email = random_email(first_name, last_name);

-- Заполнение таблицы orders
INSERT INTO orders (customer_id, order_date, total_amount, status, shipping_address)
SELECT
    floor(random() * 1000 + 1)::integer as customer_id,
    CURRENT_TIMESTAMP - (random() * interval '365 days') as order_date,
    (random() * 10000)::decimal(10,2) as total_amount,
    (ARRAY['pending', 'processing', 'shipped', 'delivered', 'cancelled'])[floor(random() * 5 + 1)] as status,
    (ARRAY[
        '123 Main St, New York, NY 10001',
        '456 Oak Ave, Los Angeles, CA 90001',
        '789 Pine Rd, Chicago, IL 60601',
        '321 Maple Dr, Houston, TX 77001',
        '654 Cedar Ln, Miami, FL 33101'
    ])[floor(random() * 5 + 1)] as shipping_address
FROM generate_series(1, 1000);

-- Создание индексов для оптимизации
CREATE INDEX idx_customers_email ON customers(email);
CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_order_date ON orders(order_date);
