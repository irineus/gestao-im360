# Política de credenciais dos PCs

Card **2.9** da Fase 2 (Planejamento e Design) — último card da fase. Fecha a pendência que o plano
deixou aberta em duas seções (§5.4, "e-mail/credenciais em campo criptografado ou fora do sistema"
e o risco "credenciais de PCs armazenadas no sistema") e que o DDL do card 2.1 marcou no próprio
schema, com `pc.credencial_ref text` e o comentário *"política definitiva: card 2.9"*.

Escopo deliberadamente pequeno: **a credencial é um atributo complementar do PC** (decisão de Irineu,
01/09/2026). O que segue é a política e o mínimo de mecanismo que a sustenta — não um subsistema de
gestão de segredos.

## 1. Decisões desta tarefa

1. **A senha fica no sistema, cifrada no Supabase Vault** — não num cofre externo. Decisão de Irineu
   (01/09/2026): *"pode criar um campo cifrado no supabase que será vinculado a cada computador"*.
2. **Acesso só para monitor e gerência** (Irineu, mesma data). Uma permissão nova,
   `salas.acessar_credencial`, marcada na matriz inicial para **direção** e **monitor**; secretaria e
   pedagógico ficam de fora, mesmo cadastrando PC.
3. **O par inteiro (usuário + senha) é o segredo**, guardado como um `jsonb` num único registro do
   Vault. `pc` guarda apenas o ponteiro. Não há coluna de e-mail em texto claro — assim a restrição
   é de tabela e função, e não de coluna: o card 2.4 já decidiu que **RLS não é por coluna**, e um
   `credencial_usuario` em claro seria legível por qualquer um com `salas.ler` via PostgREST.
4. **Ler é um ato registrado.** `fn_pc_credencial_ler` grava a linha em `pc_credencial_acesso`
   **antes** de devolver a senha, na mesma transação e sem `exception`: se o registro falha, a
   leitura falha. Log como pré-condição, não como efeito colateral — é o que o plano pede como
   mitigação do risco e o único controle que sobrevive ao fato de três pessoas terem a permissão.
5. **A planilha queimou as senhas atuais.** A aba `PCS` guarda e-mail/senha em texto puro num arquivo
   que já circulou por e-mail e nuvem. Nenhuma senha é migrada: na virada, as contas são **rotacionadas
   nas máquinas** e digitadas no sistema uma vez. A migração importa o PC, nunca a credencial.

## 2. O que é a credencial — e por que a recomendação do plano se inverteu

Irineu confirmou (01/09/2026) que o par e-mail/senha da aba `PCS` é o **login da máquina
(Google/Microsoft)** de cada PC do laboratório, e que **quem consulta é o monitor, no laboratório,
com frequência**.

O plano recomendava *não armazenar* — e essa continua sendo a recomendação correta quando a senha é
consultada duas vezes por ano por quem está sentado na secretaria. Com consulta frequente por quem
está de pé na sala, com o celular na mão, um cofre externo não é uma barreira: é um desvio. Ele seria
contornado da forma previsível — a senha volta para um papel colado no monitor, para o WhatsApp do
grupo, ou para a planilha de novo. **A alternativa real ao campo cifrado não é o cofre externo; é a
senha em texto puro fora de qualquer controle.**

O que a cifra compra, concretamente:

- o `pg_dump` semanal para o R2 (card 3.11) carrega **texto cifrado**; a chave é gerenciada pela
  plataforma, fora do banco;
- nenhuma tela, nenhuma view e nenhum `select` pelo PostgREST devolve a senha — só a função;
- quem lê fica registrado, e a permissão se tira com um clique na tela de Administração.

O que ela **não** compra, e é honesto dizer: quem tem acesso ao projeto Supabase (dono do banco)
consegue decifrar. A cifra protege o backup, o app e o vazamento por RLS — não o administrador.

## 3. Onde o segredo vive

Extensão `supabase_vault`, já disponível nos projetos Supabase. O schema `vault` **não** está entre os
*exposed schemas* do PostgREST — o app nunca o alcança, mesmo com "Automatically expose new tables"
ligado (pendência técnica 3).

