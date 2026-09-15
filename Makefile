.PHONY: up down schema etl checks marts explain psql logs clean

up:            ## поднять Postgres + Metabase
	docker compose up -d
	@echo "Postgres: localhost:$${POSTGRES_PORT:-5432}   Metabase: http://localhost:$${METABASE_PORT:-3000}"

down:
	docker compose down

schema:        ## применить DDL повторно (идемпотентно)
	@for f in sql/schema/0*.sql; do echo ">> $$f"; \
	  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U $${POSTGRES_USER:-moex} -d $${POSTGRES_DB:-moex} -f /docker-entrypoint-initdb.d/$$(basename $$f); done

etl:           ## загрузить данные MOEX -> staging -> core
	python -m etl.load

refresh:       ## то же, но подтягивает пересчитанные биржей строки (DO UPDATE)
	python -m etl.load --refresh

marts:         ## пересобрать материализованные представления
	docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U $${POSTGRES_USER:-moex} -d $${POSTGRES_DB:-moex} -c "select marts.refresh_all();"

checks:        ## проверки качества данных
	python -m etl.quality_checks

psql:
	docker compose exec postgres psql -U $${POSTGRES_USER:-moex} -d $${POSTGRES_DB:-moex}

logs:
	docker compose logs -f --tail=50

clean:         ## снести всё вместе с данными
	docker compose down -v

dashboard:     ## собрать дашборд в Metabase
	./scripts/setup_metabase.sh
