import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalogo/catalogo.dart';
import '../../catalogo/catalogo_provider.dart';
import '../../certificados/certificados.dart';
import '../../certificados/certificados_provider.dart';
import '../../erros/erro_app.dart';
import '../../sessao/sessao_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../util/datas.dart';
import '../../widgets/badge_status.dart';
import '../../widgets/barra_filtros.dart';
import '../../widgets/confirmacao.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';
import '../../widgets/painel_detalhe.dart';
import '../../widgets/tabela_im360.dart';
import 'checklist_certificado.dart';

/// Tela 9 — Certificados (docs/wireframes.md §12).
///
/// Responde "quem está chegando ao fim do curso, e o que falta para o
/// certificado sair". A fila traz **as duas situações** — último livro (um item
/// pendente, ainda com aula pela frente) e fim do curso (nenhum) —, com rótulos
/// distintos, porque é a primeira que dá tempo de pedir o certificado.
///
/// Rota: `certificados.ler + alunos.ler + materiais.ler`
/// (docs/permissoes-matriz.md §6, linha 9). O `materiais.ler` entrou neste card:
/// `v_certificado_fila` junta `metodo` internamente para o filtro por método, e
/// sem ele a fila não vem errada, vem **vazia** (card 2.3 §3.4). Os quatro
/// perfis já o têm, então nenhum perfil perde a tela.
class TelaCertificados extends ConsumerStatefulWidget {
  const TelaCertificados({super.key, this.alunoId});

  /// `?aluno=<id>` — o mesmo desenho de `?material=` na tela 6 e de `?turma=` na
  /// 5: a tela abre já com o checklist daquele aluno em vez de largar a pessoa
  /// na fila inteira.
  final String? alunoId;

  @override
  ConsumerState<TelaCertificados> createState() => _TelaCertificadosState();
}

class _TelaCertificadosState extends ConsumerState<TelaCertificados> {
  /// O aluno que veio na URL e ainda não foi aberto. Zerado depois de abrir,
  /// senão fechar o painel o reabriria em seguida.
  String? _pendenteDaUrl;

  @override
  void initState() {
    super.initState();
    _pendenteDaUrl = widget.alunoId;
  }

  @override
  void didUpdateWidget(TelaCertificados anterior) {
    super.didUpdateWidget(anterior);
    if (widget.alunoId != null && widget.alunoId != anterior.alunoId) {
      _pendenteDaUrl = widget.alunoId;
    }
  }

  Future<void> _abrir(LinhaFilaCertificado linha) => mostrarFormulario<void>(
    context,
    largura: larguraDetalhe,
    construtor: (_) => _PainelChecklist(linha: linha),
  );

  /// A caixa Financeiro acionável **na própria lista** — a jornada nº 2 do
  /// monitor (wireframe §12.2): marcar "financeiro OK" sem abrir o checklist
  /// completo.
  Future<void> _marcarFinanceiro(LinhaFilaCertificado linha, bool valor) async {
    try {
      await ref
          .read(certificadosRepositorioProvider)
          .marcarItem(
            linha.alunoId,
            item: ItemChecklist.financeiro.codigo,
            valor: valor,
          );
      ref.read(versaoCertificadosProvider.notifier).incrementar();
      if (mounted) confirmarEfemero(context, confirmacaoItemMarcado);
    } catch (erro) {
      final traduzido = erro is ErroApp ? erro : traduzirErro(erro);
      // Erro de uma marca não derruba a fila: a mensagem é efêmera e a lista
      // continua onde estava.
      if (mounted) confirmarEfemero(context, traduzido.mensagem);
    }
  }

