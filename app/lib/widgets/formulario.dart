import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../erros/erro_app.dart';
import '../theme/dimensoes.dart';
import '../theme/tipografia.dart';
import 'botoes.dart';

/// Abre [construtor] como diálogo (desktop/tablet, largura máxima
/// [largura]) ou em tela cheia (mobile) — design-system §5.4.
///
/// Devolve o que o conteúdo passar ao `Navigator.pop`; `null` quando a pessoa
/// fechou sem concluir.
Future<T?> mostrarFormulario<T>(
  BuildContext context, {
  required WidgetBuilder construtor,
  double largura = Dim.larguraFormularioMax,
}) {
  final mobile = faixaDe(MediaQuery.sizeOf(context).width) == Faixa.mobile;
  return showDialog<T>(
    context: context,
    builder: (contexto) => mobile
        ? Dialog.fullscreen(child: construtor(contexto))
        : Dialog(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: largura,
                maxHeight: MediaQuery.sizeOf(contexto).height - Dim.e32 * 2,
              ),
              child: construtor(contexto),
            ),
          ),
  );
}

/// Ação de rodapé além de "Salvar" (excluir, por exemplo). Roda com o mesmo
/// tratamento de erro do salvar; o que [executar] devolver, não nulo, fecha o
/// formulário com esse resultado.
class AcaoFormulario {
  const AcaoFormulario({
    required this.rotulo,
    required this.executar,
    this.exigePermissao,
    this.nivel = NivelBotao.secundario,
    this.confirmacao,
  });

  final String rotulo;
  final Future<Object?> Function() executar;
  final String? exigePermissao;
  final NivelBotao nivel;

  /// Confirmação destrutiva/consequente (design-system §5.8): diálogo com a
  /// consequência dita e o botão nomeando a ação, nunca "OK".
  final ConfirmacaoAcao? confirmacao;
}

class ConfirmacaoAcao {
  const ConfirmacaoAcao({
    required this.titulo,
    required this.mensagem,
    required this.rotulo,
  });

  final String titulo;
  final String mensagem;
  final String rotulo;
}

/// Chave do primário do [FormularioIm360] — enquanto executa ele troca o texto
/// por progresso, então quem precisa achá-lo acha pela chave.
const chaveBotaoSalvar = Key('formulario_salvar');

/// O formulário do sistema (design-system §5.4): rótulo em cima, obrigatórios
/// com `*` e a legenda uma vez no rodapé, **validação local só de formato**,
/// erro de regra como banner (pelo `codigo`, nunca pelo texto do banco), e o
/// primário travando reenvio enquanto executa.
///
/// A tela nunca pré-verifica regra de negócio: submete e trata o erro
/// (card 2.6 decisão 2).
class FormularioIm360 extends StatefulWidget {
  const FormularioIm360({
    super.key,
    required this.titulo,
    required this.chave,
    required this.campos,
    this.aoSalvar,
    this.rotuloSalvar = 'Salvar',
    this.aviso,
    this.acoes = const [],
    this.somenteLeitura = false,
    this.legendaObrigatorio = true,
  });

  final String titulo;
  final GlobalKey<FormState> chave;
  final List<Widget> campos;

  /// O que devolver fecha o formulário com esse resultado (`true` se nulo).
  final Future<Object?> Function()? aoSalvar;
  final String rotuloSalvar;

  /// Aviso de consequência, no par tonal de atenção, antes do botão
  /// (design-system §5.4).
  final String? aviso;

  final List<AcaoFormulario> acoes;

  /// Sem permissão de escrita a pessoa ainda pode **ver** — o botão de salvar
  /// não é renderizado (card 2.6 decisão 1), e "Fechar" substitui "Cancelar".
  final bool somenteLeitura;

  final bool legendaObrigatorio;

  @override
  State<FormularioIm360> createState() => _FormularioIm360State();
}

class _FormularioIm360State extends State<FormularioIm360> {
  bool _executando = false;
  String? _erro;

  Future<void> _salvar() async {
    final salvar = widget.aoSalvar;
    if (salvar == null) return;
    if (!widget.chave.currentState!.validate()) return;
    await _executar(() async => (await salvar()) ?? true);
  }

