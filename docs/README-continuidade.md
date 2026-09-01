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
| `modelagem-dados-ddl.md` | DDL detalhado (33 tabelas, funções de infraestrutura, padrão de RLS) e mapa DDL → card das fases 3 a 8. **Fonte das migrações** | vigente |
| `identidade-visual.md` | Marca, paleta (com contrastes WCAG verificados), tipografia, badges de status e tokens Dart. **Fonte do design system (card 2.7)**. Arquivos em `assets/marca/` | vigente |
| `regra-virada-rep.md` | Card 2.5: critério objetivo da virada REP pontual → contínuo (débito × capacidade semanal × prazo), funções `fn_rep_situacao`/`fn_rep_avaliar_virada`/`fn_rep_virar_continuo`/`fn_rep_voltar_pontual`, pendências `REP_VIRADA` e os 8 ajustes que exige | vigente |
| `regras-negocio-funcoes.md` | Card 2.2: onde vive cada regra da seção 6 do plano (restrição, trigger, função de aplicação ou rotina `pg_cron`) e a assinatura de cada objeto; catálogo de erros, de pendências, ajustes que o DDL precisa receber e mapa função → card | vigente |
| `permissoes-matriz.md` | Card 2.4: catálogo de 49 permissões em 12 domínios, o que cada política de RLS exige tabela a tabela, matriz inicial dos 4 perfis, guardas das 13 rotas e o seed do card 3.6. **Fonte do catálogo de permissões** | vigente |
| `projecao-demanda.md` | Card 02.5 (Ordem 5): algoritmo da projeção de demanda de apostilas — cascata `MODULAR`/`RITMO_ALUNO`/`PREVISAO_CURSO`/`MEDIA_METODO`, `v_ritmo_aluno`, `v_projecao_aluno`, `rt_projecao_demanda`, snapshot mensal e critério objetivo de recalibração. **Fonte do algoritmo da projeção** | vigente |
| `views-leitura.md` | Card 2.3: SQL das views de leitura (estoque, demanda, pedido sugerido, vagas, dashboard, pendências), contrato da projeção, permissões de leitura por view e ajustes exigidos no DDL. **Fonte das views** | vigente |
| `wireframes.md` | Card 2.6: estrutura das 13 telas — shell responsivo, navegação (menu lateral / barra inferior do monitor), wireframe por tela com fontes de dados (views do 2.3), ações com permissões (2.4) e estados obrigatórios. **Fonte da estrutura das telas (entrada do card 2.7)** | vigente |
| `design-system.md` | Card 2.7: design system Flutter — tokens completos nos dois temas (badges do escuro definidos com contraste verificado), `ThemeData` Material 3, catálogo de componentes (`TabelaIm360`, badges, formulários, estados de tela), breakpoints como código e **textos finais de erro e estado vazio**. Apêndice com `lib/theme/` pronto para o card 3.7. **Fonte do design system aplicado** | vigente |
| `estrategia-testes.md` | Card 2.8: estratégia de testes (pgTAP + `supabase test db`), helpers que reproduzem o contexto do PostgREST, suíte de **catálogo** que transforma os ~35 ajustes acumulados dos cards 2.2–2.5 em asserção, obrigação de teste por tipo de card, mapa decisão → teste e **critérios de aceite dos 4 marcos**. **Fonte da estratégia de testes** | vigente |

A planilha original (`Gestão Interativo.xlsx`, snapshot 29/08/2026) está no projeto do Claude.ai, não neste repositório.

## Marcos até aqui

