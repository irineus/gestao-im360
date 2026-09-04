import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../alunos/alunos.dart';
import '../../catalogo/catalogo.dart';
import '../../catalogo/catalogo_provider.dart';
import '../../erros/erro_app.dart';
import '../../pendencias/pendencias_provider.dart';
import '../../rotas/rotas.dart';
import '../../sessao/sessao_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../trilha/trilha.dart';
import '../../trilha/trilha_provider.dart';
import '../../widgets/botoes.dart';
import '../../widgets/confirmacao.dart';
import '../../widgets/dialogo_resultado.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';
import '../../widgets/painel_detalhe.dart';
import 'formularios_trilha.dart';

/// Aba **Trilha** da ficha do aluno (docs/wireframes.md §6.3), card 6.6.
///
/// É a **jornada nº 1 do monitor** (card 2.6 §3.2): aluno → ficha → Trilha →
/// Registrar entrega, e no celular. Por isso o botão de entrega fica em largura
/// total no rodapé do mobile, com 48 px de altura, e o resultado abre em folha
/// inferior.
///
/// ⚠️ **A aba não pré-verifica saldo** (card 2.6 decisão 2, wireframe §17): o
/// "est. 7" ao lado da próxima é informativo e vem da view; quem decide —
/// entregar, reordenar por falta de estoque ou bloquear — é
/// `fn_registrar_entrega`, dentro da transação e com o advisory lock que a
/// corrida do último exemplar exige. A tela distingue os TRÊS status do retorno
/// e não some com nenhum deles.
///
/// ⚠️ **A aba exige `estoque.ler`, que a rota da ficha não exige** (rota 3b do
/// card 2.4 §6, `rotaAlunoTrilha` em `rotas.dart`). Sem ela o saldo viria 0 em
/// toda linha, **sem erro nenhum**, e toda entrega seria recusada por falta de
/// um estoque que existe. É a mesma decisão da aba Turmas com `turmas.ler`
/// (card 5.7): a aba diz o que falta em vez de mostrar a lista mentindo.
class AbaTrilha extends ConsumerStatefulWidget {
  const AbaTrilha({super.key, required this.aluno});

  final Aluno aluno;

  @override
  ConsumerState<AbaTrilha> createState() => _AbaTrilhaState();
}

class _AbaTrilhaState extends ConsumerState<AbaTrilha> {
  /// O "modo de edição" do wireframe §6.3: enquanto ligado, cada item ganha as
  /// ações de mover e remover. Desligado por padrão porque a ação diária é
  /// entregar, e editar a trilha é rara — deixar as duas no mesmo peso faria a
  /// pessoa procurar o botão de entrega entre setas.
  bool _editando = false;

  Aluno get _aluno => widget.aluno;

  String _nomeDoMaterial(String? id) {
    if (id == null) return '—';
    final materiais =
        ref.read(materiaisProvider).value ?? const <MaterialDidatico>[];
    for (final m in materiais) {
      if (m.id == id) return '${m.codigo} ${m.nome}';
    }
    return '—';
  }

