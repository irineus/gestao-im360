/// O estoque como o app o vê (card 6.7): o modelo de `v_estoque_atual`
/// (card 6.4), o de `v_material_movimento` (card 6.7) e a lógica **pura** da
/// tela 6 — situação de cada material, filtro do painel e os rótulos de origem
/// de um movimento.
///
/// Pura de propósito: é o que se testa sem rede e sem cliente Supabase
/// (card 2.8 §9.3).
///
/// ⚠️ **Nada neste arquivo soma movimento para chegar a saldo.** O saldo vem da
/// view, que chama a mesma conta do banco (`sum(quantidade)` de
/// `movimento_estoque`, card 6.4). Uma soma em Dart seria a **terceira**
/// implementação que o card 2.3 §4.1 proíbe — e ela erraria exatamente para
/// quem lê o painel com filtro de período ligado, somando um pedaço da história
/// e chamando o resultado de saldo.
library;

import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// Modelos
// ---------------------------------------------------------------------------

/// Uma linha de `v_estoque_atual` (card 6.4): o material do catálogo com o
/// saldo, o mínimo e a data do último movimento.
///
/// É a fonte da aba Materiais desde o card 6.7 — antes ela lia a tabela
/// `material`. A view **inclui material sem movimento** (saldo 0) e **material
/// inativo**, que é o que o wireframe §9 pede: o filtro "Só ativos" é da tela e
/// é desligável.
@immutable
class MaterialEstoque {
  const MaterialEstoque({
    required this.materialId,
    required this.metodoId,
    required this.codigo,
    required this.nome,
    required this.categoria,
    required this.estoqueMinimo,
    required this.saldo,
    this.ativo = true,
    this.abaixoMinimo = false,
    this.qtdMovimentos = 0,
    this.ultimoMovimentoEm,
  });

  factory MaterialEstoque.deLinha(Map<String, dynamic> linha) =>
      MaterialEstoque(
        materialId: '${linha['material_id']}',
        metodoId: '${linha['metodo_id']}',
        codigo: '${linha['codigo']}',
        nome: '${linha['nome']}',
        categoria: '${linha['categoria']}',
        estoqueMinimo: (linha['estoque_minimo'] as num?)?.toInt() ?? 0,
        saldo: (linha['saldo'] as num?)?.toInt() ?? 0,
        ativo: linha['ativo'] as bool? ?? true,
        abaixoMinimo: linha['abaixo_minimo'] as bool? ?? false,
        qtdMovimentos: (linha['qtd_movimentos'] as num?)?.toInt() ?? 0,
        ultimoMovimentoEm: linha['ultimo_movimento_em'] == null
            ? null
            : DateTime.parse('${linha['ultimo_movimento_em']}').toLocal(),
      );

  final String materialId;
  final String metodoId;
  final String codigo;
  final String nome;
  final String categoria;
  final int estoqueMinimo;

  /// `sum(quantidade)` do banco. **Nunca recalculado aqui.**
  final int saldo;

  final bool ativo;

  /// Vem da view, e não de `saldo < estoqueMinimo` em Dart: são a mesma conta,
  /// e duas cópias dela divergiriam no dia em que o critério mudasse.
  final bool abaixoMinimo;

  final int qtdMovimentos;
  final DateTime? ultimoMovimentoEm;

  String get rotulo => '$codigo $nome';
}

/// Uma linha de `v_material_movimento` (card 6.7).
///
/// ⚠️ Os três pares `id` + `nome` existem porque a view resolve os rótulos com
/// `left join` em tabelas que a rota da tela **não** exige poder ler: sem
/// `alunos.ler` o nome vem nulo e o id não. É essa diferença que separa
/// "movimento sem aluno" de "tem aluno e você não pode vê-lo" — ver
/// [origemDoMovimento].
@immutable
class MovimentoMaterial {
  const MovimentoMaterial({
    required this.movimentoId,
    required this.materialId,
    required this.tipo,
    required this.quantidade,
    required this.ocorridoEm,
    this.observacao,
    this.alunoId,
    this.alunoNome,
    this.alunoCodigoSgf,
    this.pedidoItemId,
    this.pedidoNumero,
    this.estornoDeId,
    this.estornoDeTipo,
    this.estornoDeOcorridoEm,
    this.criadoPor,
    this.criadoPorNome,
  });

