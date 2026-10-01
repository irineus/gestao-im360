import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/link_inicial.dart';
import '../erros/erro_app.dart';
import '../rotas/rotas.dart';
import '../sessao/sessao_provider.dart';
import '../sessao/sessao_repositorio.dart';
import '../theme/dimensoes.dart';
import '../theme/tipografia.dart';
import '../widgets/formulario.dart';

/// Destino do link de recuperação (card 3.5 §5) e do link de **convite**
/// (card 4.7). Define a senha — e diz, no caso do convite, que é isso que
/// falta para concluir o cadastro (achado do card 3.8: a mensagem tem de ser
/// "defina sua senha", não "esqueci minha senha").
///
/// ⚠️ **Card 9.2,80: chegar aqui NÃO garante que a sessão aberta veio do
/// link.** Este comentário afirmava "a pessoa chega aqui já com uma sessão
/// criada pelo Auth", e não era verdade: em 01/10/2026 o link vencido do
/// Laurence foi aberto num desktop com a sessão do LINDOMAR aberta, o Auth
/// recusou o link, a sessão que sobrou foi a do Lindomar — e esta tela trocou
/// a senha dele (`updateUser` aplica na sessão corrente, seja de quem for).
/// Por isso a tela tem TRÊS estados, e só um deles tem formulário:
///
/// 1. **o link valeu** e a sessão corrente é a que ele criou
///    (`LinkInicial.autorizaTroca`) → o formulário;
/// 2. **o link foi recusado** (vencido, já usado, aberto noutro navegador) →
///    o que aconteceu e como pedir outro, sem formulário;
/// 3. **não há link** (a rota aberta à mão, ou a página recarregada depois) →
///    como conseguir um, sem formulário.
///
/// Nos dois últimos, se houver sessão aberta no navegador, a tela diz DE QUEM
/// ela é e oferece sair — foi exatamente uma sessão alheia esquecida que
/// virou vítima.
///
/// Textos do convite em [tituloConvite] e [apoioConvite]; a decisão entre um
/// e outro vem do `type` do link (lib/config/link_inicial.dart) ou da query
/// `motivo=convite` que o roteador acrescenta.
///
/// ⚠️ A rota precisa estar nas **Redirect URLs** dos dois projetos, e a
/// **Site URL** tem de ser a do app — sem isso o link existe e leva ao lugar
/// errado (ajuste 1 do card 3.5, para o card 3.8).
class TelaRedefinirSenha extends ConsumerStatefulWidget {
  const TelaRedefinirSenha({super.key});

  @override
  ConsumerState<TelaRedefinirSenha> createState() => _TelaRedefinirSenhaState();
}

const tituloConvite = 'Defina sua senha para concluir o cadastro';
const apoioConvite =
    'Você chegou pelo link do convite. Escolha a senha com que vai entrar no '
    'sistema — sem ela, o próximo acesso não funciona.';
const tituloRecuperacao = 'Definir nova senha';

const tituloLinkRecusado = 'Este link não vale mais';
const textoLinkVencido =
    'O link venceu ou já foi usado. Cada link vale uma vez só, por 24 horas — '
    'e abri-lo, inclusive pelo botão do e-mail, já o gasta.';
const textoLinkOutroNavegador =
    'Este link foi pedido antes de uma mudança no sistema e só abre no mesmo '
    'navegador em que foi pedido. Peça um link novo: o novo abre em qualquer '
    'aparelho.';
const textoPecaOutroLink =
    'Peça um link novo em "Esqueci minha senha", na tela de entrada, e abra só '
    'o mais recente. Se era um convite, a direção também pode reenviá-lo.';

const tituloSemLink = 'Para definir a senha, use o link do e-mail';
const textoSemLink =
    'A senha só pode ser definida por quem chegou agora pelo link de convite '
    'ou de recuperação. Se você não tem um link válido, peça um novo em '
    '"Esqueci minha senha", na tela de entrada.';

/// O aviso de sessão aberta — a vítima do card 9.2,80 foi uma sessão alheia
/// esquecida no desktop da secretaria.
String textoSessaoAberta(String email) =>
    'Este navegador está com a sessão de $email aberta. Se não é a sua conta, '
    'saia antes de continuar.';

class _TelaRedefinirSenhaState extends ConsumerState<TelaRedefinirSenha> {
  final _formulario = GlobalKey<FormState>();
  final _senha = TextEditingController();
  final _confirmacao = TextEditingController();
  bool _enviando = false;
  String? _erro;
  bool _pronto = false;
  bool _eraConvite = false;

  @override
  void dispose() {
    _senha.dispose();
    _confirmacao.dispose();
    super.dispose();
  }

