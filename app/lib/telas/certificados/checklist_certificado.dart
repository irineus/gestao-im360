import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../certificados/certificados.dart';
import '../../certificados/certificados_provider.dart';
import '../../erros/erro_app.dart';
import '../../sessao/sessao_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../util/datas.dart';
import '../../widgets/confirmacao.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';

/// O checklist do certificado (docs/wireframes.md §12.2) — **um** componente,
/// usado no painel da tela 9 e embutido na aba Certificado da ficha do aluno
/// (§6.6). O wireframe diz literalmente "mesmo componente", e as duas jornadas
/// são diferentes: a fila é "quem está chegando ao fim", a ficha é "este aluno".
///
/// ⚠️ **Cada caixa é guardada pela permissão do PRÓPRIO item** (card 2.2 §8), e
/// não pela permissão de mexer no checklist: o monitor vê o checklist inteiro e
/// só a caixa Financeiro é interativa para ele. É por isso que o item sem
/// permissão vira um indicador de leitura em vez de sumir — a regra de §5.7 do
/// design-system fala de **botão**, e aqui o que está na tela é informação, que
/// esconder deixaria o monitor sem saber se o pedagógico já assinou.
///
/// ⚠️ **A tela não pré-verifica regra nenhuma** (card 2.6, decisão 2): marca,
/// e trata o erro pelo `codigo`. Em especial, não há máquina de estados no
/// seletor de status — a volta `ENTREGUE` → `PEDIDO` é permitida de propósito
/// (card 8.3), e quem decide é `fn_certificado_status`.
class BlocoChecklist extends ConsumerStatefulWidget {
  const BlocoChecklist({super.key, required this.alunoId});

  final String alunoId;

  @override
  ConsumerState<BlocoChecklist> createState() => _BlocoChecklistState();
}

class _BlocoChecklistState extends ConsumerState<BlocoChecklist> {
  /// Erro da última escrita, já traduzido. Fica **dentro** do bloco: o checklist
  /// continua na tela, e o que falhou foi uma marca.
  String? _erro;

  /// Trava o reenvio enquanto a escrita corre — duplo clique não manda duas
  /// marcações (design-system §5.4).
  bool _executando = false;

  Future<void> _escrever(
    Future<void> Function() acao,
    String confirmacao,
  ) async {
    if (_executando) return;
    setState(() {
      _executando = true;
      _erro = null;
    });
    try {
      await acao();
      ref.read(versaoCertificadosProvider.notifier).incrementar();
      if (mounted) confirmarEfemero(context, confirmacao);
    } catch (erro) {
      final traduzido = erro is ErroApp ? erro : traduzirErro(erro);
      if (mounted) setState(() => _erro = traduzido.mensagem);
    } finally {
      if (mounted) setState(() => _executando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final checklist = ref.watch(checklistAlunoProvider(widget.alunoId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_erro != null) ...[
          AvisoTonal(mensagem: _erro!, erro: true),
          const SizedBox(height: Dim.e16),
        ],
        checklist.when(
          loading: () => const EstadoCarregando(linhas: 3),
          error: (erro, _) {
            final traduzido = erro is ErroApp ? erro : traduzirErro(erro);
            return EstadoErro(
              mensagem: traduzido.mensagem,
              codigoTecnico: traduzido.traduzido ? null : traduzido.codigo,
              aoRepetir: ref
                  .read(versaoCertificadosProvider.notifier)
                  .incrementar,
            );
          },
          data: (dados) =>
              dados == null ? _semChecklist() : _checklist(context, dados),
        ),
      ],
    );
  }

  /// O aluno está na fila e ainda não tem checklist — o caso normal de quem está
  /// no último livro. Não é vazio de erro nem de filtro: é um passo que ainda
  /// não aconteceu, e a tela oferece adiantá-lo.
  Widget _semChecklist() => EstadoVazio(
    mensagem: explicacaoSemChecklist,
    icone: Icons.workspace_premium_outlined,
    rotuloAcao: ref.watch(permissoesProvider).contains('certificados.criar')
        ? 'Abrir checklist'
        : null,
    aoAgir: () => _escrever(
      () => ref
          .read(certificadosRepositorioProvider)
          .abrirChecklist(widget.alunoId),
      confirmacaoChecklistAberto,
    ),
  );

  Widget _checklist(BuildContext context, ChecklistCertificado dados) {
    final cores = Theme.of(context).colorScheme;
    final permissoes = ref.watch(permissoesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Fim do curso: ${formatarData(dados.dataFimCurso)}',
          style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
        ),
        const SizedBox(height: Dim.e8),
        for (final item in ItemChecklist.values)
          _LinhaItem(
            item: item,
            marcado: dados.marca(item),
            autoria: dados.autoria(item),
            podeMarcar: permissoes.contains(item.permissao),
            executando: _executando,
            aoMarcar: (valor) => _escrever(
              () => ref
                  .read(certificadosRepositorioProvider)
                  .marcarItem(widget.alunoId, item: item.codigo, valor: valor),
              confirmacaoItemMarcado,
            ),
          ),
        const Divider(height: Dim.e24),
        _Status(
          status: dados.certificadoStatus,
          autoria: dados.autoriaStatus,
          podeAlterar: permissoes.contains('certificados.alterar_status'),
          executando: _executando,
          aoEscolher: (status) => _escrever(
            () => ref
                .read(certificadosRepositorioProvider)
                .alterarStatus(widget.alunoId, status: status),
            confirmacaoStatusAlterado,
          ),
        ),
        const SizedBox(height: Dim.e16),
        // A nota do wireframe §12.2: o sistema SUGERE, e quem forma é uma
        // pessoa. Depois que a condição fecha, o texto muda — dizer "vai
        // sugerir" sobre algo que já foi sugerido manda procurar no lugar errado.
        AvisoTonal(
          mensagem: dados.completo ? avisoFormadoSugerido : avisoSugereFormado,
        ),
      ],
    );
  }
}