  factory MovimentoMaterial.deLinha(Map<String, dynamic> linha) =>
      MovimentoMaterial(
        movimentoId: '${linha['movimento_id']}',
        materialId: '${linha['material_id']}',
        tipo: '${linha['tipo']}',
        quantidade: (linha['quantidade'] as num).toInt(),
        ocorridoEm: DateTime.parse('${linha['ocorrido_em']}').toLocal(),
        observacao: linha['observacao'] as String?,
        alunoId: linha['aluno_id'] == null ? null : '${linha['aluno_id']}',
        alunoNome: linha['aluno_nome'] as String?,
        alunoCodigoSgf: linha['aluno_codigo_sgf'] as String?,
        pedidoItemId: linha['pedido_item_id'] == null
            ? null
            : '${linha['pedido_item_id']}',
        pedidoNumero: linha['pedido_numero'] as String?,
        estornoDeId: linha['estorno_de_id'] == null
            ? null
            : '${linha['estorno_de_id']}',
        estornoDeTipo: linha['estorno_de_tipo'] as String?,
        estornoDeOcorridoEm: linha['estorno_de_ocorrido_em'] == null
            ? null
            : DateTime.parse('${linha['estorno_de_ocorrido_em']}').toLocal(),
        criadoPor: linha['criado_por'] == null
            ? null
            : '${linha['criado_por']}',
        criadoPorNome: linha['criado_por_nome'] as String?,
      );

  final String movimentoId;
  final String materialId;

  /// `ENTRADA`, `SAIDA`, `AJUSTE` ou `ESTORNO` (card 6.1).
  final String tipo;

  /// **Com sinal**, como a coluna. A tela não deriva o sinal do tipo — seria
  /// recriar em Dart o `case` por tipo que o card 2.1 tirou do banco.
  final int quantidade;

  final DateTime ocorridoEm;
  final String? observacao;

  final String? alunoId;
  final String? alunoNome;
  final String? alunoCodigoSgf;

  final String? pedidoItemId;
  final String? pedidoNumero;

  final String? estornoDeId;
  final String? estornoDeTipo;
  final DateTime? estornoDeOcorridoEm;

  final String? criadoPor;
  final String? criadoPorNome;

  /// `+10` / `−1`, com o sinal explícito e o menos tipográfico (o hífen ASCII
  /// some ao lado de um numeral tabular).
  String get quantidadeFormatada =>
      quantidade > 0 ? '+$quantidade' : '−${quantidade.abs()}';
}

// ---------------------------------------------------------------------------
// Situação de um material — o `0 ⚠` e o `-2 ✖` do wireframe §9
// ---------------------------------------------------------------------------

/// Três estados, e o pior deles **nunca é escondido** (card 2.3 §4.1): saldo
/// negativo é sintoma de AJUSTE errado ou de divergência da migração, e some da
/// tela é como um erro de contagem vira um erro de compra.
enum SituacaoEstoque { normal, abaixoMinimo, negativo }

SituacaoEstoque situacaoEstoqueDe(MaterialEstoque material) =>
    material.saldo < 0
    ? SituacaoEstoque.negativo
    : material.abaixoMinimo
    ? SituacaoEstoque.abaixoMinimo
    : SituacaoEstoque.normal;

/// O texto que acompanha o ícone — cor nunca é o único portador
/// (design-system §8.2), e um leitor de tela não enxerga fundo tonal nenhum.
String? rotuloSituacaoEstoque(MaterialEstoque material) =>
    switch (situacaoEstoqueDe(material)) {
      SituacaoEstoque.negativo => 'saldo negativo',
      SituacaoEstoque.abaixoMinimo => 'abaixo do mínimo',
      SituacaoEstoque.normal => null,
    };