  @override
  Widget build(BuildContext context) {
    final metodos = ref.watch(metodosProvider).value ?? const <Metodo>[];
    final fila = ref.watch(filaCertificadosProvider);
    final filtro = ref.watch(filtroCertificadosProvider);
    final permissoes = ref.watch(permissoesProvider);
    final podeMarcarFinanceiro = permissoes.contains(
      ItemChecklist.financeiro.permissao,
    );

    final todas = fila.value ?? const <LinhaFilaCertificado>[];
    final linhas = filtrarFila(todas, filtro);

    // Chegou por `?aluno=`: abre o painel assim que a fila tiver dado, uma vez.
    final pendente = _pendenteDaUrl;
    if (pendente != null && fila.hasValue) {
      _pendenteDaUrl = null;
      final alvo = todas.where((l) => l.alunoId == pendente);
      if (alvo.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _abrir(alvo.first);
        });
      }
    }

    return TabelaIm360<LinhaFilaCertificado>(
      filtros: _FiltrosCertificados(
        filtro: filtro,
        metodos: metodos,
        situacoes: situacoesPresentes(todas),
      ),
      filtrosAtivos: filtro.ativos,
      colunas: [
        ColunaIm360(
          titulo: 'Aluno',
          texto: (l) => l.rotuloAluno,
          flex: 3,
          larguraMin: 200,
        ),
        ColunaIm360(
          titulo: 'Método',
          texto: (l) => l.metodoNome,
          prioridade: 4,
          larguraMin: 120,
        ),
        ColunaIm360(
          titulo: 'Situação',
          texto: (l) => rotuloSituacao(l.situacao),
          celula: (l) => _Situacao(situacao: l.situacao),
          flex: 2,
          larguraMin: 130,
        ),
        // ⚠️ O wireframe §12.1 desenha `P ✓ F ✓ Fo ─`. O `✓` não vai para a
        // tela — o app empacota só Inter e Roboto, e a CSP impede baixar a
        // fonte de emoji; o glifo viraria caixa vazia. As marcas são ícones do
        // Material, e `texto` guarda a forma legível, que é a que o cartão do
        // celular e o leitor de tela usam.
        ColunaIm360(
          titulo: 'Checklist',
          texto: resumoChecklist,
          celula: (l) => _MarcasChecklist(linha: l),
          flex: 3,
          larguraMin: 190,
        ),
        ColunaIm360(
          titulo: 'Certificado',
          texto: rotuloStatusDaLinha,
          prioridade: 2,
          flex: 2,
          larguraMin: 120,
        ),
      ],
      linhas: fila.whenData((_) => linhas),
      aoTocarLinha: _abrir,
      cartao: (l) => CartaoIm360(
        titulo: l.rotuloAluno,
        subtitulo: '${rotuloSituacao(l.situacao)} · ${l.metodoNome}',
        apoio: resumoChecklist(l),
        badge: BadgeStatus(l.alunoStatus),
        destaque: l.certificadoStatus == null
            ? null
            : rotuloStatusCertificado(l.certificadoStatus!),
        // A caixa Financeiro na lista, no celular — sem precisar abrir o
        // checklist completo (wireframe §12.2). Só aparece com a permissão e
        // com checklist aberto: marcar o que não existe é o que o banco recusa
        // com `CERTIFICADO_INEXISTENTE`, e oferecê-lo ensinaria a não confiar.
        acao: podeMarcarFinanceiro && l.temChecklist
            ? _CaixaFinanceiro(
                linha: l,
                aoMarcar: (valor) => _marcarFinanceiro(l, valor),
              )
            : null,
      ),
      estadoVazio: todas.isNotEmpty && filtro.ativos > 0
          ? EstadoVazio(
              mensagem: vazioCertificadosFiltro,
              icone: Icons.filter_alt_off_outlined,
              rotuloAcao: 'Limpar filtros',
              aoAgir: ref.read(filtroCertificadosProvider.notifier).limpar,
            )
          : const EstadoVazio(
              mensagem: vazioCertificados,
              icone: Icons.workspace_premium_outlined,
            ),
      aoRepetir: ref.read(versaoCertificadosProvider.notifier).incrementar,
    );
  }
}

/// A situação, com ícone: fim do curso (bandeira) e último livro (relógio). Cor
/// não é portadora única, e aqui nem cor há — a palavra vem junto.
class _Situacao extends StatelessWidget {
  const _Situacao({required this.situacao});

  final String situacao;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          situacao == situacaoFim
              ? Icons.flag_outlined
              : Icons.hourglass_bottom_outlined,
          size: 16,
          color: cores.onSurfaceVariant,
        ),
        const SizedBox(width: Dim.e4),
        Flexible(
          child: Text(
            rotuloSituacao(situacao),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Tipografia.corpoTabela,
          ),
        ),
      ],
    );
  }
}

/// As três marcas do checklist na linha da fila. Sem checklist é uma frase, e
/// não três caixas vazias: "ninguém abriu isto" e "o pedagógico ainda não
/// assinou" são coisas diferentes.
///
/// ⚠️ **De leitura, e só.** A caixa acionável na lista é do CELULAR (wireframe
/// §12.2, jornada nº 2 do monitor), e não do desktop: aqui a linha inteira abre
/// o painel, e um controle clicável dentro dela transformaria o clique de "ver
/// o checklist" num toggle por engano. Quem marca no desktop marca no painel,
/// onde o "quem/quando" está à vista.
class _MarcasChecklist extends StatelessWidget {
  const _MarcasChecklist({required this.linha});

  final LinhaFilaCertificado linha;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    if (!linha.temChecklist) {
      return Text(
        semChecklist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Tipografia.corpoTabela.copyWith(color: cores.onSurfaceVariant),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in ItemChecklist.values) ...[
          _Marca(item: item, marcado: linha.marca(item) == true),
          const SizedBox(width: Dim.e4),
        ],
      ],
    );
  }
}

/// Uma marca de leitura: ícone com forma própria + a sigla da coluna. A leitura
/// completa ("Pedagógico OK: marcado") fica na semântica e no tooltip.
class _Marca extends StatelessWidget {
  const _Marca({required this.item, required this.marcado});

