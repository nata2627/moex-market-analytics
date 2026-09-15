-- Три слоя данных:
--   staging — сырые ответы API как пришли
--   core    — очищенные типизированные данные с ограничениями целостности
--   marts   — витрины для аналитики и дашборда
--
-- Разделение позволяет локализовать ошибку: битая цифра в staging означает
-- проблему источника, в core при верном staging — проблему перелива,
-- только в marts — проблему логики витрины.

CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS marts;

COMMENT ON SCHEMA staging IS 'Сырые ответы MOEX ISS как пришли, без типизации и ограничений';
COMMENT ON SCHEMA core    IS 'Очищенные типизированные данные с ограничениями целостности';
COMMENT ON SCHEMA marts   IS 'Витрины для анализа и дашборда';