// ---------------------------------------------------------------------------
// Filtro da lista — o mesmo `FiltroCatalogo`, com "só abaixo do mínimo"
// ---------------------------------------------------------------------------

bool _casaBusca(String busca, Iterable<String> campos) {
  final termo = busca.trim().toLowerCase();
  if (termo.isEmpty) return true;
  return campos.any((c) => c.toLowerCase().contains(termo));
}

/// Filtra a lista de `v_estoque_atual` com os quatro filtros do wireframe §9.
///
/// [soAbaixoMinimo] é o checkbox do desenho. Ele **não** vira `where` na view:
/// a view devolve tudo e quem esconde é a tela (card 2.3 §2.3(h)) — uma view
/// que já entregasse filtrado esconderia o material que acabou de zerar.
List<MaterialEstoque> filtrarEstoque(
  List<MaterialEstoque> todos, {
  String busca = '',
  String? metodoId,
  String? categoria,
  bool soAtivos = true,
  bool soAbaixoMinimo = false,
}) => [
  for (final m in todos)
    if ((!soAtivos || m.ativo) &&
        (metodoId == null || m.metodoId == metodoId) &&
        (categoria == null || m.categoria == categoria) &&
        (!soAbaixoMinimo || m.abaixoMinimo || m.saldo < 0) &&
        _casaBusca(busca, [m.codigo, m.nome]))
      m,
];

/// As categorias em uso — a mesma ideia de `categoriasDe` do catálogo, aqui
/// sobre as linhas da view.
List<String> categoriasDoEstoque(Iterable<MaterialEstoque> materiais) =>
    ({for (final m in materiais) m.categoria}.toList()..sort());

// ---------------------------------------------------------------------------
// Filtro do painel de movimentações — período e tipo (wireframe §9)
// ---------------------------------------------------------------------------

/// Janelas do filtro de período. `todos` existe porque o painel é
/// **conferência**: esconder o começo da história é esconder de onde veio o
/// saldo.
enum PeriodoMovimento { trintaDias, noventaDias, umAno, todos }

String rotuloPeriodo(PeriodoMovimento periodo) => switch (periodo) {
  PeriodoMovimento.trintaDias => 'Últimos 30 dias',
  PeriodoMovimento.noventaDias => 'Últimos 90 dias',
  PeriodoMovimento.umAno => 'Último ano',
  PeriodoMovimento.todos => 'Tudo',
};

int? _diasDe(PeriodoMovimento periodo) => switch (periodo) {
  PeriodoMovimento.trintaDias => 30,
  PeriodoMovimento.noventaDias => 90,
  PeriodoMovimento.umAno => 365,
  PeriodoMovimento.todos => null,
};

@immutable
class FiltroMovimento {
  const FiltroMovimento({this.periodo = PeriodoMovimento.todos, this.tipo});

  /// O padrão é **tudo**: o painel abre mostrando a história inteira, porque a
  /// pergunta que ele responde é "por que o saldo é este?".
  final PeriodoMovimento periodo;

  /// `ENTRADA` / `SAIDA` / `AJUSTE` / `ESTORNO`, ou nulo para todos.
  final String? tipo;

  int get ativos =>
      (periodo == PeriodoMovimento.todos ? 0 : 1) + (tipo == null ? 0 : 1);

  FiltroMovimento copiar({
    PeriodoMovimento? periodo,
    String? Function()? tipo,
  }) => FiltroMovimento(
    periodo: periodo ?? this.periodo,
    tipo: tipo == null ? this.tipo : tipo(),
  );
}

/// [hoje] entra por parâmetro porque o corte de período é uma data, e data neste
/// app não vem do relógio do aparelho (`hojeSaoPaulo`, card 5.9).
List<MovimentoMaterial> filtrarMovimentos(
  List<MovimentoMaterial> todos,
  FiltroMovimento filtro, {
  required DateTime hoje,
}) {
  final dias = _diasDe(filtro.periodo);
  final corte = dias == null ? null : hoje.subtract(Duration(days: dias));
  return [
    for (final m in todos)
      if ((corte == null || !m.ocorridoEm.isBefore(corte)) &&
          (filtro.tipo == null || m.tipo == filtro.tipo))
        m,
  ];
}

