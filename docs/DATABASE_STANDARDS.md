# Database Standards - Django ORM and PostgreSQL

## Models and schema
- Use Django models and PostgreSQL as the default persistence layer.
- Use consistent snake_case database names and meaningful Django model/field names.
- Define primary keys, foreign keys, uniqueness, check constraints, and appropriate indexes.
- Prefer database-enforced integrity to frontend-only checks.
- Use explicit `on_delete` behavior based on business rules.
- Store timezone-aware timestamps in UTC and format dates for display in the UI.

## Queries and transactions
- Use QuerySets rather than raw SQL unless justified and reviewed.
- Prevent N+1 queries using `select_related` and `prefetch_related`.
- Use `transaction.atomic()` for related writes that must succeed or fail together.
- Use `select_for_update()` or optimistic version checks when concurrency requires it.
- Avoid loading entire large tables into memory.

## Migration safety
- Use `makemigrations` to generate migrations and review their contents.
- Use `migrate` to apply approved migrations.
- Do not delete, reset, or rewrite production data without explicit approval and a recovery plan.
- Favor additive, backward-compatible migrations for deployed applications.
- Separate large data backfills from schema changes where practical.
- Verify rollback and backup strategy for high-risk changes.

## Deletion and audit
- Use archiving or soft deletion for business-critical records where appropriate.
- Preserve referential integrity and enforce access to archived data.
- Audit sensitive record changes with actor, timestamp, and relevant details without logging secrets.

## Review checklist
- [ ] Constraints and indexes fit access patterns
- [ ] Migration reviewed for destructive effects
- [ ] Transaction and concurrency risks handled
- [ ] Query performance and permission scope verified
