.PHONY: test up down logs backup

test:
	./scripts/test-api.sh

up:
	docker compose up -d --build

down:
	docker compose down

logs:
	docker compose logs -f --tail=100

backup:
	./scripts/backup.sh