  Future<void> _abrirEConfirmar(WidgetBuilder construtor) async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: construtor,
    );
    if (resultado != null && mounted) confirmarEfemero(context, resultado);
  }

  /// A entrega: um botão, uma chamada, três resultados possíveis.
  ///
  /// O erro (aluno inativo, sem permissão, trilha em fim) chega como exceção e
  /// vira o mesmo diálogo, com o texto do catálogo pelo `codigo` — nunca pelo
  /// texto do banco (card 2.2 §1.2).
  Future<void> _registrarEntrega() async {
    try {
      final resultado = await ref
          .read(trilhaRepositorioProvider)
          .registrarEntrega(_aluno.id!);
      // A entrega abre `COMPRA_SEM_ESTOQUE`/`ESTOQUE_ZERO` e fecha
      // `ULTIMO_LIVRO`: recarregar a central junto é o que impede o diálogo de
      // mandar "Ver pendência" para uma lista que ainda não a tem.
      ref.read(versaoTrilhaProvider.notifier).incrementar();
      ref.read(versaoPendenciasProvider.notifier).incrementar();
      if (!mounted) return;

      final texto = textoResultadoEntrega(
        resultado,
        nomeDoMaterial: _nomeDoMaterial,
      );
      await mostrarResultado(
        context,
        titulo: texto.titulo,
        mensagem: texto.mensagem,
        tom: switch (resultado.status) {
          StatusEntrega.entregue => TomResultado.sucesso,
          StatusEntrega.reordenada => TomResultado.atencao,
          StatusEntrega.bloqueadaSemEstoque => TomResultado.alerta,
        },
        links: [
          if (resultadoTemPendencia(resultado))
            LinkResultado(
              rotulo: 'Ver pendência',
              aoTocar: () => context.go(caminhoDeRota('pendencias')),
            ),
          if (resultado.emFim)
            LinkResultado(
              rotulo: 'Ver checklist',
              aoTocar: () =>
                  context.go(caminhoFichaAluno(_aluno.id!, aba: 'certificado')),
            ),
        ],
      );
    } catch (erro) {
      final traduzido = erro is ErroApp ? erro : traduzirErro(erro);
      if (!mounted) return;
      await mostrarResultado(
        context,
        titulo: 'A entrega não foi registrada',
        mensagem: traduzido.mensagem,
        tom: TomResultado.alerta,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final permissoes = ref.watch(permissoesProvider);
    final faltando = permissoesFaltantes(rotaAlunoTrilha, permissoes);
    if (faltando.isNotEmpty) {
      return EstadoSemAcesso(texto: semAcessoTrilha, faltando: faltando);
    }

    // O catálogo é observado aqui, e não só lido no `_nomeDoMaterial`: o
    // `ref.read` de um `FutureProvider` que ninguém observa devolve `null` para
    // sempre — a busca nunca começa —, e os três diálogos de resultado sairiam
    // dizendo "— foi entregue". Medido no `tela_trilha_test`.
    ref.watch(materiaisProvider);

    final trilha = ref.watch(trilhaAlunoProvider(_aluno.id!));
    return trilha.when(
      loading: () => const EstadoCarregando(linhas: 5),
      error: (erro, _) {
        final traduzido = erro is ErroApp ? erro : traduzirErro(erro);
        return EstadoErro(
          mensagem: traduzido.mensagem,
          codigoTecnico: traduzido.traduzido ? null : traduzido.codigo,
          aoRepetir: ref.read(versaoTrilhaProvider.notifier).incrementar,
        );
      },
      data: _corpo,
    );
  }

  Widget _corpo(List<ItemTrilha> itens) {
    final podeEditar = ref
        .watch(permissoesProvider)
        .contains('alunos.editar_trilha');

    if (itens.isEmpty) {
      return EstadoVazio(
        mensagem: vazioTrilha,
        icone: Icons.menu_book_outlined,
        rotuloAcao: podeEditar ? 'Editar trilha' : null,
        aoAgir: () =>
            _abrirEConfirmar((_) => FormularioGerarTrilha(aluno: _aluno)),
      );
    }

    final resumo = resumirTrilha(itens);
    final proxima = proximoDaTrilha(itens);
    final mobile = faixaDe(MediaQuery.sizeOf(context).width) == Faixa.mobile;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(Dim.e16),
            children: [
              _Cabecalho(
                aluno: _aluno,
                resumo: resumo,
                editando: _editando,
                aoAlternarEdicao: () => setState(() => _editando = !_editando),
              ),
              if (_editando) ...[
                const SizedBox(height: Dim.e8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: BotaoAcao(
                    rotulo: 'Incluir apostila',
                    icone: Icons.add,
                    nivel: NivelBotao.secundario,
                    exigePermissao: 'alunos.editar_trilha',
                    aoTocar: () => _abrirEConfirmar(
                      (_) => FormularioIncluirNaTrilha(
                        aluno: _aluno,
                        trilha: itens,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: Dim.e12),
              for (final item in itens)
                _LinhaItem(
                  item: item,
                  total: itens.length,
                  editando: _editando,
                  // No desktop a ação da entrega mora na linha da próxima,
                  // como o wireframe desenha. No mobile ela é o rodapé fixo:
                  // repetir os dois deixaria dois botões primários na mesma
                  // tela, e o §5.7 pede um por região.
                  aoEntregar: mobile || !item.proximo
                      ? null
                      : _registrarEntrega,
                  aoEstornar: () => _abrirEConfirmar(
                    (_) => FormularioEstornarEntrega(item: item),
                  ),
                  aoMover: (destino) async {
                    final texto = await moverNaTrilha(
                      ref,
                      alunoId: _aluno.id!,
                      item: item,
                      novaPosicao: destino,
                    );
                    if (mounted) confirmarEfemero(context, texto);
                  },
                  aoMoverPara: () => _abrirEConfirmar(
                    (_) => FormularioReordenarTrilha(
                      aluno: _aluno,
                      item: item,
                      total: itens.length,
                    ),
                  ),
                  aoRemover: () => _abrirEConfirmar(
                    (_) => FormularioRemoverDaTrilha(aluno: _aluno, item: item),
                  ),
                ),
            ],
          ),
        ),
        if (mobile)
          _RodapeEntrega(
            aluno: _aluno,
            proxima: proxima,
            emFim: resumo.emFim,
            aoEntregar: _registrarEntrega,
          ),
      ],
    );
  }
}

/// Cabeçalho da aba: combo, contagem e o botão que liga o modo de edição.
class _Cabecalho extends StatelessWidget {
  const _Cabecalho({
    required this.aluno,
    required this.resumo,
    required this.editando,
    required this.aoAlternarEdicao,
  });

  final Aluno aluno;
  final ResumoTrilha resumo;
  final bool editando;
  final VoidCallback aoAlternarEdicao;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: TituloSecao(
          texto: 'Trilha',
          apoio:
              '${resumo.texto}. A ordem é a do combo; "próxima" é derivada, '
              'nunca digitada.',
        ),
      ),
      const SizedBox(width: Dim.e8),
      BotaoAcao(
        rotulo: editando ? 'Concluir edição' : 'Editar trilha',
        icone: editando ? Icons.done : Icons.edit_outlined,
        nivel: NivelBotao.secundario,
        exigePermissao: 'alunos.editar_trilha',
        aoTocar: aoAlternarEdicao,
      ),
    ],
  );
}