O que muda no DDL do card 2.1 (aplicado no card **4.3**, que cria `pc`):

```sql
-- Substitui a coluna reservada `credencial_ref text` do card 2.1.
alter table public.pc
  drop column credencial_ref,
  add column credencial_secret_id uuid,          -- id do segredo em vault.secrets
  add column credencial_em        timestamptz,   -- quando a senha foi gravada/rotacionada
  add column credencial_por       uuid;          -- quem gravou
```

Sem chave estrangeira para `vault.secrets`: é tabela gerenciada pela plataforma, e uma FK para outro
schema administrado por fora é acoplamento que quebra em atualização do Supabase. O órfão é evitado
por trigger (§7).

O segredo é um `jsonb` com duas chaves:

```json
{"usuario": "pc03@escola.exemplo", "senha": "…"}
```

## 4. As duas funções

Ambas `security definer` com `search_path` fixo — entram na **lista fechada** do teste C8 (card 2.8).
Como `definer` ignora a RLS de `pc`, as duas filtram `unidade_id = fn_unidade_atual()` **no corpo**:
é exatamente a lição que o card 2.3 tirou de `fn_capacidade_efetiva`.

```sql
-- Gravar / rotacionar / limpar. p_senha nula apaga a credencial.
create or replace function public.fn_pc_credencial_gravar(
  p_pc_id uuid, p_usuario text, p_senha text
) returns void
language plpgsql
security definer
set search_path = public, vault, pg_temp
as $$
declare v_pc public.pc;
begin
  perform public.fn_exige_permissao('salas.acessar_credencial');

  select * into v_pc from public.pc
   where id = p_pc_id and unidade_id = public.fn_unidade_atual()
   for update;
  if not found then
    raise exception 'PC não encontrado' using errcode = 'PT404', detail = 'PC_INEXISTENTE';
  end if;

  if p_senha is null then
    if v_pc.credencial_secret_id is not null then
      delete from vault.secrets where id = v_pc.credencial_secret_id;
    end if;
    update public.pc set credencial_secret_id = null,
                         credencial_em = null, credencial_por = null
     where id = p_pc_id;
    return;
  end if;

  if v_pc.credencial_secret_id is null then
    update public.pc
       set credencial_secret_id = vault.create_secret(
             jsonb_build_object('usuario', p_usuario, 'senha', p_senha)::text,
             null, 'credencial do PC ' || v_pc.identificador),
           credencial_em = now(), credencial_por = auth.uid()
     where id = p_pc_id;
  else
    perform vault.update_secret(
      v_pc.credencial_secret_id,
      jsonb_build_object('usuario', p_usuario, 'senha', p_senha)::text);
    update public.pc set credencial_em = now(), credencial_por = auth.uid()
     where id = p_pc_id;
  end if;
end;
$$;

-- Ler. Registra o acesso antes de devolver.
create or replace function public.fn_pc_credencial_ler(p_pc_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, vault, pg_temp
as $$
declare v_pc public.pc; v_segredo text;
begin
  perform public.fn_exige_permissao('salas.acessar_credencial');

  select * into v_pc from public.pc
   where id = p_pc_id and unidade_id = public.fn_unidade_atual();
  if not found then
    raise exception 'PC não encontrado' using errcode = 'PT404', detail = 'PC_INEXISTENTE';
  end if;
  if v_pc.credencial_secret_id is null then
    return null;
  end if;

  -- Sem exception em volta: log que falha derruba a leitura, de propósito.
  insert into public.pc_credencial_acesso (unidade_id, pc_id)
  values (v_pc.unidade_id, v_pc.id);

  select decrypted_secret into v_segredo
    from vault.decrypted_secrets where id = v_pc.credencial_secret_id;
  return v_segredo::jsonb;
end;
$$;

revoke execute on function public.fn_pc_credencial_ler(uuid), public.fn_pc_credencial_gravar(uuid, text, text) from public;
grant  execute on function public.fn_pc_credencial_ler(uuid), public.fn_pc_credencial_gravar(uuid, text, text) to authenticated;
```

**Uma permissão só para ler e gravar**, e não duas: quem grava a senha está digitando a senha. Um
`salas.gravar_credencial` separado descreveria uma proteção que não existe.