/// Uma linha do checklist: a caixa (ou o indicador, sem permissão), o rótulo e
/// o "quem/quando" ao lado.
class _LinhaItem extends StatelessWidget {
  const _LinhaItem({
    required this.item,
    required this.marcado,
    required this.autoria,
    required this.podeMarcar,
    required this.executando,
    required this.aoMarcar,
  });

  final ItemChecklist item;
  final bool marcado;
  final AutoriaItem autoria;
  final bool podeMarcar;
  final bool executando;
  final ValueChanged<bool> aoMarcar;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final rotuloQuem = rotuloAutoria(autoria, formatarData);

    return ConstrainedBox(
      // Alvo de 44 px nas jornadas do celular (design-system §8.4) — a caixa
      // Financeiro é a jornada nº 2 do monitor.
      constraints: const BoxConstraints(minHeight: Dim.alvoMobile),
      child: Row(
        children: [
          if (podeMarcar)
            Checkbox(
              value: marcado,
              onChanged: executando
                  ? null
                  : (valor) => aoMarcar(valor ?? false),
              semanticLabel: item.rotulo,
            )
          else
            // Sem permissão de marcar, o item continua VISÍVEL: o monitor
            // precisa saber se o pedagógico já assinou. O ícone com forma
            // própria carrega o estado — cor nunca é portadora única
            // (design-system §8.2).
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Dim.e12),
              child: Semantics(
                label: '${item.rotulo}: ${marcado ? 'marcado' : 'pendente'}',
                excludeSemantics: true,
                child: Icon(
                  marcado
                      ? Icons.check_box_outlined
                      : Icons.check_box_outline_blank,
                  size: 20,
                  color: cores.onSurfaceVariant,
                ),
              ),
            ),
          Expanded(child: Text(item.rotulo, style: Tipografia.corpo)),
          const SizedBox(width: Dim.e8),
          Flexible(
            child: Text(
              rotuloQuem,
              textAlign: TextAlign.end,
              style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// O status do certificado: `NÃO PEDIDO ▸ PEDIDO ▸ ENTREGUE` (wireframe §12.2).
///
/// ⚠️ Sem `certificados.alterar_status` o status vira texto, e não um seletor
/// desabilitado: permissão não destrava na tela (card 2.6, decisão 1), e um
/// controle apagado sugeriria que preencher algo o destrava.
class _Status extends StatelessWidget {
  const _Status({
    required this.status,
    required this.autoria,
    required this.podeAlterar,
    required this.executando,
    required this.aoEscolher,
  });

  final String status;
  final AutoriaItem autoria;
  final bool podeAlterar;
  final bool executando;
  final ValueChanged<String> aoEscolher;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Status do certificado',
          style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
        ),
        const SizedBox(height: Dim.e4),
        if (podeAlterar)
          // `Wrap` e não `Row`: em 390 px os três segmentos com os rótulos por
          // extenso não cabem numa linha, e um `SegmentedButton` dentro de uma
          // `Row` sem folga estoura à direita (design-system §11, item 19).
          Wrap(
            spacing: Dim.e8,
            runSpacing: Dim.e8,
            children: [
              for (final codigo in statusDoCertificado)
                ChoiceChip(
                  label: Text(rotuloStatusCertificado(codigo)),
                  selected: status == codigo,
                  onSelected: (escolhido) {
                    if (executando || !escolhido || status == codigo) return;
                    aoEscolher(codigo);
                  },
                ),
            ],
          )
        else
          Text(rotuloStatusCertificado(status), style: Tipografia.corpo),
        const SizedBox(height: Dim.e4),
        Text(
          rotuloAutoria(autoria, formatarData),
          style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// A aba Certificado da ficha do aluno (docs/wireframes.md §6.6) — o mesmo
/// bloco, com a rolagem e o respiro da ficha em volta.
class AbaCertificado extends StatelessWidget {
  const AbaCertificado({super.key, required this.alunoId});

  final String alunoId;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(Dim.e16),
    children: [BlocoChecklist(alunoId: alunoId)],
  );
}
