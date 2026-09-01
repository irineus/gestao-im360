# App Flutter — Gestão IM360

Esqueleto do card **3.7**: login, camada de sessão, shell responsivo e guardas
de rota. As telas de negócio chegam nos cards das fases 4 a 9 — hoje cada rota
abre um placeholder que diz **qual card** a entrega.

## Rodar

Os três valores de ambiente entram em *build time*, com `--dart-define`. Sem
eles o app sobe numa tela que diz o que falta, em vez de dar erro de rede em
toda consulta.

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
  erros/
    catalogo_erros.dart       codigo -> mensagem (design-system §7.1)
    erro_app.dart             extrai o codigo do DETAIL das exceções do Supabase
  rotas/
    rotas.dart                as 13 telas e o conjunto mínimo de cada uma (2.4 §6)
    roteador.dart             go_router: redirect por estado de sessão + guarda por rota
  sessao/
    sessao.dart               Sessao e os cinco estados (inclusive os de falha)
    sessao_repositorio.dart   a carga em três passos (acesso-autenticacao §4)
    sessao_provider.dart      Riverpod; permissoesProvider e resumoUsuarioProvider
  telas/                      login, redefinir senha, unidade, acesso bloqueado, placeholders
  theme/                      cópia do apêndice §10 do card 2.7 + preferência clara/escura
  widgets/
    botoes.dart               BotaoAcao: sem permissão oculta, sem estado desabilita com motivo
    estados.dart              carregando / vazio / erro / sem acesso
    marca.dart                símbolo e assinatura desenhados (ver nota no arquivo)
    shell_im360.dart          menu lateral / trilho / barra inferior
```

O contrato de códigos de erro é `../test/fixtures/codigos_erro.txt`, na raiz do
repositório: os dois consumidores são o banco (C12) e o app, e ele não é de
nenhum dos dois sozinho.
