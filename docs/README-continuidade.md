# Gestão IM360 — guia de continuidade

Leia este documento e o `CLAUDE.md` da raiz ao iniciar qualquer sessão. Depois, leia a página Notion **Decisões vigentes** (`3cd2f3f4-b9b2-8106-95cd-fc8d937bd953`) — em conflito, ela vence estes documentos.

## Contexto em uma frase

O sistema **Gestão IM360** (Flutter + Supabase + Cloudflare) substituirá a planilha `Gestão Interativo.xlsx` na gestão de alunos, turmas, vagas e material didático de uma escola com três métodos de ensino (Interativo, Inglês e Modular). Concepção e plano aprovados; a Fase 0 (Fundação) está em andamento, com target de go-live em outubro/2026.

## Documentos deste diretório

| Documento | Conteúdo | Estado |
|---|---|---|
| `plano-projeto-sistema.md` | Plano v1.0: visão, escopo, permissões, arquitetura, modelo de dados, regras, telas, migração, fases, riscos. As decisões do cap. 11 foram respondidas em 31/08/2026 — ver Decisões vigentes | referência |
| `analise-planilha-entendimento.md` | Entendimento funcional da planilha, 18 dúvidas respondidas, mapa técnico de colunas | concluído |
| `script-extracao-planilha.md` | Protótipo Python (openpyxl) de extração da planilha — base da ferramenta de migração da fase 8/9 do board | protótipo |

A planilha original (`Gestão Interativo.xlsx`, snapshot 29/08/2026) está no projeto do Claude.ai, não neste repositório.

## Marcos até aqui

- 29–30/08/2026 — análise da planilha, 18 pontos de requisitos validados, plano v1.0.
- 30/08/2026 — board no Notion (11 fases) e página Decisões vigentes criados; plano v1.1 (Word) enviado ao dono do produto.
- 31/08/2026 — dono do produto respondeu as 9 questões do cap. 11; decisões técnicas fechadas com Irineu; projetos Supabase dev/prod criados; repositório inicializado com este bootstrap. Planilha de conferência de alunos sem turma entregue ao pedagógico (20 alunos + 2 códigos divergentes).

## Decisões-chave (resumo — detalhe na página Decisões vigentes)

- Nome **Gestão IM360**; domínio `gestaoim360.com`; app id `com.gestaoim360.app` (cadastro nas lojas pendente — avisar Irineu na fase de Publicação).
- Ambientes: Supabase **dev** `ncdfolxdupbbfvtydngx` e **prod** `aqfuawrygxsiopyppjza` (sa-east-1). Migrações **somente via CI/CD** (`develop` → dev; `main` → prod).
- Entrega sem estoque: não bloqueia — entrega a próxima apostila da trilha com estoque, reordenando a trilha (registrado no histórico); se **nenhuma** tiver estoque, bloqueia e gera pendência de compra.
- Parâmetros iniciais: projeção 60 dias; alerta STANDBY 30 dias.
- REP híbrido: eventos pontuais com data enquanto der para repor tudo no prazo; senão o aluno vira REP contínuo na alocação (critério objetivo da virada: definir na Fase 2 do plano).
- Perfis direção/pedagógico/secretaria/monitor com matriz de permissões configurável; `tem_permissao()` + RLS.
- Sentry desde a Fase 0 (free tier), além dos logs do Supabase.

## Próximos passos (Fase 0)

1. Irineu: configurar os secrets do workflow (`SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD_DEV`, `SUPABASE_DB_PASSWORD_PROD`) e criar a branch `develop`.
2. Primeira migração de schema em `supabase/migrations/`: `unidade`, `usuario`, `perfil`, `permissao`, `perfil_permissao`, `usuario_perfil`, `parametro`, função `tem_permissao(codigo)` e políticas de RLS.
3. Esqueleto Flutter (`flutter create` com org `com.gestaoim360`), login por e-mail/senha, deploy web no Cloudflare Pages.
4. Sentry no Flutter; Worker do Cloudflare para evitar pausa do free tier; backup semanal `pg_dump` → R2.
5. Desabilitar "Automatically expose new tables" nos dois projetos Supabase (Settings → API) quando o schema começar a existir.

O sequenciamento oficial dessas tarefas está no board do Notion — use a skill `proxima-tarefa`.

## Convenções

Ver "Regras inegociáveis" no `CLAUDE.md`. Em resumo: regras de negócio no banco; RLS em tudo; português snake_case; `unidade_id` + auditoria em toda tabela; estoque imutável com estorno; credenciais nunca em texto puro.