  Future<void> _acao(AcaoFormulario acao) async {
    final confirmacao = acao.confirmacao;
    if (confirmacao != null) {
      final confirmou = await showDialog<bool>(
        context: context,
        builder: (contexto) => AlertDialog(
          title: Text(confirmacao.titulo),
          content: Text(confirmacao.mensagem, style: Tipografia.corpo),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(contexto).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(contexto).pop(true),
              style: acao.nivel == NivelBotao.destrutivo
                  ? FilledButton.styleFrom(
                      backgroundColor: Theme.of(contexto).colorScheme.error,
                      foregroundColor: Theme.of(contexto).colorScheme.onError,
                    )
                  : null,
              child: Text(confirmacao.rotulo),
            ),
          ],
        ),
      );
      if (confirmou != true || !mounted) return;
    }
    await _executar(acao.executar);
  }

  Future<void> _executar(Future<Object?> Function() acao) async {
    setState(() {
      _executando = true;
      _erro = null;
    });
    try {
      final resultado = await acao();
      if (mounted && resultado != null) Navigator.of(context).pop(resultado);
    } catch (erro) {
      if (mounted) setState(() => _erro = traduzirErro(erro).mensagem);
    } finally {
      if (mounted) setState(() => _executando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final mobile = faixaDe(MediaQuery.sizeOf(context).width) == Faixa.mobile;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Dim.e24, Dim.e16, Dim.e12, Dim.e8),
          child: Row(
            children: [
              Expanded(child: Text(widget.titulo, style: Tipografia.subtitulo)),
              IconButton(
                tooltip: 'Fechar',
                icon: const Icon(Icons.close),
                onPressed: _executando
                    ? null
                    : () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Dim.e24),
            child: Form(
              key: widget.chave,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final campo in widget.campos) ...[
                    campo,
                    const SizedBox(height: Dim.e16),
                  ],
                  if (widget.aviso != null) ...[
                    AvisoTonal(mensagem: widget.aviso!),
                    const SizedBox(height: Dim.e16),
                  ],
                  if (_erro != null) ...[
                    AvisoTonal(mensagem: _erro!, erro: true),
                    const SizedBox(height: Dim.e16),
                  ],
                  if (widget.legendaObrigatorio && !widget.somenteLeitura)
                    Text(
                      '* obrigatório',
                      style: Tipografia.apoio.copyWith(
                        color: cores.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(Dim.e16),
          child: Row(
            children: [
              for (final acao in widget.acoes) ...[
                BotaoAcao(
                  rotulo: acao.rotulo,
                  nivel: acao.nivel,
                  exigePermissao: acao.exigePermissao,
                  aoTocar: _executando ? null : () => _acao(acao),
                ),
                const SizedBox(width: Dim.e8),
              ],
              const Spacer(),
              TextButton(
                onPressed: _executando
                    ? null
                    : () => Navigator.of(context).pop(),
                child: Text(widget.somenteLeitura ? 'Fechar' : 'Cancelar'),
              ),
              if (!widget.somenteLeitura && widget.aoSalvar != null) ...[
                const SizedBox(width: Dim.e8),
                SizedBox(
                  height: mobile ? Dim.alturaBotaoMobile : null,
                  child: FilledButton(
                    key: chaveBotaoSalvar,
                    onPressed: _executando ? null : _salvar,
                    child: _executando
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(widget.rotuloSalvar),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Banner tonal: atenção (padrão) ou erro. O mesmo par de cores do banner da
/// tela de login, componentizado uma vez.
class AvisoTonal extends StatelessWidget {
  const AvisoTonal({super.key, required this.mensagem, this.erro = false});

  final String mensagem;
  final bool erro;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(Dim.e12),
      decoration: BoxDecoration(
        color: erro ? cores.errorContainer : cores.tertiaryContainer,
        borderRadius: BorderRadius.circular(Dim.raio),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            erro ? Icons.error_outline : Icons.info_outline,
            size: 18,
            color: erro ? cores.error : cores.onTertiaryContainer,
          ),
          const SizedBox(width: Dim.e8),
          Expanded(
            child: Text(
              mensagem,
              style: Tipografia.corpoTabela.copyWith(
                color: erro ? cores.error : cores.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- validação local, só de formato (design-system §5.4) ---------------------

String? validarObrigatorio(String? valor) =>
    (valor == null || valor.trim().isEmpty) ? 'Campo obrigatório.' : null;

String? validarInteiroNaoNegativo(String? valor) {
  if (valor == null || valor.trim().isEmpty) return 'Campo obrigatório.';
  final numero = int.tryParse(valor.trim());
  if (numero == null || numero < 0) return 'Informe um número inteiro ≥ 0.';
  return null;
}

/// Só dígitos — para os campos numéricos.
final somenteDigitos = FilteringTextInputFormatter.digitsOnly;
