#!/usr/bin/env bash
# Настройка Metabase через API: администратор, подключение к базе, четыре
# карточки и дашборд. Нужен, чтобы дашборд воспроизводился у любого, кто
# склонировал репозиторий, а не существовал только на машине автора.
#
# Идемпотентность: если Metabase уже настроен, скрипт не падает, а сообщает
# об этом и выходит. Повторный запуск не создаёт второй дашборд.
set -euo pipefail

# Учётные данные стенда. В репозитории их нет и быть не может: он
# публичный, и записанный здесь пароль — это пароль, выложенный в
# интернет, сколько бы раз он ни был «от локального контейнера».
#
# Но обещание «склонировал и запустил» ломать тоже не хочется, а
# требовать пароль руками — значит его сломать. Поэтому пароль не
# спрашивается, а заводится сам: при первой настройке генерируется
# случайный и дописывается в .env, который не отслеживается. Дальше
# скрипт читает его оттуда, и повторный запуск входит той же учёткой.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$REPO/.env"
if [ -f "$ENV_FILE" ]; then
    set -a; . "$ENV_FILE"; set +a
fi

MB=${MB_URL:-http://localhost:3000}
EMAIL=${MB_EMAIL:-analyst@moex.local}

if [ -z "${MB_PASSWORD:-}" ]; then
    # Случайные знаки, а не слово: Metabase отвергает короткие и словарные
    # пароли. Только буквы и цифры — пароль идёт и в .env, и в JSON, и
    # экранирование было бы лишним способом отстрелить себе ногу.
    # `|| true` против SIGPIPE: при set -o pipefail обрыв tr со стороны
    # head уронил бы весь скрипт.
    MB_PASSWORD=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 28 || true)
    printf '\n# Пароль Metabase, создан при первой настройке\nMB_PASSWORD=%s\n' \
        "$MB_PASSWORD" >> "$ENV_FILE"
    echo "Пароль Metabase создан и записан в .env"
fi
PASSWORD=$MB_PASSWORD

echo "Жду, пока Metabase поднимется..."
until [ "$(curl -s -o /dev/null -w '%{http_code}' "$MB/api/health")" = "200" ]; do sleep 3; done

# Признак «Metabase ещё не настроен» — has-user-setup, а НЕ наличие
# setup-token: токен остаётся в ответе и после первичной настройки, и по
# нему нельзя отличить свежую установку от уже настроенной.
PROPS=$(curl -s "$MB/api/session/properties")
HAS_USER=$(echo "$PROPS" | jq -r '.["has-user-setup"]')
SETUP_TOKEN=$(echo "$PROPS" | jq -r '.["setup-token"] // empty')

if [ "$HAS_USER" != "true" ]; then
    echo "Первичная настройка: создаю администратора"
    curl -s -X POST "$MB/api/setup" -H 'Content-Type: application/json' -d "{
        \"token\": \"$SETUP_TOKEN\",
        \"user\": {\"first_name\":\"MOEX\",\"last_name\":\"Analytics\",
                   \"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",
                   \"site_name\":\"Витрина МосБиржи\"},
        \"prefs\": {\"site_name\":\"Витрина МосБиржи\",\"allow_tracking\":false}
    }" > /dev/null
else
    echo "Metabase уже настроен, вхожу существующим пользователем"
fi

SESSION=$(curl -s -X POST "$MB/api/session" -H 'Content-Type: application/json' \
          -d "{\"username\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" | jq -r .id)
auth=(-H "X-Metabase-Session: $SESSION")

# --- подключение к базе -----------------------------------------------------
DB_ID=$(curl -s "${auth[@]}" "$MB/api/database" | jq -r '.data[] | select(.name=="MOEX") | .id' | head -1)
if [ -z "$DB_ID" ]; then
    echo "Подключаю базу MOEX"
    # Учётка базы берётся из .env, а не зашивается. Раньше здесь стояло
    # moex/moex строкой, и смена POSTGRES_PASSWORD молча ломала
    # подключение: контейнер поднимался с новым паролем, а Metabase
    # продолжал ходить со старым.
    DB_ID=$(curl -s -X POST "$MB/api/database" "${auth[@]}" -H 'Content-Type: application/json' -d "{
        \"engine\":\"postgres\",\"name\":\"MOEX\",
        \"details\":{\"host\":\"postgres\",\"port\":5432,
                   \"dbname\":\"${POSTGRES_DB:-moex}\",
                   \"user\":\"${POSTGRES_USER:-moex}\",
                   \"password\":\"${POSTGRES_PASSWORD:-moex}\",
                   \"ssl\":false,\"schema-filters-type\":\"inclusion\",
                   \"schema-filters-patterns\":\"core,marts\"},
        \"is_full_sync\":true}" | jq -r .id)
    curl -s -X POST "${auth[@]}" "$MB/api/database/$DB_ID/sync_schema" > /dev/null
    echo "Жду синхронизации схемы..."
    until [ "$(curl -s "${auth[@]}" "$MB/api/database/$DB_ID/metadata" | jq '.tables | length')" -gt 5 ]; do sleep 3; done
else
    echo "База MOEX уже подключена (id=$DB_ID)"
fi

# --- дашборд ----------------------------------------------------------------
DASH_NAME="Витрина российского фондового рынка"
EXISTING=$(curl -s "${auth[@]}" "$MB/api/dashboard" | jq -r ".[] | select(.name==\"$DASH_NAME\") | .id" | head -1)
if [ -n "$EXISTING" ]; then
    echo "Дашборд уже существует: $MB/dashboard/$EXISTING"
    exit 0
