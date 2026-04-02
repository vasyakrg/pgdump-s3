-- Replace all email domains in customers table with ya.ru
UPDATE customers
SET email = CASE
    WHEN email LIKE '%@%' THEN CONCAT(SPLIT_PART(email, '@', 1), '@ya.ru')
    ELSE CONCAT(email, '@ya.ru')
END;
