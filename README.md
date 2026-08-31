# Gestão IM360

Sistema de gestão pedagógica e de material didático — substitui a planilha "Gestão Interativo".
Flutter (web + Android + iOS) · Supabase (Postgres, Auth, RLS) · Cloudflare Pages · Sentry.

- Contexto para sessões do Claude Code: [`CLAUDE.md`](CLAUDE.md)
- Guia de continuidade e decisões: [`docs/README-continuidade.md`](docs/README-continuidade.md) + página "Decisões vigentes" no Notion (fonte da verdade)
- Roadmap: board "Gestão Interativo — Roadmap de Construção" no Notion

## Ambientes

| Ambiente | Projeto Supabase | Branch |
|---|---|---|
| dev | `ncdfolxdupbbfvtydngx` (GestaoIM360DevDB) | `develop` |
| prod | `aqfuawrygxsiopyppjza` (GestaoIM360ProdDB) | `main` |

Migrações são aplicadas **somente pelo CI/CD** (`.github/workflows/db-migrations.yml`), a partir de `supabase/migrations/`.

## Setup (uma vez)

1. Secrets no GitHub (Settings → Secrets and variables → Actions): `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD_DEV`, `SUPABASE_DB_PASSWORD_PROD`.
2. Criar a branch `develop` a partir de `main`.
3. (Opcional, recomendado) Ambientes `dev` e `prod` no GitHub com proteção de aprovação para `prod`.
4. Local: `supabase init` se o CLI reclamar do `supabase/config.toml` mínimo deste bootstrap.
