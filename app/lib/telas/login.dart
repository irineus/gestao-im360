import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/ambiente.dart';
import '../erros/erro_app.dart';
import '../sessao/sessao_provider.dart';
import '../theme/dimensoes.dart';
import '../theme/tipografia.dart';
import '../widgets/marca.dart';

/// Tela 1 — login (docs/wireframes.md §4).
///
/// Sem cadastro público: usuário é convidado pela direção (card 3.5 §3).
class TelaLogin extends ConsumerStatefulWidget {
  const TelaLogin({super.key});

  @override
  ConsumerState<TelaLogin> createState() => _TelaLoginState();
}

/// A pista que faltava (achado do card 3.8, fechado no 4.7): quem chegou por
/// convite e fechou a página sem definir a senha cai aqui, e a credencial
/// inválida é indistinguível de senha errada — a saída é o link de
/// redefinição, e a tela agora diz isso.
const dicaConviteSemSenha =
    'Chegou por convite e ainda não definiu a senha? Use "Esqueci minha '
    'senha" para criá-la.';

class _TelaLoginState extends ConsumerState<TelaLogin> {
  final _formulario = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _senha = TextEditingController();
  bool _mostrarSenha = false;
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (!_formulario.currentState!.validate()) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await ref
          .read(sessaoProvider.notifier)
          .entrar(email: _email.text, senha: _senha.text);
    } catch (erro) {
      if (mounted) setState(() => _erro = traduzirErro(erro).mensagem);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _esqueciSenha() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _erro = 'Informe o e-mail para receber o link.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await ref
          .read(sessaoRepositorioProvider)
          .recuperarSenha(
            email,
            redirecionarPara: Ambiente.urlRedefinicaoSenha,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Se este e-mail estiver cadastrado, o link de redefinição foi enviado.',
            ),
          ),
        );
      }
    } catch (erro) {
      if (mounted) setState(() => _erro = traduzirErro(erro).mensagem);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Dim.e24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: Dim.larguraFormularioMax,
            ),
            child: Form(
              key: _formulario,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: SimboloIm360(lado: 72)),
                  const SizedBox(height: Dim.e16),
                  const Center(child: AssinaturaIm360(lado: 28, comNome: true)),
                  const SizedBox(height: Dim.e32),
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(labelText: 'E-mail'),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                    textInputAction: TextInputAction.next,
                    // Corpo 16 px sempre: evita o zoom automático do iOS
                    // (card 1.9 §4).
                    style: Tipografia.corpo,
                    validator: (v) => (v == null || !v.contains('@'))
                        ? 'Informe um e-mail válido.'
                        : null,
                  ),
                  const SizedBox(height: Dim.e16),
                  TextFormField(
                    controller: _senha,
                    decoration: InputDecoration(
                      labelText: 'Senha',
                      suffixIcon: IconButton(
                        tooltip: _mostrarSenha
                            ? 'Ocultar senha'
                            : 'Mostrar senha',
                        icon: Icon(
                          _mostrarSenha
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () =>
                            setState(() => _mostrarSenha = !_mostrarSenha),
                      ),
                    ),
                    obscureText: !_mostrarSenha,
                    autofillHints: const [AutofillHints.password],
                    style: Tipografia.corpo,
                    onFieldSubmitted: (_) => _entrar(),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Informe a senha.' : null,
                  ),
                  if (_erro != null) ...[
                    const SizedBox(height: Dim.e16),
                    Container(
                      padding: const EdgeInsets.all(Dim.e12),
                      decoration: BoxDecoration(
                        color: cores.errorContainer,
                        borderRadius: BorderRadius.circular(Dim.raio),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _erro!,
                            style: Tipografia.corpoTabela.copyWith(
                              color: cores.error,
                            ),
                          ),
                          if (_erro == mensagemCredencialInvalida) ...[
                            const SizedBox(height: Dim.e4),
                            Text(
                              dicaConviteSemSenha,
                              style: Tipografia.apoio.copyWith(
                                color: cores.error,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: Dim.e24),
                  FilledButton(
                    onPressed: _enviando ? null : _entrar,
                    child: _enviando
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Entrar'),
                  ),
                  const SizedBox(height: Dim.e8),
                  TextButton(
                    onPressed: _enviando ? null : _esqueciSenha,
                    child: const Text('Esqueci minha senha'),
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
