-- Отдельная база для внутренних настроек Metabase (дашборды, вопросы, пользователи).
-- Держим её рядом, но НЕ в базе moex: смешивать служебные таблицы BI-инструмента
-- с аналитическими данными — верный способ однажды снести чужое при очистке схемы.
-- CREATE DATABASE нельзя выполнить внутри транзакции, поэтому файл отдельный.
SELECT 'CREATE DATABASE metabase_app'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'metabase_app')
\gexec