// ---------------------------------------------------------------------------
// Origem de um movimento — e os três casos de "existe e você não pode ver"
// ---------------------------------------------------------------------------

/// A coluna do meio do painel: "Afonso (4433)", "pedido 2026-001", "estorno de
/// saída de 12/08/2026".
///
/// ⚠️ **Os três rótulos podem vir nulos sem que a linha suma** — é a decisão da
/// migração deste card: `left join` em `aluno`, `pedido_compra` e `usuario`,
/// porque a rota da tela 6 exige só `materiais.ler` + `estoque.ler`. Quando o
/// id existe e o nome não, o texto diz **que existe e não está visível**, e não
/// um traço: um traço faria uma SAIDA de entrega parecer um ajuste sem dono, que
/// é a mesma mentira que o card 4.6 recusou na ficha (pendência 9.13).
String origemDoMovimento(MovimentoMaterial mov) {
  if (mov.alunoId != null) {
    final nome = mov.alunoNome;
    if (nome == null) return 'Aluno não visível para o seu perfil';
    final codigo = mov.alunoCodigoSgf;
    return codigo == null || codigo.isEmpty ? nome : '$nome ($codigo)';
  }
  if (mov.pedidoItemId != null) {
    final numero = mov.pedidoNumero;
    return numero == null
        ? 'Recebimento de pedido (número não visível para o seu perfil)'
        : 'Pedido $numero';
  }
  if (mov.estornoDeId != null) {
    final quando = mov.estornoDeOcorridoEm;
    final tipo = (mov.estornoDeTipo ?? 'movimento').toLowerCase();
    return quando == null
        ? 'Estorno de $tipo anterior'
        : 'Estorno de $tipo de ${_data(quando)}';
  }
  return mov.tipo == 'ENTRADA' ? 'Entrada sem pedido' : 'Lançamento manual';
}

/// "por Débora", ou **nada**. Nulo quando o autor não é legível (sem `admin.ler`
/// e não sendo a própria pessoa, card 3.4) e quando a linha não tem autor — a
/// fixture e o importador do card 9.1 gravam movimento sem `criado_por`. Nos
/// dois casos a tela **omite o trecho**, em vez de escrever "por —".
String? autorDoMovimento(MovimentoMaterial mov) {
  final nome = mov.criadoPorNome;
  return nome == null || nome.isEmpty ? null : 'por $nome';
}

String _dois(int n) => n.toString().padLeft(2, '0');
String _data(DateTime d) => '${_dois(d.day)}/${_dois(d.month)}/${d.year}';

// ---------------------------------------------------------------------------
// Textos de tela — docs/design-system.md §7.2, palavra por palavra
// ---------------------------------------------------------------------------

/// §7.2, linha "Movimentações de material". A frase diz **onde** se lança
/// entrada, porque a pergunta que um painel vazio produz é justamente essa.
const vazioMovimentos =
    'Nenhuma movimentação. Entrada de estoque acontece pelo recebimento de '
    'pedido, na tela Compras.';

const vazioMovimentosFiltro = 'Nenhuma movimentação com esses filtros.';

/// Aviso de consequência do formulário de ajuste (design-system §5.4).
const avisoAjuste =
    'O ajuste entra como um movimento de estoque e não pode ser apagado — '
    'correção de ajuste é outro ajuste. Use quantidade positiva para acrescentar '
    'ao saldo e negativa para tirar.';

/// O que o `[Ajustar]` faz e o que ele **não** faz. Fica no formulário porque é
/// onde a pessoa pergunta "e a entrada que eu recebi?".
const avisoAjusteNaoEEntrada =
    'Recebimento de pedido não se lança aqui: ele entra na tela Compras, e é lá '
    'que a chegada fica ligada ao pedido.';

/// Sem material selecionado o painel não tem assunto.
const semMaterialSelecionado =
    'Escolha um material na lista para ver as movimentações dele.';
