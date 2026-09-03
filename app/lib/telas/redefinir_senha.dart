import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/link_inicial.dart';
import '../erros/erro_app.dart';
import '../sessao/sessao_provider.dart';
import '../theme/dimensoes.dart';
import '../theme/tipografia.dart';

/// Destino do link de recuperação (card 3.5 §5) e do link de **convite**
/// (card 4.7). A pessoa chega aqui já com uma sessão criada pelo Auth; a tela
/// só define a senha — e diz, no caso do convite, que é isso que falta para
/// concluir o cadastro (achado do card 3.8: a mensagem tem de ser "defina sua
/// senha", não "esqueci minha senha").
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

class _TelaRedefinirSenhaState extends ConsumerState<TelaRedefinirSenha> {
  final _formulario = GlobalKey<FormState>();
  final _senha = TextEditingController();
  final _confirmacao = TextEditingController();
  bool _enviando = false;
  String? _erro;
  bool _pronto = false;

  @override
  void dispose() {
    _senha.dispose();
    _confirmacao.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formulario.currentState!.validate()) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await ref.read(sessaoRepositorioProvider).trocarSenha(_senha.text);
      await ref.read(sessaoProvider.notifier).recarregar();
      if (mounted) setState(() => _pronto = true);
    } catch (erro) {
      if (mounted) setState(() => _erro = traduzirErro(erro).mensagem);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _entrar() {
    // Senha definida: o convite deixa de estar pendente, e o roteador leva à
    // primeira tela que a pessoa pode abrir (ou a "sem perfil", que é a
    // verdade até alguém atribuir um).
    LinkInicial.consumir();
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final convite =
        LinkInicial.convitePendente ||
        GoRouterState.of(context).uri.queryParameters['motivo'] == 'convite';

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Dim.e24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: Dim.larguraFormularioMax,
            ),
            child: _pronto
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        convite ? 'Senha definida.' : 'Senha alterada.',
                        style: Tipografia.corpo,
                      ),
                      const SizedBox(height: Dim.e24),
                      FilledButton(
                        onPressed: _entrar,
                        child: const Text('Entrar no sistema'),
                      ),
                    ],
                  )
                : Form(
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
                            style: Tipografia.corpo.copyWith(
                              color: cores.onSurfaceVariant,
                            ),
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
                            helperText:
                                'Ao menos 8 caracteres, com letras e números.',
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
                          decoration: const InputDecoration(
                            labelText: 'Repetir a nova senha',
                          ),
                          validator: (v) => v != _senha.text
                              ? 'As duas senhas precisam ser iguais.'
                              : null,
                        ),
                        if (_erro != null) ...[
                          const SizedBox(height: Dim.e16),
                          Text(
                            _erro!,
                            style: Tipografia.corpoTabela.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: Dim.e24),
                        FilledButton(
                          onPressed: _enviando ? null : _salvar,
                          child: const Text('Salvar senha'),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
