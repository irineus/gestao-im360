-- =============================================================================
-- Card 3.5 — Auth por e-mail/senha e espelhamento auth.users → usuario
-- Fonte: plano §4 (decisão 18), docs/modelagem-dados-ddl.md §5.1 ("Espelho de
--        auth.users. Populado por trigger em auth.users (card 3.5)"),
--        docs/permissoes-matriz.md §8.4, docs/acesso-autenticacao.md
--
-- Entrega: fn_usuario_espelhar + os dois triggers em auth.users, e
--          fn_usuario_espelho_coerente + o trigger que impede a divergência
--          pelo lado do app.
--
-- A configuração do Auth em si (signup público desligado, expiração de link,
-- SMTP) NÃO é migração: vive em supabase/config.toml e no painel dos projetos
-- remotos. Ver docs/acesso-autenticacao.md §2 e §7.
--
-- O invariante que este arquivo instala, em uma frase:
--
--     `usuario` é um espelho de `auth.users`: quem entra em auth entra aqui, e
--     `usuario.email` é SEMPRE igual a `auth.users.email`.
--
-- Sem trigger, a alternativa seria criar a linha de `usuario` pelo app depois do
-- convite. Isso deixa uma janela em que a pessoa já consegue autenticar e ainda
-- não tem linha nenhuma — e um usuário autenticado sem `usuario` não é um
-- usuário sem acesso, é um usuário cujo fn_unidade_atual() devolve null e que vê
-- todas as telas vazias, sem erro nenhum. É o silêncio que este projeto já
-- catalogou como o modo de falha mais caro (cards 2.3, 2.4, 3.4).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. fn_usuario_espelhar() — cria a linha de `usuario` no ato do convite
-- -----------------------------------------------------------------------------
-- security definer por dois motivos independentes: `public.usuario` tem RLS
-- habilitada e FORÇADA (card 3.3) e quem dispara este trigger é o
-- `supabase_auth_admin`, que não é usuário do sistema e não teria política
-- nenhuma a favor. O dono (postgres) tem BYPASSRLS — achado do card 3.3 —, então
-- a escrita passa. Como toda função definer deste projeto, o filtro de unidade
-- está no CORPO e não na RLS (cards 2.3 §3.4 e 2.9).
--
-- O que o espelho copia, e o que ele deliberadamente NÃO copia:
--
--   copia   id, email               — identidade; o email volta a ser copiado a
--                                     cada troca confirmada no Auth (§2 abaixo)
--   copia   nome, unidade_id        — SÓ NA CRIAÇÃO, a partir do metadado do
--                                     convite; depois são dado do app, corrigidos
--                                     na tela de Administração (card 4.7). Se o
--                                     espelho os reescrevesse a cada update, a
--                                     correção da direção duraria até a próxima
--                                     mexida no Auth.
--   não copia  ativo                — `ativo` é decisão da direção, não do Auth.
--                                     Desativar no app não revoga o token que já
--                                     foi emitido: a pessoa continua conseguindo
--                                     autenticar, mas fn_unidade_atual() devolve
--                                     null e tem_permissao() é falsa para tudo
--                                     (card 3.4), então o app nega tudo. A sessão
--                                     morre de vez quando o JWT expira (1h).
--                                     Bloqueio imediato de verdade é "Ban user"
--                                     no painel do Auth.
create or replace function public.fn_usuario_espelhar()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_meta      text;
  v_unidade   uuid;
  v_qtd       integer;
begin
  -- Sem e-mail não há usuário do sistema: o projeto é e-mail/senha (decisão 18),
  -- e `usuario.email` é `not null`. Deixar seguir daria um 23502 sem `codigo`,
  -- que o Flutter não sabe traduzir (card 2.2 §1.2).
  if new.email is null or trim(new.email) = '' then
    raise exception using
      errcode = 'PT422',
      message = 'Não é possível criar um usuário sem e-mail.',
      detail  = json_build_object('codigo', 'USUARIO_SEM_EMAIL',
                                  'auth_user_id', new.id)::text,
      hint    = 'Este sistema autentica por e-mail e senha. Convide a pessoa por e-mail.';
  end if;

  -- Unidade: do metadado do convite, ou a única unidade ativa.
  --
  -- O fallback não é conveniência: na v1 existe UMA unidade (decisão de
  -- arquitetura, seção 1 das Decisões vigentes), e o convite feito pelo painel do
  -- Supabase — que é o fluxo do card 3.5 até a tela de Administração existir
  -- (card 4.7) — não tem onde digitar metadado. Melhor ainda, o fallback se fecha
  -- sozinho: no dia em que a segunda unidade nascer (Fase 11) ele deixa de ser
  -- não-ambíguo e passa a recusar, obrigando quem convida a dizer a unidade. Um
  -- default que expira quando deixa de ser óbvio.
  v_meta := nullif(trim(coalesce(new.raw_user_meta_data ->> 'unidade_id', '')), '');

  if v_meta is not null then
    begin
      v_unidade := v_meta::uuid;
    exception when invalid_text_representation then
      raise exception using
        errcode = 'PT422',
        message = 'A unidade informada no convite não é válida.',
        detail  = json_build_object('codigo', 'USUARIO_SEM_UNIDADE',
                                    'unidade_id', v_meta)::text,
        hint    = 'Informe o id da unidade em raw_user_meta_data.unidade_id.';
    end;

    if not exists (select 1 from public.unidade u where u.id = v_unidade and u.ativo) then
      raise exception using
        errcode = 'PT422',
        message = 'A unidade informada no convite não existe ou está inativa.',
        detail  = json_build_object('codigo', 'USUARIO_SEM_UNIDADE',
                                    'unidade_id', v_meta)::text,
        hint    = 'Informe o id de uma unidade ativa em raw_user_meta_data.unidade_id.';
    end if;
  else
    -- Duas consultas em vez de um `count(*), min(id)`: não existe min(uuid) no
    -- Postgres, e a única forma de escrever isso numa linha seria comparar uuid
    -- como texto, que é ordenação sem significado.
    select count(*) into v_qtd from public.unidade u where u.ativo;

    if v_qtd <> 1 then
      raise exception using
        errcode = 'PT422',
        message = case when v_qtd = 0
                       then 'Não há unidade cadastrada para vincular o usuário.'
                       else 'Há mais de uma unidade ativa: o convite precisa dizer qual.'
                  end,
        detail  = json_build_object('codigo', 'USUARIO_SEM_UNIDADE',
                                    'unidades_ativas', v_qtd)::text,
        hint    = 'Informe o id da unidade em raw_user_meta_data.unidade_id ao convidar.';
    end if;

    select u.id into v_unidade from public.unidade u where u.ativo;
  end if;

  -- `nome` é obrigatório e o convite pelo painel não pergunta: entra a parte
  -- local do e-mail, que é reconhecível na lista de usuários e obviamente
  -- provisória. A direção corrige na tela de Administração (card 4.7).
  insert into public.usuario (id, unidade_id, nome, email)
  values (new.id,
          v_unidade,
          coalesce(nullif(trim(new.raw_user_meta_data ->> 'nome'), ''),
                   split_part(new.email, '@', 1)),
          new.email)
  on conflict (id) do nothing;   -- espelho nunca sobrescreve dado do app

  return new;
end;
$$;

comment on function public.fn_usuario_espelhar() is
  'Cria a linha de public.usuario quando nasce um auth.users. Unidade vem de raw_user_meta_data.unidade_id ou da única unidade ativa; nome vem do metadado ou da parte local do e-mail (card 3.5).';

-- C9 (card 2.8): nenhum execute para public/anon — e nem para authenticated,
-- que não chama esta função por caminho nenhum. O Postgres verifica o privilégio
-- em CREATE TRIGGER, não a cada disparo (mesma nota de fn_auditoria, card 3.3).
revoke execute on function public.fn_usuario_espelhar() from public;
revoke execute on function public.fn_usuario_espelhar() from anon;
revoke execute on function public.fn_usuario_espelhar() from authenticated;

-- -----------------------------------------------------------------------------
-- 2. fn_usuario_email_sincronizar() — a troca de e-mail confirmada no Auth
-- -----------------------------------------------------------------------------
-- O GoTrue grava o e-mail novo em auth.users depois de confirmado nos dois
-- endereços (double_confirm_changes, config.toml). Sem este trigger, `usuario`
-- guardaria para sempre o e-mail antigo: a pessoa entraria com um e-mail e a
-- tela de Administração mostraria outro — divergência silenciosa entre a
-- identidade e o espelho dela.
create or replace function public.fn_usuario_email_sincronizar()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.email is distinct from old.email and new.email is not null then
    update public.usuario
       set email = new.email
     where id = new.id;
  end if;
  return new;
end;
$$;

comment on function public.fn_usuario_email_sincronizar() is
  'Replica em public.usuario a troca de e-mail confirmada em auth.users (card 3.5).';

revoke execute on function public.fn_usuario_email_sincronizar() from public;
revoke execute on function public.fn_usuario_email_sincronizar() from anon;
revoke execute on function public.fn_usuario_email_sincronizar() from authenticated;

-- -----------------------------------------------------------------------------
-- 3. Os triggers em auth.users
-- -----------------------------------------------------------------------------
-- `after insert`: a linha de auth.users precisa existir antes, porque
-- usuario.id a referencia (FK do card 3.3).
drop trigger if exists tg_auth_usuario_criado on auth.users;
create trigger tg_auth_usuario_criado
  after insert on auth.users
  for each row execute function public.fn_usuario_espelhar();

drop trigger if exists tg_auth_usuario_email on auth.users;
create trigger tg_auth_usuario_email
  after update of email on auth.users
  for each row execute function public.fn_usuario_email_sincronizar();

-- Não há trigger de delete, e a ausência é a decisão: a FK usuario.id →
-- auth.users(id) é `on delete restrict` (card 3.3), então apagar a pessoa no
-- painel do Auth FALHA enquanto houver espelho. É o comportamento certo — quem
-- entregou apostila, alterou status de aluno e lançou estoque está em
-- `criado_por`/`atualizado_por` de milhares de linhas, e apagar o usuário
-- transformaria esse rastro em uuid órfão. Usuário sai do ar com `ativo = false`
-- (e "Ban user" no Auth, se precisar ser imediato), nunca por delete.

-- -----------------------------------------------------------------------------
-- 4. O outro lado: o app não pode fazer o espelho divergir
-- -----------------------------------------------------------------------------
-- A política usuario_upd (card 3.4) deixa quem tem `admin.gerir_usuarios`
-- atualizar a linha, e o PostgREST publica a tabela inteira: um PATCH em
-- /rest/v1/usuario?id=eq.… com `email` novo passaria pela RLS sem reclamar. O
-- resultado seria o pior tipo de bug deste projeto — a tela mostraria um e-mail
-- com o qual ninguém consegue entrar, sem nenhum erro em lugar nenhum. O e-mail
-- é do Auth; trocá-lo é um fluxo do Auth, com confirmação nos dois endereços.
--
-- security definer porque precisa ler `auth.users`, que nenhum papel do app
-- alcança. Entra na lista fechada do teste C8 com essa justificativa. Não filtra
-- unidade no corpo porque não devolve dado: compara e recusa.
create or replace function public.fn_usuario_espelho_coerente()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_email_auth text;
begin
  select u.email into v_email_auth
    from auth.users u
   where u.id = new.id;

  -- Sem linha em auth.users não há divergência a acusar: há um usuário que não
  -- existe no Auth, e quem diz isso é a FK `usuario.id → auth.users(id)`, com
  -- 23503. Inventar um código nosso aqui seria traduzir para pior o que a
  -- restrição já diz com precisão (card 2.2 §1: restrição antes de função).
  if v_email_auth is null then
    return new;
  end if;

  if new.email is distinct from v_email_auth then
    raise exception using
      errcode = 'PT409',
      message = 'O e-mail do usuário é o e-mail de acesso e só muda pelo próprio Auth.',
      detail  = json_build_object('codigo', 'EMAIL_IMUTAVEL',
                                  'email_auth', v_email_auth)::text,
      hint    = 'Peça à pessoa para trocar o e-mail pelo app (confirmação nos dois endereços) ou troque no painel do Auth.';
  end if;

  return new;
end;
$$;

comment on function public.fn_usuario_espelho_coerente() is
  'Recusa insert/update em public.usuario cujo email divirja de auth.users. PT409 / EMAIL_IMUTAVEL (card 3.5).';

revoke execute on function public.fn_usuario_espelho_coerente() from public;
revoke execute on function public.fn_usuario_espelho_coerente() from anon;
revoke execute on function public.fn_usuario_espelho_coerente() from authenticated;

create trigger tg_usuario_espelho_coerente
  before insert or update of email on public.usuario
  for each row execute function public.fn_usuario_espelho_coerente();
