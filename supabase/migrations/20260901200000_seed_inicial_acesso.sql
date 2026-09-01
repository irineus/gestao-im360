-- =============================================================================
-- Card 3.6 — Seed inicial: unidade, perfis, catálogo de permissões, matriz,
--            parâmetros e o primeiro usuário de direção.
--
-- Fontes: docs/permissoes-matriz.md §3 (catálogo), §5 (matriz) e §8 (contrato do
--         seed); docs/regra-virada-rep.md §4 (quatro parâmetros rep_*);
--         docs/projecao-demanda.md §3 (nove da projeção);
--         docs/modelagem-dados-ddl.md §5 (horizonte e STANDBY).
--
-- ⚠️ ESTE SEED É MIGRAÇÃO, e não `supabase/seed.sql`. Ele precisa existir em
--    PRODUÇÃO: sem catálogo e sem matriz, `tem_permissao()` devolve falso para
--    todo mundo e o sistema inteiro fica vazio, sem erro nenhum. O
--    `supabase/seed.sql` é infraestrutura de teste e nunca sai do stack local
--    (card 2.8, ajuste 6).
--
-- Por que o corpo do seed vira FUNÇÃO em vez de `insert` solto: a escola-fixture
-- do card 3.4.5 precisa do MESMO catálogo e da MESMA matriz nas suas duas
-- unidades. Enquanto o seed real não existia, a fixture declarou um catálogo
-- mínimo próprio; a partir daqui isso seria uma segunda fonte da verdade ao lado
-- da real — e o teste de paridade do card 2.8 §6.3 compararia a tela contra a
-- matriz DE MENTIRA e passaria. Com o seed exposto como função idempotente que
-- recebe a unidade, migração e fixture chamam o mesmo código, e a divergência
-- deixa de ser possível em vez de ficar sob vigilância.
--
-- Idempotência, contrato do §8 do card 2.4:
--   * `permissao`      — `do update` em descrição/domínio/ativo. O catálogo é
--                        CÓDIGO: só muda por migração, e a tabela não tem
--                        política de escrita nenhuma.
--   * `perfil`         — `do nothing`. O nome é editável na tela.
--   * `perfil_permissao` — `do nothing` e SEM `delete`: reexecutar acrescenta o
--                        que faltar e NUNCA desfaz o que a direção marcou ou
--                        desmarcou na tela de Administração.
--   * `parametro`      — `do nothing`, pela mesma razão: valor ajustado pela
--                        escola não pode voltar ao default a cada deploy.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Catálogo de permissões — as 50 do card 2.4 §3 mais o card 2.9
-- -----------------------------------------------------------------------------
-- A descrição não é enfeite: é a coluna que a tela de Administração (card 4.7)
-- mostra ao lado da caixa de marcar. "estoque.ajustar" sozinho não diz a ninguém
-- o que acontece se a caixa for marcada.
create or replace function public.fn_seed_permissoes(p_unidade_id uuid)
returns integer
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_n integer;
begin
  insert into public.permissao (unidade_id, codigo, descricao, dominio)
  select p_unidade_id, c.codigo, c.descricao, split_part(c.codigo, '.', 1)
    from (values
      -- admin (3)
      ('admin.ler',                        'Ler usuário, perfil, permissão, matriz e atribuições'),
      ('admin.gerir_usuarios',             'Criar/editar usuário; atribuir e remover perfis'),
      ('admin.gerir_perfis',               'Criar/editar perfil; marcar e desmarcar a matriz'),
      -- unidades (2)
      ('unidades.ler',                     'Ler a unidade (nome no cabeçalho e seleção de unidade)'),
      ('unidades.gerir',                   'Criar/editar unidade'),
      -- parametros (2)
      ('parametros.ler',                   'Ler os parâmetros na tela de Administração'),
      ('parametros.gerir',                 'Criar/editar parâmetros da escola'),
      -- materiais (4)
      ('materiais.ler',                    'Ler método, material, curso, módulo, combo e composições'),
      ('materiais.criar',                  'Criar material, curso, módulo e combo'),
      ('materiais.editar',                 'Editar material, curso, módulo, combo e suas composições'),
      ('materiais.excluir',                'Excluir cadastro sem uso e linha de composição'),
      -- alunos (7)
      ('alunos.ler',                       'Ler aluno, histórico de status e trilha'),
      ('alunos.criar',                     'Matricular aluno'),
      ('alunos.editar',                    'Editar dados cadastrais, combo e previsão de conclusão'),
      ('alunos.alterar_status',            'Alterar o status do aluno nas transições normais'),
      ('alunos.reverter_status',           'Sair de FORMADO/CANCELADO (status terminal), com motivo'),
      ('alunos.formar_sem_certificado',    'Formar aluno sem certificado ENTREGUE no checklist'),
      ('alunos.editar_trilha',             'Reordenar, incluir e remover item da trilha do aluno'),
      -- salas (6, com o 50º código do card 2.9)
      ('salas.ler',                        'Ler sala, PC e manutenções'),
      ('salas.criar',                      'Cadastrar sala e PC'),
      ('salas.editar',                     'Editar sala e PC, inclusive o status do PC'),
      ('salas.excluir',                    'Excluir sala e PC sem histórico'),
      ('salas.registrar_manutencao',       'Abrir e fechar manutenção de PC (recalcula a capacidade)'),
      ('salas.acessar_credencial',         'Ler e gravar a credencial do PC (registrada em log)'),
      -- professores (3)
      ('professores.ler',                  'Ler professor (nome na grade semanal)'),
      ('professores.criar',                'Cadastrar professor'),
      ('professores.editar',               'Editar e inativar professor'),
      -- turmas (6)
      ('turmas.ler',                       'Ler blocos, alocações, reposições e turmas Modular'),
      ('turmas.criar',                     'Criar bloco de horário e turma Modular'),
      ('turmas.editar',                    'Editar bloco, cronograma e avanço de módulo'),
      ('turmas.excluir',                   'Excluir bloco e turma sem alocação'),
      ('turmas.alocar',                    'Adicionar e remover aluno de bloco/turma; lançar reposição'),
      ('turmas.lancar_reposicao_retroativa','Lançar reposição com data no passado'),
      -- estoque (4)
      ('estoque.ler',                      'Ler movimentos e saldo de estoque'),
      ('estoque.lancar_saida',             'Registrar entrega de apostila (saída de estoque)'),
      ('estoque.estornar',                 'Estornar entrega registrada'),
      ('estoque.ajustar',                  'Ajustar o saldo com motivo obrigatório'),
      -- compras (6)
      ('compras.ler',                      'Ler pedidos de compra e seus itens'),
      ('compras.criar',                    'Criar pedido em rascunho e seus itens'),
      ('compras.editar',                   'Editar itens do rascunho, enviar e cancelar pedido'),
      ('compras.excluir',                  'Remover item de pedido em rascunho'),
      ('compras.receber',                  'Receber pedido (gera entrada no estoque)'),
      ('compras.receber_excedente',        'Receber quantidade acima da pedida'),
      -- certificados (5)
      ('certificados.ler',                 'Ler o checklist de certificado'),
      ('certificados.criar',               'Abrir o checklist de certificado do aluno'),
      ('certificados.marcar_pedagogico',   'Marcar os itens pedagógico e formatura'),
      ('certificados.marcar_financeiro',   'Marcar o item financeiro OK'),
      ('certificados.alterar_status',      'Alterar o status do certificado (pedido, entregue)'),
      -- pendencias (2)
      ('pendencias.ler',                   'Ler a central de pendências'),
      ('pendencias.resolver',              'Resolver pendência com justificativa')
    ) as c(codigo, descricao)
  on conflict (unidade_id, codigo) do update
     set descricao = excluded.descricao,
         dominio   = excluded.dominio,
         ativo     = true;

  select count(*) into v_n from public.permissao where unidade_id = p_unidade_id;
  return v_n;