- 29–30/08/2026 — análise da planilha, 18 pontos de requisitos validados, plano v1.0.
- 30/08/2026 — board no Notion (11 fases) e página Decisões vigentes criados; plano v1.1 (Word) enviado ao dono do produto.
- 31/08/2026 — dono do produto respondeu as 9 questões do cap. 11; decisões técnicas fechadas com Irineu; projetos Supabase dev/prod criados; repositório inicializado com este bootstrap. Planilha de conferência de alunos sem turma entregue ao pedagógico (20 alunos + 2 códigos divergentes).
- 31/08/2026 — board reconciliado com as decisões já tomadas e **card 2.1 concluído**: DDL detalhado em `modelagem-dados-ddl.md`. Card 2.5 criado para o critério objetivo da virada REP pontual → contínuo.
- 01/09/2026 — **card 2.5 concluído**: critério objetivo da virada REP fechado em `regra-virada-rep.md`. Virada **sugerida** (pendência `REP_VIRADA`), nunca automática — virar contínuo cria alocação permanente e consome vaga toda semana. Prazo de 30 dias corridos por aula perdida, com quatro parâmetros novos (`rep_prazo_dias`, `rep_capacidade_semanal`, `rep_faltas_max`, `rep_janela_volta_dias`). Destrava as regras de admissão e lotação da Fase 5.
- 01/09/2026 — promoção `develop` → `main` (PR #7): as duas branches voltaram a ter conteúdo idêntico, sem nenhuma migração envolvida.
- 31/08/2026 — **card 1.9 concluído**: identidade visual fechada em `identidade-visual.md` + SVGs em `assets/marca/`. Paleta inspirada no Instituto Mix sem copiar (o sistema é de um franqueado, não é produto da franqueadora): laranja de marca, estrutura em grafite-azulado, vermelho reservado a erro. Destrava os cards 2.6 (wireframes) e 2.7 (design system).
- 01/09/2026 — **card 2.4 concluído**: catálogo de permissões e matriz inicial em `docs/permissoes-matriz.md`. 49 códigos `<dominio>.<acao>` em 12 domínios (15 do card 2.2, 9 do card 2.3, 25 novos); domínio no **plural**, fechando o ajuste #7 do card 2.3. Achado central: **várias escritas acontecem como efeito colateral dentro da transação de outro ator** — as funções do card 2.2 são `security invoker`, então a entrega do monitor escreve em `aluno_material`, `aluno_material_hist`, `certificado_checklist` e `pendencia`, e o padrão de quatro políticas do card 2.1 barraria todas. Nove tabelas ganham política fora do padrão, `movimento_estoque` ganha insert **por tipo** (senão o monitor lança ENTRADA pelo PostgREST) e `pendencia` fica sem exigência de domínio no insert. Doze achados no total, seis bloqueantes.
- 01/09/2026 — **card 2.3 concluído**: views de leitura especificadas em `docs/views-leitura.md`. Decisões estruturais: `security_invoker = on` em toda view, nenhuma `materialized view` (matview não respeita RLS), `fn_hoje()` no fuso de São Paulo em lugar de `current_date`, e `qtd_projetada` reservada como `0` em `v_pedido_sugerido` para a Fase 8 entrar por `create or replace`. Oito ajustes registrados para os cards de migração, dois deles bloqueantes.
- 01/09/2026 — **card 2.6 concluído**: wireframes das 13 telas em `docs/wireframes.md`. Estrutura, navegação e estados; desktop-first para secretaria, barra inferior mobile centrada nas três jornadas do monitor (registrar entrega, financeiro OK, manutenção de PC). Decisões transversais: botão sem permissão é ocultado (sem estado, desabilitado com motivo); a tela nunca pré-verifica regra em Dart — chama a função e reage aos status de retorno; central de pendências com ação contextual por tipo (`REP_VIRADA` executada de lá). Destrava o card 2.7 (design system).
- 01/09/2026 — **card 2.7 concluído**: design system Flutter em `docs/design-system.md`, fechando a cadeia identidade (1.9) → estrutura (2.6) → aplicação (2.7). Badges no tema escuro definidos (a lacuna do 1.9) com todos os pares AA verificados; `ColorScheme` montado à mão (nunca `fromSeed`); sistema plano com bordas; textos finais de erro (por `codigo`) e de estado vazio fechados para todas as telas. Destrava o card 3.7 (esqueleto Flutter, que copia `lib/theme/` do apêndice).
- 01/09/2026 — **card 02.5 (Ordem 5) concluído**: algoritmo da projeção de demanda especificado em `docs/projecao-demanda.md`, preenchendo o contrato que o card 2.3 deixou reservado. Cascata escolhida **por aluno**, nunca por item; a projeção começa no **segundo** item pendente da trilha (a parcela imediata é a primeira), sem o que todo aluno pesaria duas vezes no pedido sugerido; ritmo individual por média dos três intervalos mais recentes com piso de 7 e teto de 120 dias; previsão de conclusão vencida não serve de base; grão mensal mantido. Nove parâmetros novos, snapshot mensal (`demanda_projetada_hist`) para tornar a recalibração do card 11.2 uma medição, e o achado #4 do card 2.4 (`fn_param_int` como `security definer`) escalado a **bloqueante**.

- 01/09/2026 — **card 2.8 concluído**: estratégia de testes e critérios de aceite em `docs/estrategia-testes.md`. Escolhido **pgTAP** com `supabase test db` (o projeto testa muito mais estrutura e exceção do que resultado de `select`). Dois achados estruturais: (1) a maior parte dos ~35 "ajustes que o DDL precisa receber" acumulados nos cards 2.2–2.5 e Ordem 5 é da mesma família — valor gravado que o `check` recusa, ou permissão exigida que o seed não cria — e **falha em silêncio dentro do `exception` da rotina diária**, mas é toda verificável por **teste de catálogo** de dezenas de linhas; (2) teste de view não é "não dá erro", é **paridade de linhas entre perfis autorizados**, porque a RLS reduz em silêncio e a tela vazia mente. Sem meta percentual de cobertura: o portão é obrigação por tipo de card. Marco 3 teve divergência registrada — a planilha **não projeta demanda**, então metade do marco não é comparável e passa a ter critério próprio (reprodução por degrau, disjunção e banda de plausibilidade). Card **3.4.5** criado para os helpers e a escola-fixture.
## Decisões-chave (resumo — detalhe na página Decisões vigentes)

- Nome **Gestão IM360**; domínio `gestaoim360.com`; app id `com.gestaoim360.app` (cadastro nas lojas pendente — avisar Irineu na fase de Publicação). Identidade visual definida internamente em 31/08/2026 (card 1.9), sem depender do dono do produto.
- Ambientes: Supabase **dev** `ncdfolxdupbbfvtydngx` e **prod** `aqfuawrygxsiopyppjza` (sa-east-1). Migrações **somente via CI/CD** (`develop` → dev; `main` → prod).
- Entrega sem estoque: não bloqueia — entrega a próxima apostila da trilha com estoque, reordenando a trilha (registrado no histórico); se **nenhuma** tiver estoque, bloqueia e gera pendência de compra.
- Parâmetros iniciais: projeção 60 dias; alerta STANDBY 30 dias.
- REP híbrido: eventos pontuais com data enquanto der para repor tudo no prazo; senão o aluno vira REP contínuo na alocação. **Critério objetivo fechado em 01/09/2026 (card 2.5):** o aluno é sugerido para contínuo quando o débito de aulas em aberto não cabe mais na capacidade semanal de reposição até o prazo de 30 dias da aula mais antiga, ou quando falta duas vezes à própria reposição. A virada é sempre sugerida, nunca automática.
- Perfis direção/pedagógico/secretaria/monitor com matriz de permissões configurável; `tem_permissao()` + RLS.
- Sentry desde a Fase 0 (free tier), além dos logs do Supabase.

## Próximos passos (Fase 0)

1. Irineu: validar os secrets do workflow (`SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD_DEV`, `SUPABASE_DB_PASSWORD_PROD`) **antes** da migração do card 3.3 — o único run que o `db-migrations` já teve (bootstrap, 31/08) falhou. A branch `develop` já existe.
2. Primeira migração de schema em `supabase/migrations/`: `unidade`, `usuario`, `perfil`, `permissao`, `perfil_permissao`, `usuario_perfil`, `parametro`, função `tem_permissao(codigo)` e políticas de RLS — o que cada política exige está em `permissoes-matriz.md` §4, inclusive as nove tabelas que fogem do padrão de quatro políticas. Junto: `fn_hoje()` e os `default public.fn_hoje()` no lugar de `current_date` (card 2.3, §10).
3. Esqueleto Flutter (`flutter create` com org `com.gestaoim360`), login por e-mail/senha, deploy web no Cloudflare Pages.
4. Sentry no Flutter; Worker do Cloudflare para evitar pausa do free tier; backup semanal `pg_dump` → R2.
5. Antes da primeira migração valer: `supabase/seed.sql` com pgTAP + helpers `tests.*` + escola-fixture (card **3.4.5**) e o workflow `testes.yml` do card 3.9 — a suíte de catálogo do card 2.8 tem de estar verde desde a migração do 3.3.
6. Desabilitar "Automatically expose new tables" nos dois projetos Supabase (Settings → API) quando o schema começar a existir.

O sequenciamento oficial dessas tarefas está no board do Notion — use a skill `proxima-tarefa`.

## Convenções

Ver "Regras inegociáveis" no `CLAUDE.md`. Em resumo: regras de negócio no banco; RLS em tudo; português snake_case; `unidade_id` + auditoria em toda tabela; estoque imutável com estorno; credenciais nunca em texto puro.