`PC_INEXISTENTE` é o único código de erro novo deste card — vale tanto para PC inexistente quanto para
PC de outra unidade, que é o comportamento certo: quem não pode ver não descobre que existe.

## 5. Permissão nova e matriz inicial

Uma linha no catálogo do card 2.4, que passa de **49 para 50 códigos** (`salas` vai de 5 para 6):

| Código | Origem | O que autoriza |
|---|---|---|
| `salas.acessar_credencial` | 2.9 | `fn_pc_credencial_ler` e `fn_pc_credencial_gravar`; `select`/`insert` em `pc_credencial_acesso` |

| Código | direção | pedagógico | secretaria | monitor |
|---|:--:|:--:|:--:|:--:|
| `salas.acessar_credencial` | ✔ | | | ✔ |

Secretaria cadastra o PC (`salas.criar`/`salas.editar`) mas não vê nem grava a credencial — é o
recorte que Irineu pediu, e não há efeito colateral: nenhuma função de outro domínio lê credencial
dentro da transação de outro ator, que é a armadilha que o card 2.4 mapeou nas nove tabelas fora do
padrão.

## 6. Log de acesso

```sql
create table public.pc_credencial_acesso (
  id uuid primary key default gen_random_uuid(),
  unidade_id uuid not null references public.unidade(id),
  pc_id      uuid not null references public.pc(id) on delete cascade,
  criado_em  timestamptz not null default now(), criado_por uuid,
  atualizado_em timestamptz, atualizado_por uuid
);
```

Sem colunas próprias de "quem" e "quando": `criado_por`/`criado_em` da auditoria padrão já são
exatamente isso, e duplicar convidaria as duas a divergirem.

Políticas — fogem do padrão de quatro, e entram na lista fechada de ausências intencionais do teste
C4 (card 2.8), junto com `movimento_estoque` e `permissao`:

| Tabela | `select` | `insert` | `update` | `delete` |
|---|---|---|---|---|
| **`pc_credencial_acesso`** | `salas.acessar_credencial` | `salas.acessar_credencial` | — | — |

Log é imutável pela mesma razão que movimento de estoque é: registro que se apaga não é registro.
Quem tem a permissão pode, pelo PostgREST, inserir uma linha de acesso que não aconteceu — ruído,
não escapatória. O que importa é o inverso, e esse está fechado: **não há caminho que devolva a senha
sem gravar a linha**.

## 7. Trigger de limpeza

```sql
-- PC excluído (salas.excluir, só sem histórico) não deixa segredo órfão no Vault.
create or replace function public.tg_pc_credencial_apaga() returns trigger
language plpgsql security definer set search_path = public, vault, pg_temp as $$
begin
  if old.credencial_secret_id is not null then
    delete from vault.secrets where id = old.credencial_secret_id;
  end if;
  return old;
end; $$;
```

## 8. Na tela (card 4.5, tela 10 — Salas e PCs)

O card 2.6 decidiu não desenhar campo de credencial até esta política existir (§13 dos wireframes).
Agora existe, e é pouco:

- a ficha do PC mostra **"credencial cadastrada · atualizada em dd/mm/aaaa"** ou "sem credencial" —
  esse carimbo vem de `pc.credencial_em`, legível com `salas.ler`;
- o botão **"Ver credencial"** só aparece para quem tem `salas.acessar_credencial` (botão sem
  permissão é **ocultado** — decisão (b) do card 2.6) e abre um **diálogo** com usuário e senha, com
  "copiar" — resultado que muda a próxima ação vai em diálogo, nunca em *snackbar* (card 2.7 (f));
- **não existe listagem de credenciais**: uma por vez, a partir do PC. Um vazamento de tela é uma
  credencial, e o log significa alguma coisa;
- a senha **nunca** vai para estado persistente do app (`shared_preferences`), para log, nem para
  breadcrumb do Sentry (card 3.12);
- gravar/rotacionar é o mesmo diálogo, com os dois campos em branco — não se pré-carrega senha em
  formulário.

## 9. Migração (cards 9.1, 9.2 e 9.7)