/// Uma apostila da trilha.
///
/// ⚠️ **Cor não é portadora única** (design-system §8.2): cada situação tem
/// ícone com forma própria (✓, ►, ○) e a palavra ao lado.
class _LinhaItem extends StatelessWidget {
  const _LinhaItem({
    required this.item,
    required this.total,
    required this.editando,
    required this.aoEntregar,
    required this.aoEstornar,
    required this.aoMover,
    required this.aoMoverPara,
    required this.aoRemover,
  });

  final ItemTrilha item;
  final int total;
  final bool editando;
  final VoidCallback? aoEntregar;
  final VoidCallback aoEstornar;
  final void Function(int novaPosicao) aoMover;
  final VoidCallback aoMoverPara;
  final VoidCallback aoRemover;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final situacao = situacaoDe(item);
    final (icone, cor) = switch (situacao) {
      SituacaoItem.entregue => (Icons.check_circle_outline, cores.primary),
      SituacaoItem.proxima => (Icons.play_circle_outline, cores.tertiary),
      SituacaoItem.pendente => (Icons.circle_outlined, cores.onSurfaceVariant),
    };

    return Semantics(
      label:
          'Apostila ${item.posicao} de $total, ${item.rotulo}, '
          '${rotuloSituacao(item)}',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: Dim.alvoMobile),
        padding: const EdgeInsets.symmetric(vertical: Dim.e8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: cores.outlineVariant, width: 1),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 32,
              child: Text(
                '${item.posicao}',
                style: Tipografia.numero(Tipografia.corpoTabela)
                    .copyWith(color: cores.onSurfaceVariant),
              ),
            ),
            Icon(icone, size: 18, color: cor),
            const SizedBox(width: Dim.e8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.rotulo,
                    style: item.proximo
                        ? Tipografia.corpoTabela.copyWith(
                            fontWeight: FontWeight.w600,
                          )
                        : Tipografia.corpoTabela,
                  ),
                  Text(
                    [
                      rotuloSituacao(item),
                      if (item.manual) 'incluída à mão',
                    ].join(' · '),
                    style: Tipografia.apoio.copyWith(
                      color: cores.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Dim.e8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: Dim.e4,
              runSpacing: Dim.e4,
              children: [
                if (aoEntregar != null)
                  BotaoAcao(
                    rotulo: 'Registrar entrega',
                    exigePermissao: 'estoque.lancar_saida',
                    aoTocar: aoEntregar,
                  ),
                // ⚠️ Divergência do wireframe §6.3, registrada no §17: o desenho
                // oferece [Estornar] só nas "entregas recentes". Aqui ele
                // aparece em TODA entrega com movimento vinculado — "recente"
                // não tem definição no modelo, e esconder o botão nas antigas
                // deixaria uma correção sem tela nenhuma (o mesmo buraco que o
                // card 5.7 fechou no bloco desativado). Estornar duas vezes
                // continua impossível: `movimento_estorno_uk` e o
                // MOVIMENTO_JA_ESTORNADO do card 6.3.
                if (item.entregue)
                  BotaoAcao(
                    rotulo: 'Estornar',
                    nivel: NivelBotao.terciario,
                    exigePermissao: 'estoque.estornar',
                    desabilitado: item.estornavel
                        ? null
                        : const DesabilitadoCom(motivoSemMovimento),
                    aoTocar: aoEstornar,
                  ),
                if (editando && !item.entregue) ...[
                  _BotaoSeta(
                    icone: Icons.arrow_upward,
                    dica: 'Subir uma posição',
                    aoTocar: item.posicao <= 1
                        ? null
                        : () => aoMover(item.posicao - 1),
                  ),
                  _BotaoSeta(
                    icone: Icons.arrow_downward,
                    dica: 'Descer uma posição',
                    aoTocar: item.posicao >= total
                        ? null
                        : () => aoMover(item.posicao + 1),
                  ),
                  BotaoAcao(
                    rotulo: 'Mover para…',
                    nivel: NivelBotao.terciario,
                    exigePermissao: 'alunos.editar_trilha',
                    aoTocar: aoMoverPara,
                  ),
                  BotaoAcao(
                    rotulo: 'Remover',
                    nivel: NivelBotao.terciario,
                    exigePermissao: 'alunos.editar_trilha',
                    aoTocar: aoRemover,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Seta de reordenação — 44 px de alvo (design-system §8.4) e `tooltip` que é
/// também o rótulo da leitura de tela, porque um ícone sozinho não anuncia nada.
class _BotaoSeta extends StatelessWidget {
  const _BotaoSeta({
    required this.icone,
    required this.dica,
    required this.aoTocar,
  });

  final IconData icone;
  final String dica;
  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: Dim.alvoMobile,
    height: Dim.alvoMobile,
    child: IconButton(
      icon: Icon(icone, size: 18),
      tooltip: dica,
      onPressed: aoTocar,
    ),
  );
}

/// O rodapé do mobile: a ação da jornada nº 1, em largura total, 48 px, sempre
/// visível (wireframe §6.3). Sem estado para entregar, o botão fica **visível e
/// desabilitado com o motivo** — decisão 1 do card 2.6: sem estado, não sem
/// permissão.
class _RodapeEntrega extends StatelessWidget {
  const _RodapeEntrega({
    required this.aluno,
    required this.proxima,
    required this.emFim,
    required this.aoEntregar,
  });

  final Aluno aluno;
  final ItemTrilha? proxima;
  final bool emFim;
  final VoidCallback aoEntregar;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final motivo = !aluno.emAula
        ? motivoAlunoInativo
        : emFim
        ? motivoTrilhaEmFim
        : proxima == null
        ? motivoTrilhaVazia
        : null;

    return Container(
      padding: const EdgeInsets.all(Dim.e12),
      decoration: BoxDecoration(
        color: cores.surface,
        border: Border(top: BorderSide(color: cores.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (proxima != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Dim.e8),
                child: Text(
                  'Próxima: ${proxima!.rotulo}',
                  style: Tipografia.apoio.copyWith(
                    color: cores.onSurfaceVariant,
                  ),
                ),
              ),
            // `minHeight`, e não altura fixa: com o botão desabilitado o
            // `BotaoAcao` acrescenta a legenda do motivo embaixo (§5.7), e uma
            // altura fixa de 48 px a cortava — o motivo existia e não se lia,
            // que é o mesmo defeito de não ter motivo nenhum.
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: Dim.alturaBotaoMobile,
              ),
              child: BotaoAcao(
                rotulo: 'Registrar entrega',
                icone: Icons.local_library_outlined,
                exigePermissao: 'estoque.lancar_saida',
                desabilitado: motivo == null ? null : DesabilitadoCom(motivo),
                aoTocar: aoEntregar,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
