# App Flutter — Gestão IM360

Esqueleto do card **3.7**: login, camada de sessão, shell responsivo e guardas
de rota. As telas de negócio chegam nos cards das fases 4 a 9 — entregues até
aqui: Materiais (4.4), Salas e PCs (4.5) e Administração (4.7, com o histórico
do 4.7.5); as demais rotas abrem um placeholder que diz **qual card** a entrega.

## Rodar

Os valores de ambiente entram em *build time*, com `--dart-define`. Sem os três
primeiros o app sobe numa tela que diz o que falta, em vez de dar erro de rede em
toda consulta; os dois últimos são da observabilidade (card 3.12) e a ausência
deles **não** impede o app de rodar — só o deixa sem Sentry.

```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_ANON_KEY=<anon key do supabase status> \
  --dart-define=APP_URL_BASE=http://localhost:8080
```

Contra o stack local (`supabase start` na raiz do repositório), os oito usuários
da escola-fixture logam com a senha `fixture-local-123` — um por perfil
(`docs/acesso-autenticacao.md` §10). A recuperação de senha se testa no Mailpit,
em <http://127.0.0.1:54324>.

| `--dart-define` | O que é |
|---|---|
| `SUPABASE_URL` | URL do projeto (dev `ncdfolxdupbbfvtydngx`, prod `aqfuawrygxsiopyppjza`) |
| `SUPABASE_ANON_KEY` | chave anônima/publicável — **pública por desenho**, vai no bundle. A *service key* nunca entra aqui: `service_role` tem `BYPASSRLS` (card 3.3) |
| `APP_URL_BASE` | base pública do app, usada para montar o `redirectTo` da recuperação de senha. Precisa estar nas **Redirect URLs** dos dois projetos, com o curinga `/**` (`docs/deploy-web.md` §4) |
| `SENTRY_DSN` | DSN do projeto `irineu-pinheiro/gestao-im360` (card 3.12). **Sem ele o Sentry não inicializa** — é o que mantém `flutter run` e a suíte sem mandar nada para lugar nenhum. Público por desenho, como a chave anônima: autoriza escrever evento, nunca ler. ⚠️ Ao mudar o DSN, conferir o `connect-src` de `web/_headers` — CSP que barra a ingestão bloqueia o envio **em silêncio** (`docs/observabilidade.md` §4) |
| `APP_AMBIENTE` | rótulo do ambiente no Sentry: `homologacao` ou `producao`. Fora do CI, deixar em branco — o default é `local` |

## Empacotar para o Cloudflare Pages

```bash
flutter build web --release --no-web-resources-cdn \
  --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=… --dart-define=APP_URL_BASE=…
```

`--no-web-resources-cdn` **não é opcional**: sem ele o build de release busca o CanvasKit no
`gstatic.com` e, com o CDN inalcançável (filtro de rede, proxy), o app abre em **tela branca sem
erro**. Com a opção, tudo é servido da própria origem. O resto do contrato do deploy — os
cabeçalhos, por que não existe `_redirects` e o que Irineu configura no painel do Supabase — está em
`docs/deploy-web.md`.

O app usa **estratégia de URL por caminho** (`/alunos`, não `/#/alunos`): o fragmento pertence ao
Auth, que devolve os tokens nele. Quem serve o build precisa devolver o `index.html` para qualquer
caminho — o Cloudflare Pages já faz isso sozinho, um `python -m http.server` não faz.

## Verificar antes de empurrar

O portão do card 3.9 (`testes.yml`) roda estes três:

```bash
dart format --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
```

## Onde está o quê