  final ItemChecklist item;
  final bool marcado;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final descricao = '${item.rotulo}: ${marcado ? 'marcado' : 'pendente'}';
    return Tooltip(
      message: descricao,
      child: Semantics(
        label: descricao,
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              marcado
                  ? Icons.check_box_outlined
                  : Icons.check_box_outline_blank,
              size: 16,
              color: marcado ? cores.primary : cores.onSurfaceVariant,
            ),
            Text(
              item.sigla,
              style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// A caixa Financeiro acionável na lista (wireframe §12.2, jornada nº 2 do
/// monitor). Alvo de 44 px, e o tooltip diz o que ela faz — no celular a linha
/// inteira abre o painel, e sem o alvo próprio o toque cairia lá.
class _CaixaFinanceiro extends StatelessWidget {
  const _CaixaFinanceiro({required this.linha, required this.aoMarcar});

  final LinhaFilaCertificado linha;
  final ValueChanged<bool> aoMarcar;

  @override
  Widget build(BuildContext context) {
    final marcado = linha.financeiroOk == true;
    return Tooltip(
      message: marcado ? 'Desmarcar Financeiro OK' : 'Marcar Financeiro OK',
      child: SizedBox(
        width: Dim.alvoMobile,
        height: Dim.alvoMobile,
        child: Checkbox(
          value: marcado,
          onChanged: (valor) => aoMarcar(valor ?? false),
          semanticLabel: ItemChecklist.financeiro.rotulo,
        ),
      ),
    );
  }
}

/// O painel do checklist, aberto pela linha da fila (wireframe §12.2).
class _PainelChecklist extends StatelessWidget {
  const _PainelChecklist({required this.linha});

  final LinhaFilaCertificado linha;

  @override
  Widget build(BuildContext context) => PainelDetalhe(
    titulo: linha.rotuloAluno,
    subtitulo: [
      rotuloSituacao(linha.situacao),
      linha.metodoNome,
      if (linha.dataFimCurso != null)
        'fim do curso ${formatarData(linha.dataFimCurso!)}',
    ].join(' · '),
    acoes: const [],
    filho: BlocoChecklist(alunoId: linha.alunoId),
  );
}

/// Busca, método, situação e "só financeiro pendente" (design-system §5.3 e
/// wireframe §12.1/§12.2).
class _FiltrosCertificados extends ConsumerStatefulWidget {
  const _FiltrosCertificados({
    required this.filtro,
    required this.metodos,
    required this.situacoes,
  });

  final FiltroCertificados filtro;
  final List<Metodo> metodos;
  final List<String> situacoes;

  @override
  ConsumerState<_FiltrosCertificados> createState() =>
      _FiltrosCertificadosState();
}

class _FiltrosCertificadosState extends ConsumerState<_FiltrosCertificados> {
  late final _busca = TextEditingController(text: widget.filtro.busca);

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // "Limpar filtros" vem de fora (estado vazio): o campo acompanha.
    ref.listen(filtroCertificadosProvider, (_, novo) {
      if (_busca.text != novo.busca) _busca.text = novo.busca;
    });
    final filtro = widget.filtro;
    final controlador = ref.read(filtroCertificadosProvider.notifier);

    return Wrap(
      spacing: Dim.e8,
      runSpacing: Dim.e8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        CampoBusca(
          controlador: _busca,
          rotulo: 'Aluno ou código',
          aoMudar: (valor) => controlador.definir(filtro.copiar(busca: valor)),
          aoLimpar: () => controlador.definir(filtro.copiar(busca: '')),
        ),
        FiltroSuspenso<String>(
          key: ValueKey('metodo-${filtro.metodoId}'),
          rotulo: 'Método',
          selecao: filtro.metodoId ?? '',
          entradas: [
            const DropdownMenuEntry(value: '', label: 'Todos'),
            for (final metodo in widget.metodos)
              DropdownMenuEntry(value: metodo.id, label: metodo.nome),
          ],
          aoSelecionar: (valor) => controlador.definir(
            filtro.copiar(
              metodoId: () => (valor == null || valor.isEmpty) ? null : valor,
            ),
          ),
        ),
        FiltroSuspenso<String>(
          key: ValueKey('situacao-${filtro.situacao}'),
          rotulo: 'Situação',
          largura: 200,
          selecao: filtro.situacao ?? '',
          entradas: [
            const DropdownMenuEntry(value: '', label: 'Todas'),
            for (final situacao in widget.situacoes)
              DropdownMenuEntry(
                value: situacao,
                label: rotuloSituacao(situacao),
              ),
          ],
          aoSelecionar: (valor) => controlador.definir(
            filtro.copiar(
              situacao: () => (valor == null || valor.isEmpty) ? null : valor,
            ),
          ),
        ),
        // A jornada nº 2 do monitor começa aqui: a fila filtrada por
        // "financeiro pendente" (wireframe §12.2).
        FilterChip(
          label: const Text('Financeiro pendente'),
          selected: filtro.soFinanceiroPendente,
          onSelected: (valor) =>
              controlador.definir(filtro.copiar(soFinanceiroPendente: valor)),
        ),
      ],
    );
  }
}
