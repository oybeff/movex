.PHONY: help install run stop migrate migrate-create migrate-downgrade backup restore health format lint test clean

# Default target
help:
	@echo "Movex GO - Available commands:"
	@echo ""
	@echo "Development:"
	@echo "  make install        - Install dependencies"
	@echo "  make run            - Run app locally"
	@echo "  make stop           - Stop running app"
	@echo ""
	@echo "Database:"
	@echo "  make migrate        - Run database migrations"
	@echo "  make migrate-create - Create new migration"
	@echo "  make migrate-downgrade - Rollback last migration"
	@echo "  make backup         - Backup database"
	@echo "  make restore        - Restore database"
	@echo ""
	@echo "Code Quality:"
	@echo "  make format         - Format code"
	@echo "  make lint           - Lint code"
	@echo "  make test           - Run tests"
	@echo ""
	@echo "Utilities:"
	@echo "  make health         - Check service health"
	@echo "  make clean          - Clean up"

# Development
install:
	pip install -r requirements.txt

run:
	uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

stop:
	@pkill -f "uvicorn app.main:app" || echo "No running process found"

# Database commands
migrate:
	alembic upgrade head

migrate-create:
	@read -p "Enter migration message: " msg; \
	alembic revision --autogenerate -m "$$msg"

migrate-downgrade:
	alembic downgrade -1

# Backup and restore
backup:
	@mkdir -p backups
	@echo "Creating backup..."
	@pg_dump -U $${POSTGRES_USER:-postgres} $${POSTGRES_DB:-movex_go} > backups/backup_$$(date +%Y%m%d_%H%M%S).sql
	@echo "Backup created in backups/ directory"

restore:
	@read -p "Enter backup file name: " file; \
	psql -U $${POSTGRES_USER:-postgres} $${POSTGRES_DB:-movex_go} < backups/$$file

# Code Quality
format:
	black app/
	isort app/

lint:
	flake8 app/
	mypy app/

test:
	pytest tests/ -v

# Utilities
health:
	@curl -s http://localhost:8000/health | python -m json.tool

clean:
	find . -type d -name "__pycache__" -exec rm -rf {} +
	find . -type f -name "*.pyc" -delete
	find . -type f -name "*.pyo" -delete
	find . -type f -name "*.coverage" -delete
	find . -type d -name "*.egg-info" -exec rm -rf {} +
	find . -type d -name ".pytest_cache" -exec rm -rf {} +
	find . -type d -name ".mypy_cache" -exec rm -rf {} +