```
lib/
  config/ambiente.dart        --dart-define e o que falta quando falta
  config/link_inicial.dart    o `type` do link com que o app abriu (convite,
                              recuperação) — lido ANTES do Supabase.initialize,
                              que consome e limpa a URL (card 4.7)
  administracao/              card 4.7 — usuários, perfis, matriz, parâmetros e
                              o histórico da matriz (4.7.5)
    administracao.dart        modelos + lógica pura: domínios, quem está sem
                              perfil, plano de perfis, validação por tipo
    administracao_repositorio.dart
                              interface + PostgREST nas tabelas; o convite vai
                              pela Edge Function convidar-usuario (functions.invoke)
    administracao_provider.dart
                              FutureProviders, filtro de usuários, perfil
                              selecionado e a versão que toda escrita incrementa
  catalogo/                   card 4.4 — o catálogo curricular como o app o vê
    catalogo.dart             modelos das sete tabelas do 4.1 + filtros e o plano de
                              gravação de uma sequência ordenada (lógica pura, testável)
    catalogo_repositorio.dart interface + implementação PostgREST (tabelas, nunca view)
    catalogo_provider.dart    FutureProviders por consulta, filtros por aba e a versão
                              do catálogo que toda escrita incrementa para recarregar
  infraestrutura/             card 4.5 — salas, PCs, manutenções e professores
    infraestrutura.dart       modelos das quatro tabelas do 4.3 + lógica pura: capacidade
                              efetiva da sala, manutenção em aberto, ação contextual do PC,
                              datas dd/mm/aaaa e filtros
    infraestrutura_repositorio.dart
                              interface + PostgREST nas tabelas; a credencial só pelas RPCs
                              fn_pc_credencial_ler / fn_pc_credencial_gravar (card 2.9)
    infraestrutura_provider.dart
                              FutureProviders, filtros por aba e a versão que toda escrita
                              incrementa
  erros/
    catalogo_erros.dart       codigo -> mensagem (design-system §7.1)
    erro_app.dart             extrai o codigo do DETAIL das exceções do Supabase; traduz
                              também os SQLSTATEs de integridade 23503/23505 (card 4.4),
                              os códigos do GoTrue (rate limit, e-mail já cadastrado…) e
                              a resposta de uma Edge Function (card 4.7)
  rotas/
    rotas.dart                as 13 telas e o conjunto mínimo de cada uma (2.4 §6)
    roteador.dart             go_router: redirect por estado de sessão + guarda por rota;
                              mapa rota -> tela entregue (o resto abre o placeholder)
  sessao/
    sessao.dart               Sessao e os cinco estados (inclusive os de falha)
    sessao_repositorio.dart   a carga em três passos (acesso-autenticacao §4)
    sessao_provider.dart      Riverpod; permissoesProvider, resumoUsuarioProvider e
                              unidadeAtualProvider (a unidade que toda escrita carrega)
  telas/                      login, redefinir senha, unidade, acesso bloqueado, placeholders
    materiais/                card 4.4 — tela 6 (parte catálogo): três abas
      tela_materiais.dart     abas Materiais / Cursos / Combos, cada uma uma TabelaIm360
      filtros_catalogo.dart   busca, método, categoria, "só ativos" — estado no provider
      formularios.dart        material, curso, combo, módulo e o nome dos métodos
      detalhes.dart           painel do curso (sequência + módulos) e do combo (cursos)
      editor_sequencia.dart   lista ordenada com alça própria, remover e adicionar
    salas/                    card 4.5 — tela 10: Salas e PCs, com Professores na 2ª aba
      tela_salas.dart         abas Salas e PCs / Professores, cada uma uma TabelaIm360
      filtros_salas.dart      busca, tipo, "só ativas" / "só ativos" — estado no provider
      detalhe_sala.dart       painel da sala: PCs com situação e ação contextual
                              (Manutenção / Encerrar / Reativar)
      formularios.dart        sala, PC (com a ficha da credencial do card 2.9 §8),
                              manutenção, encerramento, reativação, professor
    administracao/            card 4.7 — tela 12: quatro abas
      tela_administracao.dart Usuários / Perfis e matriz / Parâmetros / Histórico
      aba_usuarios.dart       lista com quem está SEM PERFIL destacado, filtros
      aba_matriz.dart         um perfil por vez, 12 domínios, caixa com descrição;
                              desmarcar pede confirmação (vale na hora)
      aba_parametros.dart     chave, valor, descrição, tipo
      aba_historico.dart      quem concedeu/removeu o quê, quando (card 4.7.5)
      formularios.dart        convite (Edge Function + perfis no mesmo ato),
                              usuário, perfil, parâmetro
  theme/                      cópia do apêndice §10 do card 2.7 + preferência clara/escura
  widgets/
    botoes.dart               BotaoAcao: sem permissão oculta, sem estado desabilita com motivo
    confirmacao.dart          confirmarEfemero — a snackbar de "salvo" / "excluído"
    estados.dart              carregando / vazio / erro / sem acesso
    painel_detalhe.dart       PainelDetalhe e TituloSecao — cabeçalho e seções dos painéis
    formulario.dart           FormularioIm360 (design-system §5.4): validação de formato,
                              banner de erro pelo codigo, primário travado ao executar,
                              ações extras com confirmação; mostrarFormulario decide
                              diálogo × tela cheia pela faixa
    marca.dart                símbolo e assinatura desenhados (ver nota no arquivo)
    shell_im360.dart          menu lateral / trilho / barra inferior
    tabela_im360.dart         TabelaIm360 (design-system §5.2): os quatro estados num
                              contrato só, degradação por prioridade de coluna e cartões
                              no mobile com os filtros numa folha inferior
```

O contrato de códigos de erro é `../test/fixtures/codigos_erro.txt`, na raiz do
repositório: os dois consumidores são o banco (C12) e o app, e ele não é de
nenhum dos dois sozinho.