  Future<void> _salvar(bool convite) async {
    if (!_formulario.currentState!.validate()) return;
    final repositorio = ref.read(sessaoRepositorioProvider);
    // Conferida de novo no clique, e não só no `build`: a sessão pode ter
    // mudado entre desenhar o formulário e tocar em Salvar.
    if (!LinkInicial.autorizaTroca(repositorio.autenticado?.id)) {
      setState(() => _erro = mensagemSenhaSemLink);
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await repositorio.trocarSenha(_senha.text);
      // O link é de uso único, e a autorização que ele deu também.
      LinkInicial.consumir();
      _eraConvite = convite;
      await ref.read(sessaoProvider.notifier).recarregar();
      if (mounted) setState(() => _pronto = true);
    } catch (erro) {
      if (mounted) setState(() => _erro = traduzirErro(erro).mensagem);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _entrar() {
    // Senha definida: o link já foi consumido, e o roteador leva à primeira
    // tela que a pessoa pode abrir (ou a "sem perfil", que é a verdade até
    // alguém atribuir um).
    context.go('/');
  }

  /// Sai da sessão aberta — de quem quer que seja — e vai à tela de entrada,
  /// onde está o "Esqueci minha senha".
  Future<void> _sair() async {
    LinkInicial.consumir();
    await ref.read(sessaoProvider.notifier).sair();
    if (mounted) context.go(rotaLogin.caminho);
  }

  void _irPara(String caminho) {
    LinkInicial.consumir();
    context.go(caminho);
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final convite =
        LinkInicial.convitePendente ||
        GoRouterState.of(context).uri.queryParameters['motivo'] == 'convite';
    // Observada para a tela se redesenhar quando a sessão muda (sair, o link
    // criando sessão nova); QUEM está autenticado vem do Auth, e não da carga
    // da sessão, que pode estar sem espelho, sem perfil ou carregando.
    ref.watch(sessaoProvider);
    final autenticado = ref.read(sessaoRepositorioProvider).autenticado;

    final Widget conteudo;
    if (_pronto) {
      conteudo = _concluido();
    } else if (LinkInicial.autorizaTroca(autenticado?.id)) {
      conteudo = _formularioSenha(cores, convite);
    } else {
      conteudo = _semFormulario(cores, autenticado);
    }

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Dim.e24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: Dim.larguraFormularioMax,
            ),
            child: conteudo,
          ),
        ),
      ),
    );
  }

  Widget _concluido() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        _eraConvite ? 'Senha definida.' : 'Senha alterada.',
        style: Tipografia.corpo,
      ),
      const SizedBox(height: Dim.e24),
      FilledButton(onPressed: _entrar, child: const Text('Entrar no sistema')),
    ],
  );

  /// O estado 1 do topo do arquivo — o único com formulário.
  Widget _formularioSenha(ColorScheme cores, bool convite) => Form(
    key: _formulario,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          convite ? tituloConvite : tituloRecuperacao,
          style: Tipografia.titulo,
        ),
        if (convite) ...[
          const SizedBox(height: Dim.e8),
          Text(
            apoioConvite,
            style: Tipografia.corpo.copyWith(color: cores.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: Dim.e24),
        TextFormField(
          controller: _senha,
          obscureText: true,
          style: Tipografia.corpo,
          decoration: const InputDecoration(
            labelText: 'Nova senha',
            // O mínimo é o do Auth (card 3.5 §2).
            helperText: 'Ao menos 8 caracteres, com letras e números.',
          ),
          validator: (v) => (v == null || v.length < 8)
              ? 'A senha precisa de ao menos 8 caracteres.'
              : null,
        ),
        const SizedBox(height: Dim.e16),
        TextFormField(
          controller: _confirmacao,
          obscureText: true,
          style: Tipografia.corpo,
          decoration: const InputDecoration(labelText: 'Repetir a nova senha'),
          validator: (v) =>
              v != _senha.text ? 'As duas senhas precisam ser iguais.' : null,
        ),
        if (_erro != null) ...[
          const SizedBox(height: Dim.e16),
          Text(
            _erro!,
            style: Tipografia.corpoTabela.copyWith(color: cores.error),
          ),
        ],
        const SizedBox(height: Dim.e24),
        FilledButton(
          onPressed: _enviando ? null : () => _salvar(convite),
          child: const Text('Salvar senha'),
        ),
      ],
    ),
  );

  /// Os estados 2 e 3 do topo do arquivo: sem formulário, sempre com o
  /// caminho para um link novo — e com a sessão aberta nomeada, quando há.
  Widget _semFormulario(ColorScheme cores, UsuarioAutenticado? autenticado) {
    final erro = LinkInicial.erro;
    final (titulo, texto) = erro == null
        ? (tituloSemLink, textoSemLink)
        : (
            tituloLinkRecusado,
            erro == codigoLinkOutroNavegador
                ? textoLinkOutroNavegador
                : textoLinkVencido,
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.link_off, size: 40, color: cores.onSurfaceVariant),
        const SizedBox(height: Dim.e16),
        Text(titulo, style: Tipografia.titulo),
        const SizedBox(height: Dim.e8),
        Text(texto, style: Tipografia.corpo),
        if (erro != null) ...[
          const SizedBox(height: Dim.e8),
          Text(
            textoPecaOutroLink,
            style: Tipografia.corpo.copyWith(color: cores.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: Dim.e24),
        if (autenticado != null) ...[
          AvisoTonal(mensagem: textoSessaoAberta(autenticado.email)),
          const SizedBox(height: Dim.e16),
          FilledButton(onPressed: _sair, child: const Text('Sair')),
          const SizedBox(height: Dim.e8),
          OutlinedButton(
            onPressed: () => _irPara('/'),
            child: const Text('Voltar ao sistema'),
          ),
        ] else
          FilledButton(
            onPressed: () => _irPara(rotaLogin.caminho),
            child: const Text('Ir para a tela de entrada'),
          ),
      ],
    );
  }
}