end $$;

comment on function public.fn_seed_permissoes(uuid) is
  'Catálogo de 50 permissões da unidade (card 2.4 §3 + card 2.9). Idempotente, com do update: o catálogo é código, não dado — permissao não tem política de escrita.';

-- -----------------------------------------------------------------------------
-- 2. Perfis — os quatro do plano
-- -----------------------------------------------------------------------------
create or replace function public.fn_seed_perfis(p_unidade_id uuid)
returns integer
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_n integer;
begin
  insert into public.perfil (unidade_id, codigo, nome)
  select p_unidade_id, p.codigo, p.nome
    from (values
      ('DIRECAO',    'Direção'),
      ('PEDAGOGICO', 'Pedagógico'),
      ('SECRETARIA', 'Secretaria'),
      ('MONITOR',    'Monitor')
    ) as p(codigo, nome)
  on conflict (unidade_id, codigo) do nothing;

  select count(*) into v_n from public.perfil where unidade_id = p_unidade_id;
  return v_n;
end $$;

comment on function public.fn_seed_perfis(uuid) is
  'Os quatro perfis do plano. do nothing: o nome é editável na tela de Administração (card 3.6).';

-- -----------------------------------------------------------------------------
-- 3. Matriz inicial perfil × permissão — docs/permissoes-matriz.md §5
-- -----------------------------------------------------------------------------
-- Uma linha por código, com os perfis que o recebem. É a mesma tabela do
-- documento, virada de lado para caber em SQL revisável linha a linha: quem
-- confere a matriz confere ESTE bloco contra aquela tabela, sem interpretar
-- `join`.
--
-- Três pontos confirmados por Irineu em 01/09/2026 (card 2.4 §9): a secretaria
-- cadastra salas, PCs, professores e materiais (SIM); o monitor abre manutenção
-- de PC (SIM); o pedagógico enxerga compras (NÃO — segue sem `compras.ler`).
--
-- ⚠️ CORREÇÃO AO CONTRATO DO CARD 2.4 §8 (achado deste card, 01/09/2026). Lá
-- está escrito que o seed "acrescenta o que faltar e não desfaz configuração".
-- As duas metades da frase se contradizem: a direção DESMARCA `compras.receber`
-- da secretaria na tela de Administração, a linha some, e "acrescentar o que
-- faltar" a devolve no deploy seguinte — sem erro, sem log, e sem ninguém ligar
-- uma coisa à outra. Não ter `delete` protege só quem marca a mais; quem
-- desmarca ficava desprotegido, e desmarcar é o lado que importa para segurança.
--
-- O guarda é POR CÓDIGO, e não por linha nem por unidade: o seed só distribui um
-- código que ainda não tem NENHUMA linha na matriz daquela unidade. Assim
--   * permissão desmarcada de um perfil não volta (o código continua tendo
--     linha em outro perfil);
--   * código NOVO, acrescentado ao catálogo por uma migração futura, continua
--     sendo distribuído no primeiro deploy — que é o que "acrescenta o que
--     faltar" queria dizer.
-- Resta um caso: o código desmarcado de TODOS os perfis volta. É o preço de não
-- ter como distinguir "nunca foi dado" de "foi tirado de todo mundo" sem
-- histórico — e histórico da matriz é exatamente o card 4.7.5, já no board.
-- Também não há `delete`: o seed nunca tira o que a direção marcou a mais.
create or replace function public.fn_seed_matriz(p_unidade_id uuid)
returns integer
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_n integer;
begin
  insert into public.perfil_permissao (unidade_id, perfil_id, permissao_id)
  select p_unidade_id, pe.id, pm.id
    from (values
      ('admin.ler',                         '{DIRECAO}'::text[]),
      ('admin.gerir_usuarios',              '{DIRECAO}'),
      ('admin.gerir_perfis',                '{DIRECAO}'),
      ('unidades.ler',                      '{DIRECAO,PEDAGOGICO,SECRETARIA,MONITOR}'),
      ('unidades.gerir',                    '{DIRECAO}'),
      ('parametros.ler',                    '{DIRECAO}'),
      ('parametros.gerir',                  '{DIRECAO}'),
      ('materiais.ler',                     '{DIRECAO,PEDAGOGICO,SECRETARIA,MONITOR}'),
      ('materiais.criar',                   '{DIRECAO,SECRETARIA}'),
      ('materiais.editar',                  '{DIRECAO,SECRETARIA}'),
      ('materiais.excluir',                 '{DIRECAO,SECRETARIA}'),
      ('alunos.ler',                        '{DIRECAO,PEDAGOGICO,SECRETARIA,MONITOR}'),
      ('alunos.criar',                      '{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      ('alunos.editar',                     '{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      ('alunos.alterar_status',             '{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      ('alunos.reverter_status',            '{DIRECAO}'),
      ('alunos.formar_sem_certificado',     '{DIRECAO}'),
      ('alunos.editar_trilha',              '{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      ('salas.ler',                         '{DIRECAO,PEDAGOGICO,SECRETARIA,MONITOR}'),
      ('salas.criar',                       '{DIRECAO,SECRETARIA}'),
      ('salas.editar',                      '{DIRECAO,SECRETARIA}'),
      ('salas.excluir',                     '{DIRECAO}'),
      ('salas.registrar_manutencao',        '{DIRECAO,SECRETARIA,MONITOR}'),
      ('salas.acessar_credencial',          '{DIRECAO,MONITOR}'),
      ('professores.ler',                   '{DIRECAO,PEDAGOGICO,SECRETARIA,MONITOR}'),
      ('professores.criar',                 '{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      ('professores.editar',                '{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      ('turmas.ler',                        '{DIRECAO,PEDAGOGICO,SECRETARIA,MONITOR}'),
      ('turmas.criar',                      '{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      ('turmas.editar',                     '{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      ('turmas.excluir',                    '{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      ('turmas.alocar',                     '{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      ('turmas.lancar_reposicao_retroativa','{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      ('estoque.ler',                       '{DIRECAO,PEDAGOGICO,SECRETARIA,MONITOR}'),
      ('estoque.lancar_saida',              '{DIRECAO,SECRETARIA,MONITOR}'),
      ('estoque.estornar',                  '{DIRECAO,SECRETARIA}'),
      ('estoque.ajustar',                   '{DIRECAO,SECRETARIA}'),
      ('compras.ler',                       '{DIRECAO,SECRETARIA}'),
      ('compras.criar',                     '{DIRECAO,SECRETARIA}'),
      ('compras.editar',                    '{DIRECAO,SECRETARIA}'),
      ('compras.excluir',                   '{DIRECAO,SECRETARIA}'),
      ('compras.receber',                   '{DIRECAO,SECRETARIA}'),
      ('compras.receber_excedente',         '{DIRECAO}'),
      ('certificados.ler',                  '{DIRECAO,PEDAGOGICO,SECRETARIA,MONITOR}'),
      ('certificados.criar',                '{DIRECAO,SECRETARIA,MONITOR}'),
      ('certificados.marcar_pedagogico',    '{DIRECAO,PEDAGOGICO}'),
      ('certificados.marcar_financeiro',    '{DIRECAO,MONITOR}'),
      ('certificados.alterar_status',       '{DIRECAO,SECRETARIA}'),
      ('pendencias.ler',                    '{DIRECAO,PEDAGOGICO,SECRETARIA,MONITOR}'),
      ('pendencias.resolver',               '{DIRECAO,PEDAGOGICO,SECRETARIA}')
    ) as m(codigo, perfis)
    join public.permissao pm on pm.unidade_id = p_unidade_id and pm.codigo = m.codigo
    join public.perfil    pe on pe.unidade_id = p_unidade_id and pe.codigo = any (m.perfis)
   where not exists (select 1 from public.perfil_permissao pp
                      where pp.permissao_id = pm.id)
  on conflict (perfil_id, permissao_id) do nothing;

  select count(*) into v_n
    from public.perfil_permissao where unidade_id = p_unidade_id;
  return v_n;
end $$;

comment on function public.fn_seed_matriz(uuid) is
  'Matriz inicial de docs/permissoes-matriz.md §5 (direção 50, secretaria 37, pedagógico 22, monitor 14). Distribui só código que ainda não tem linha nenhuma na unidade: assim código novo chega e permissão desmarcada na tela não volta no deploy seguinte.';

-- -----------------------------------------------------------------------------
-- 4. Parâmetros — os 15 que as regras já escritas leem
-- -----------------------------------------------------------------------------
-- Parâmetro ausente é erro PARAMETRO_AUSENTE (card 2.2 §2.3): não há default
-- escondido no código, então o que não estiver aqui não roda. A origem de cada
-- valor está na coluna de comentário — nenhum deles é medição, e os três
-- `ritmo_padrao_dias_<METODO>` são substituídos pela mediana observada no card
-- 9.5.
--
-- `do nothing` e não `do update`: valor ajustado pela escola na tela de
-- Administração não pode voltar ao default no deploy seguinte.
create or replace function public.fn_seed_parametros(p_unidade_id uuid)
returns integer
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_n integer;
begin
  insert into public.parametro (unidade_id, chave, valor, tipo, descricao)
  select p_unidade_id, p.chave, p.valor, 'INTEIRO', p.descricao
    from (values
      -- decisão de 31/08/2026 (card 2.1 §5)
      ('projecao_horizonte_dias',      '60',  'Horizonte da projeção de demanda, em dias'),
      ('standby_alerta_dias',          '30',  'Dias em STANDBY até gerar pendência'),
      -- card 2.5 (docs/regra-virada-rep.md §4)
      ('rep_prazo_dias',               '30',  'Prazo, em dias corridos da aula perdida, para repor sem virar REP contínuo'),
      ('rep_capacidade_semanal',       '1',   'Reposições por semana que o aluno consegue fazer além dos encontros regulares'),
      ('rep_faltas_max',               '2',   'Faltas a reposições agendadas, na janela do prazo, que sugerem a virada'),
      ('rep_janela_volta_dias',        '30',  'Carência sem débito e sem falta para sugerir a volta a REP pontual'),
      -- card de Ordem 5 (docs/projecao-demanda.md §3)
      ('ritmo_padrao_dias_INTERATIVO', '30',  'Dias por apostila no degrau MEDIA_METODO do método Interativo'),
      ('ritmo_padrao_dias_INGLES',     '30',  'Dias por apostila no degrau MEDIA_METODO do método Inglês'),
      ('ritmo_padrao_dias_MODULAR',    '45',  'Dias por módulo no Modular, quando a turma não tem cronograma'),
      ('ritmo_padrao_dias_PADRAO',     '30',  'Último recurso, quando falta a chave do método'),
      ('ritmo_janela_entregas',        '4',   'Entregas recentes que entram na média de ritmo do aluno (4 entregas = 3 intervalos)'),
      ('ritmo_intervalo_min_dias',     '7',   'Piso: intervalo menor que isto é entrega em lote, não ritmo'),
      ('ritmo_intervalo_max_dias',     '120', 'Teto: intervalo maior que isto é interrupção, não ritmo'),
      ('projecao_acelerar_pct',        '50',  'Percentual do ritmo do método aplicado ao aluno ACELERAR'),
      ('ritmo_calibracao_dias',        '180', 'Janela da mediana observada por método na recalibração')
    ) as p(chave, valor, descricao)
  on conflict (unidade_id, chave) do nothing;

  select count(*) into v_n from public.parametro where unidade_id = p_unidade_id;
  return v_n;
end $$;

comment on function public.fn_seed_parametros(uuid) is
  'Os 15 parâmetros lidos pelas regras já especificadas (cards 2.1, 2.5 e Ordem 5). do nothing: valor ajustado na tela não volta ao default no deploy seguinte.';

-- -----------------------------------------------------------------------------
-- 5. A porta única — o que migração e escola-fixture chamam
-- -----------------------------------------------------------------------------
create or replace function public.fn_seed_acesso(p_unidade_id uuid)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
begin
  perform public.fn_seed_permissoes(p_unidade_id);
  perform public.fn_seed_perfis(p_unidade_id);
  perform public.fn_seed_matriz(p_unidade_id);      -- depois das duas: cruza por código
  perform public.fn_seed_parametros(p_unidade_id);
end $$;

comment on function public.fn_seed_acesso(uuid) is
  'Catálogo + perfis + matriz + parâmetros de uma unidade. Chamada pela migração (unidade real) e por supabase/seed.sql (escola-fixture): uma fonte só, para que a fixture não passe a comparar a tela contra uma matriz de mentira (card 3.4.5, camada acesso_seed_real).';

-- -----------------------------------------------------------------------------
-- 6. O primeiro usuário de direção
-- -----------------------------------------------------------------------------
-- O card 3.5 fechou o espelho auth.users → usuario: o convite pelo painel do
-- Auth já cria a linha de `usuario` sozinho. O que falta é `usuario_perfil` —
-- sem ele a pessoa entra, `fn_minhas_permissoes()` devolve vazio e todas as
-- telas ficam ocultas, sem erro. Hoje NÃO HÁ EM QUEM LOGAR no dev, e o card 3.7
-- depende disso.
--
-- São duas metades, porque a ordem entre o convite e o deploy não é controlável:
--   (a) a chamada abaixo, para o caso de o convite já ter acontecido;
--   (b) o trigger, para o caso normal — a migração chega antes, o convite depois.
-- Com só a metade (a) o seed rodaria em produção, não encontraria ninguém e não
-- faria nada: o silêncio que este projeto já catalogou três vezes.
--
-- O e-mail mora em `parametro` e não no corpo da função de propósito: um e-mail
-- digitado errado se corrige na tela de Administração, não numa migração nova.
-- ⚠️ Corolário: como todo parâmetro, ele é legível por qualquer autenticado da
-- unidade (card 3.4). É o e-mail de quem dirige a escola, não um segredo —
-- segredo continua indo para o Vault (card 2.9).
create or replace function public.fn_seed_direcao_inicial(p_unidade_id uuid)
returns boolean
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_email   text;
  v_usuario uuid;
begin
  select valor into v_email
    from public.parametro
   where unidade_id = p_unidade_id and chave = 'direcao_inicial_email';

  if v_email is null then
    return false;
  end if;

  select id into v_usuario
    from public.usuario
   where unidade_id = p_unidade_id and lower(email) = lower(v_email);

  if v_usuario is null then
    return false;   -- ainda não convidado; o trigger abaixo cuida quando for
  end if;

  insert into public.usuario_perfil (unidade_id, usuario_id, perfil_id)
  select p_unidade_id, v_usuario, pe.id
    from public.perfil pe
   where pe.unidade_id = p_unidade_id and pe.codigo = 'DIRECAO'
  on conflict (usuario_id, perfil_id) do nothing;

  return true;
end $$;

comment on function public.fn_seed_direcao_inicial(uuid) is
  'Liga ao perfil DIRECAO o usuário cujo e-mail está no parâmetro direcao_inicial_email. Metade (a) do bootstrap: cobre o convite que já aconteceu. A metade (b) é tg_usuario_direcao_inicial.';

-- security definer: o trigger dispara dentro da transação do espelho (card 3.5),
-- que é do supabase_auth_admin, e precisa LER `parametro` e ESCREVER
-- `usuario_perfil` — as duas com RLS forçada e nenhuma política a favor de quem
-- convida. O filtro de unidade está no corpo (`new.unidade_id`), como manda a
-- correção do card 2.3 para toda função definer deste projeto.
create or replace function public.fn_usuario_direcao_inicial()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_email text;
begin
  select valor into v_email
    from public.parametro
   where unidade_id = new.unidade_id and chave = 'direcao_inicial_email';

  if v_email is not null and lower(new.email) = lower(v_email) then
    insert into public.usuario_perfil (unidade_id, usuario_id, perfil_id)
    select new.unidade_id, new.id, pe.id
      from public.perfil pe
     where pe.unidade_id = new.unidade_id and pe.codigo = 'DIRECAO'
    on conflict (usuario_id, perfil_id) do nothing;
  end if;

  return null;   -- after trigger: o retorno é ignorado
end $$;

comment on function public.fn_usuario_direcao_inicial() is
  'Metade (b) do bootstrap do card 3.6: quando o convite chega DEPOIS do deploy, atribui DIRECAO ao usuário cujo e-mail é o do parâmetro direcao_inicial_email.';

revoke execute on function public.fn_usuario_direcao_inicial() from public, anon, authenticated;

drop trigger if exists tg_usuario_direcao_inicial on public.usuario;
create trigger tg_usuario_direcao_inicial
  after insert on public.usuario
  for each row execute function public.fn_usuario_direcao_inicial();

-- -----------------------------------------------------------------------------
-- 7. Nenhuma função de seed alcançável pelo PostgREST (C9 do card 2.8)
-- -----------------------------------------------------------------------------
-- `create function` concede EXECUTE a PUBLIC por padrão. Estas escrevem catálogo
-- e matriz: mesmo sendo `security invoker` (a RLS as barraria), publicá-las na
-- API seria oferecer um botão que não existe em tela nenhuma.
revoke execute on function public.fn_seed_permissoes(uuid)      from public, anon, authenticated;
revoke execute on function public.fn_seed_perfis(uuid)          from public, anon, authenticated;
revoke execute on function public.fn_seed_matriz(uuid)          from public, anon, authenticated;
revoke execute on function public.fn_seed_parametros(uuid)      from public, anon, authenticated;
revoke execute on function public.fn_seed_acesso(uuid)          from public, anon, authenticated;
revoke execute on function public.fn_seed_direcao_inicial(uuid) from public, anon, authenticated;

-- =============================================================================
-- 8. Aplicação: a unidade real da escola
-- =============================================================================
-- `codigo` é a chave natural estável criada pelo card 3.3 justamente para isto:
-- `nome` é editável por quem tem `unidades.gerir`, e um seed idempotente por
-- nome inseriria uma segunda unidade em silêncio no dia em que alguém corrigisse
-- o cabeçalho.
do $$
declare
  v_unidade uuid;
begin
  insert into public.unidade (codigo, nome)
  values ('MATRIZ', 'Instituto Mix Charqueadas')
  on conflict (codigo) do nothing;

  select id into v_unidade from public.unidade where codigo = 'MATRIZ';

  perform public.fn_seed_acesso(v_unidade);

  -- E-mail do primeiro usuário de direção (Irineu, 01/09/2026). Editável na tela
  -- de Administração; `do nothing` para não sobrescrever correção feita lá.
  insert into public.parametro (unidade_id, chave, valor, tipo, descricao)
  values (v_unidade, 'direcao_inicial_email', 'irineus@gmail.com', 'TEXTO',
          'E-mail que recebe o perfil DIRECAO no primeiro acesso (bootstrap do card 3.6)')
  on conflict (unidade_id, chave) do nothing;

  perform public.fn_seed_direcao_inicial(v_unidade);
end $$;
