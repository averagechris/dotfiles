---
name: databricks-cli
description: |
  Quick reference for using the local Databricks CLI, especially for workspace,
  SQL-related resources, warehouses, queries, auth, and API access.
---

# Databricks CLI

Use this skill when working with the local `databricks` binary.

## Important clarification

- There is **no** top-level `databricks sql` subcommand in the current official
  Databricks CLI.
- SQL-related functionality is exposed through command groups such as:
  - `databricks queries`
  - `databricks query-history`
  - `databricks warehouses`
- `databricks psql` is for **Lakebase Postgres**, not generic Databricks SQL
  warehouse querying.
- `databricks-sql-connector` is a **Python library** (`from databricks import sql`),
  not a CLI plugin and does not add subcommands to `databricks`.

## Rules

- Prefer non-interactive commands.
- Prefer machine-readable output with `-o json` when possible.
- Use the CLI's native command groups instead of inventing a `sql` subcommand.
- Use `databricks api` as an escape hatch when the dedicated command group is
  missing a needed operation.

## Good defaults

```bash
databricks version
databricks auth profiles
databricks auth env
databricks current-user me -o json
databricks warehouses list -o json
databricks queries list -o json
databricks query-history list -o json
```

## Common command groups

```bash
# Authentication / identity
databricks auth login
databricks auth profiles
databricks auth describe
databricks current-user me -o json

# Workspace and files
databricks workspace list / -o json
databricks fs ls dbfs:/ -o json
databricks repos list -o json

# Warehouses
databricks warehouses list -o json
databricks warehouses get WAREHOUSE_ID -o json
databricks warehouses start WAREHOUSE_ID
databricks warehouses stop WAREHOUSE_ID

# Saved queries
databricks queries list -o json
databricks queries get QUERY_ID -o json
databricks queries create --json @query.json
databricks queries update QUERY_ID --json @query.json

# Query history
databricks query-history list -o json

# Generic REST API escape hatch
databricks api get /api/2.0/clusters/list
databricks api post /api/2.0/jobs/runs/submit --json @payload.json
```

## SQL-specific guidance

If an agent wants to "use Databricks SQL", choose the right interface:

1. **Manage SQL warehouses**
   - use `databricks warehouses ...`
2. **Manage saved queries / query definitions**
   - use `databricks queries ...`
3. **Inspect query execution history**
   - use `databricks query-history list`
4. **Connect to Lakebase Postgres**
   - use `databricks psql ...`
5. **Run arbitrary SQL from Python code**
   - use the `databricks-sql-connector` Python package, not the CLI

## Agent usage notes

- Prefer `-o json` for automation.
- Read command-specific help before assuming subcommands exist.
- For unsupported workflows, prefer `databricks api` over inventing new CLI
  syntax.
- If you need true SQL execution against a warehouse and the CLI command groups
  are insufficient, use Python with `from databricks import sql`.