- O extrator lê da aba `PCS` **identificador, sala e status**. A coluna de senha é **descartada na
  origem** — não entra no CSV intermediário, para não recriar o problema num arquivo novo.
- As senhas atuais são consideradas **queimadas**: circularam em texto puro. Na virada, as contas são
  rotacionadas nas máquinas e as novas digitadas no sistema, uma vez, por quem tem a permissão.
- O congelamento da planilha (card 9.7) inclui **limpar a coluna de senha da aba `PCS`** antes de
  arquivar. Planilha congelada com senha dentro é a mesma exposição, só que sem dono.

## 10. Testes que este card exige (card 2.8)

Catálogo (baratos, entram com a migração do card 4.3):

| # | Asserção |
|---|---|
| C14 | Nenhuma coluna de tabela do schema `public` tem nome casando com `senha\|password\|pwd\|secret` — exceto `credencial_secret_id` |
| C15 | `authenticated` não tem `usage` no schema `vault` nem `select` em `vault.decrypted_secrets` |
| — | C4 ganha `pc_credencial_acesso` (sem `update`/`delete`) na lista de ausências intencionais |
| — | C8 ganha `fn_pc_credencial_ler`, `fn_pc_credencial_gravar` e `tg_pc_credencial_apaga` na lista fechada de `security definer` |
| — | C12: `PC_INEXISTENTE` entra em `test/fixtures/codigos_erro.txt` (de 21 para 22 códigos) |

Comportamento (card 4.3/4.5):

1. usuário **sem** a permissão → `throws_ok` com `SEM_PERMISSAO` **e zero linhas** em
   `pc_credencial_acesso` (a segunda metade é a que importa);
2. usuário **com** a permissão → devolve o par gravado e cria **exatamente uma** linha de log;
3. usuário da **segunda unidade** da fixture → `PC_INEXISTENTE` para um PC da primeira;
4. `fn_pc_credencial_gravar(pc, u, null)` limpa a coluna **e** o registro no Vault.

## 11. Ajustes que este card exige

| # | Ajuste | Card | Bloqueante |
|---|---|---|:--:|
| 1 | `pc`: trocar `credencial_ref text` por `credencial_secret_id`/`credencial_em`/`credencial_por` | 4.3 | ✔ |
| 2 | Habilitar a extensão `supabase_vault` na migração e conferir que `vault` não está exposto no PostgREST | 3.3 | ✔ |
| 3 | `salas.acessar_credencial` no seed de permissões e na matriz (direção, monitor) | 3.6 | ✔ |
| 4 | Tabela `pc_credencial_acesso` com as políticas fora do padrão do §6 | 4.3 | ✔ |
| 5 | `PC_INEXISTENTE` no catálogo de erros do card 2.2 e no fixture de contrato | 2.2 / 3.7 | ✔ |
| 6 | C4, C8 e C12 atualizados; C14 e C15 criados | 3.4.5 / 3.9 | ✔ |
| 7 | Trigger `tg_pc_credencial_apaga` | 4.3 | |
| 8 | Ficha do PC com carimbo, botão e diálogo do §8 | 4.5 | |
| 9 | Extrator descarta a coluna de senha; planilha congelada sanitizada | 9.2 / 9.7 | |

## 12. O que fica em aberto

- **Verificar em dev, no card 4.3, que o dono das funções da migração enxerga
  `vault.decrypted_secrets`.** É o único ponto do desenho que depende de detalhe da plataforma. Se
  não enxergar, a saída não é construir criptografia própria: é voltar a `credencial_ref` apontando
  para cofre externo, com o custo de adoção descrito no §2 assumido explicitamente.
- **Rotação periódica não entra na v1.** Não há rotina, nem prazo, nem alerta de senha velha —
  `credencial_em` na tela é o suficiente para alguém reparar. Se virar necessidade, é card da Fase 11.
- **Recomendação à escola, fora do escopo do sistema:** que a conta de login de cada PC do laboratório
  não seja uma conta pessoal com e-mail e Drive vinculados. O sistema não tem como impor isso, e a
  política acima protege o registro da senha, não o alcance da conta.