fi

mk_card () {  # имя, описание, тип, SQL, visualization_settings
    curl -s -X POST "$MB/api/card" "${auth[@]}" -H 'Content-Type: application/json' -d "$(jq -n \
        --arg name "$1" --arg desc "$2" --arg display "$3" --arg q "$4" \
        --argjson vs "$5" --argjson db "$DB_ID" \
        '{name:$name, description:$desc, display:$display, database_id:$db,
          dataset_query:{type:"native", database:$db, native:{query:$q}},
          visualization_settings:$vs}')" | jq -r .id
}

C1=$(mk_card "Динамика рынка: с дивидендами и без" \
 "IMOEX — ценовой индекс, MCFTR — полной доходности. Расхождение между линиями и есть вклад дивидендов." \
 "line" \
 "with nedeli as (select index_id, date_trunc('week', trade_date)::date as nedelya, max(trade_date) as posledniy_den from core.index_quote where index_id in ('IMOEX','MCFTR') group by 1,2), tochki as (select n.index_id, n.nedelya, q.close from nedeli n join core.index_quote q on q.index_id=n.index_id and q.trade_date=n.posledniy_den) select nedelya as \"Дата\", case index_id when 'IMOEX' then 'Без дивидендов (IMOEX)' else 'С дивидендами (MCFTR)' end as \"Индекс\", round((close / first_value(close) over (partition by index_id order by nedelya) - 1) * 100, 1) as \"Доходность, %\" from tochki order by nedelya" \
 '{"graph.dimensions":["Дата","Индекс"],"graph.metrics":["Доходность, %"],"graph.y_axis.title_text":"Доходность с начала периода, %","graph.x_axis.title_text":""}')

# Вертикальные бары, а не горизонтальные: row chart в Metabase схлопывает
# всё после восьмой категории в синтетическую строку «Other», суммируя
# значения. На топ-10 это давало несуществующую бумагу с суммой двух
# последних. Настройками graph.max_categories не обходится.
C2=$(mk_card "Топ-10 бумаг по доходности" \
 "Период 03.01.2022 — 15.09.2026. Цены скорректированы на дробления акций. БСП — выброс: рост втрое сильнее следующей бумаги." "bar" \
 "select shortname as \"Бумага\", round((dohodnost_total*100)::numeric,1) as \"Доходность, %\" from marts.mv_security_stats order by dohodnost_total desc limit 10" \
 '{"graph.dimensions":["Бумага"],"graph.metrics":["Доходность, %"],"graph.y_axis.title_text":"Доходность за период, %","graph.x_axis.title_text":"","graph.show_values":true,"series_settings":{"Доходность, %":{"color":"#2a78d6"}}}')

# Без размера пузыря: он кодировал оборот, но легенды для размера Metabase
# не рисует, поэтому читатель видел точки разного размера без объяснения.
C3=$(mk_card "Доходность против волатильности" \
 "Период 03.01.2022 — 15.09.2026. Каждая точка — бумага индекса МосБиржи." "scatter" \
 "select round((volatilnost_god*100)::numeric,1) as \"Волатильность, % годовых\", round((dohodnost_total*100)::numeric,1) as \"Доходность, %\", shortname as \"Бумага\" from marts.mv_security_stats where volatilnost_god is not null" \
 '{"graph.dimensions":["Волатильность, % годовых"],"graph.metrics":["Доходность, %"],"graph.x_axis.title_text":"Волатильность, % годовых","graph.y_axis.title_text":"Доходность за период, %","series_settings":{"Доходность, %":{"color":"#2a78d6"}}}')

C4=$(mk_card "Беты к индексу МосБиржи" "Две независимые оценки беты: ковариационная и регрессионная" "table" \
 "select shortname as \"Бумага\", sector_name as \"Сектор\", round(beta_cov::numeric,3) as \"Бета (cov/var)\", round(beta_regr::numeric,3) as \"Бета (regr_slope)\", round(r2::numeric,3) as \"R²\", round((volatilnost_god*100)::numeric,1) as \"Волатильность, %\", round((max_prosadka*100)::numeric,1) as \"Макс. просадка, %\" from marts.mv_security_stats order by beta_cov desc" \
 '{}')

DASH=$(curl -s -X POST "$MB/api/dashboard" "${auth[@]}" -H 'Content-Type: application/json' \
       -d "{\"name\":\"$DASH_NAME\",\"description\":\"Данные Московской биржи, 2022-2026. Вся аналитика — в SQL.\"}" | jq -r .id)

curl -s -X PUT "$MB/api/dashboard/$DASH" "${auth[@]}" -H 'Content-Type: application/json' -d "{
  \"dashcards\":[
    {\"id\":-1,\"card_id\":$C1,\"row\":0,\"col\":0,\"size_x\":24,\"size_y\":6,\"parameter_mappings\":[]},
    {\"id\":-2,\"card_id\":$C2,\"row\":6,\"col\":0,\"size_x\":12,\"size_y\":6,\"parameter_mappings\":[]},
    {\"id\":-3,\"card_id\":$C3,\"row\":6,\"col\":12,\"size_x\":12,\"size_y\":6,\"parameter_mappings\":[]},
    {\"id\":-4,\"card_id\":$C4,\"row\":12,\"col\":0,\"size_x\":24,\"size_y\":8,\"parameter_mappings\":[]}
  ]}" > /dev/null

echo "Готово. Дашборд: $MB/dashboard/$DASH"
echo "Вход: $EMAIL, пароль в .env (MB_PASSWORD)"
