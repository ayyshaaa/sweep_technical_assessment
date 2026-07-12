# Setup complet
setup:
	python3 -m venv venv
	./venv/bin/pip install -r requirements.txt

all: deps seed run docs

# Install dbt dependencies
deps:
	./venv/bin/dbt deps

# Load the seed data into the DuckDB database
seed:
	./venv/bin/dbt seed

# Run the dbt models and tests
run:
	./venv/bin/dbt run --select staging
	./venv/bin/dbt test --select staging
	./venv/bin/dbt run --select marts
	./venv/bin/dbt test --select marts

# Generate and serve the dbt documentation
docs:
	./venv/bin/dbt docs generate
	./venv/bin/dbt docs serve

# Run the dbt tests only
test:
	./venv/bin/dbt test

# Clean up the virtual environment and dbt artifacts
clean:
	./venv/bin/dbt clean
	rm -rf venv

.PHONY: setup all seed run docs test clean