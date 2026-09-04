/// A trilha do aluno como o app a vê (card 6.6): o modelo de `v_aluno_trilha`,
/// o retorno de `fn_registrar_entrega` e a lógica **pura** da aba Trilha —
/// situação de cada item, resumo do cabeçalho e os textos dos três resultados
/// da entrega.
///
/// Pura de propósito: é o que se testa sem rede e sem cliente Supabase
/// (card 2.8 §9.3). Regra de negócio continua no banco — quem decide se a
/// entrega sai, reordena ou bloqueia é `fn_registrar_entrega`, dentro da
/// transação. Aqui só se **lê o resultado** e se escolhe a frase.
///
/// ⚠️ Nada neste arquivo compara saldo com zero para decidir se a entrega pode
/// acontecer. É a decisão 2 do card 2.6 (wireframe §17): a tela não pré-verifica
/// regra em Dart. O `saldo` que chega da view é informativo — seria a terceira
/// implementação da soma que o card 2.3 §4.1 proíbe, e ela erraria justamente
/// na corrida do último exemplar, que é onde o banco acerta com advisory lock.
library;

import 'package:flutter/foundation.dart';

import '../util/datas.dart';

// ---------------------------------------------------------------------------
// Modelos
// ---------------------------------------------------------------------------

/// Uma linha de `v_aluno_trilha` (card 6.6).
@immutable
class ItemTrilha {
  const ItemTrilha({
    required this.itemId,
    required this.alunoId,
    required this.materialId,
    required this.ordem,
    required this.posicao,
    required this.materialCodigo,
    required this.materialNome,
    this.materialCategoria,
    this.origem = 'COMBO',
    this.entregue = false,
    this.dataEntrega,
    this.movimentoEstoqueId,
    this.proximo = false,
    this.saldo = 0,
  });

  factory ItemTrilha.deLinha(Map<String, dynamic> linha) => ItemTrilha(
    itemId: '${linha['item_id']}',
    alunoId: '${linha['aluno_id']}',
    materialId: '${linha['material_id']}',
    ordem: (linha['ordem'] as num).toInt(),
    posicao: (linha['posicao'] as num).toInt(),
    materialCodigo: '${linha['material_codigo']}',
    materialNome: '${linha['material_nome']}',
    materialCategoria: linha['material_categoria'] as String?,
    origem: '${linha['origem']}',
    entregue: linha['entregue'] as bool? ?? false,
    dataEntrega: linha['data_entrega'] == null
        ? null
        : DateTime.parse('${linha['data_entrega']}'),
    movimentoEstoqueId: linha['movimento_estoque_id'] == null
        ? null
        : '${linha['movimento_estoque_id']}',
    proximo: linha['proximo'] as bool? ?? false,
    saldo: (linha['saldo'] as num?)?.toInt() ?? 0,
  );

  final String itemId;
  final String alunoId;
  final String materialId;

  /// A coluna do banco, de 10 em 10 (card 6.2 §5.1). Vai para
  /// `fn_trilha_reordenar` como POSIÇÃO de destino, nunca para a tela.
  final int ordem;

  /// O número da coluna `#` da aba: 1..n, contínuo (view do card 6.6).
  final int posicao;

  final String materialCodigo;
  final String materialNome;
  final String? materialCategoria;

  /// `COMBO` (veio da expansão do combo) ou `MANUAL` (alguém incluiu à mão).
  final String origem;

  final bool entregue;
  final DateTime? dataEntrega;

  /// A SAIDA que pagou a entrega. É o que `fn_estornar_entrega` recebe — sem
  /// ele não há o que estornar, e o botão não aparece.
  final String? movimentoEstoqueId;

  /// O item pendente de menor `ordem` — o "► próxima" do wireframe §6.3.
  final bool proximo;

  /// Saldo do material, **informativo** (ver o aviso no topo do arquivo).
  final int saldo;

  bool get manual => origem == 'MANUAL';

  /// Só entrega com movimento se estorna: a fixture do card 6.1 tem itens
  /// marcados como entregues sem vínculo (a migração do card 9.1 também terá),
  /// e para eles o botão fica visível e desabilitado com o motivo.
  bool get estornavel => entregue && movimentoEstoqueId != null;

  String get rotulo => '$materialCodigo $materialNome';
}

/// Os três resultados de `fn_registrar_entrega` (card 2.2 §6.1, tipo
/// `tp_entrega_resultado`). São **retorno**, nunca exceção: os dois últimos
/// precisam deixar pendência gravada, e um `raise` a levaria no rollback.
enum StatusEntrega { entregue, reordenada, bloqueadaSemEstoque }

@immutable
class ResultadoEntrega {
  const ResultadoEntrega({
    required this.status,
    this.materialId,
    this.materialSolicitado,
    this.movimentoId,
    this.proximoMaterialId,
    this.emFim = false,
  });

  factory ResultadoEntrega.deLinha(Map<String, dynamic> linha) =>
      ResultadoEntrega(
        status: statusEntregaDe('${linha['status']}'),
        materialId: linha['material_id'] == null
            ? null
            : '${linha['material_id']}',
        materialSolicitado: linha['material_solicitado'] == null
            ? null
            : '${linha['material_solicitado']}',
        movimentoId: linha['movimento_id'] == null
            ? null
            : '${linha['movimento_id']}',
        proximoMaterialId: linha['proximo_material_id'] == null
            ? null
            : '${linha['proximo_material_id']}',
        emFim: linha['em_fim'] as bool? ?? false,
      );

  final StatusEntrega status;

  /// O material que de fato saiu do estoque. Nulo em `BLOQUEADA_SEM_ESTOQUE`,
  /// e é a diferença dele para `materialSolicitado` que denuncia o
  /// reordenamento a quem lê o retorno sem olhar o `status`.
  final String? materialId;
  final String? materialSolicitado;
  final String? movimentoId;
  final String? proximoMaterialId;

  /// A trilha fechou nesta entrega — o checklist de certificado foi aberto.
  final bool emFim;
}

/// O código do banco → o enum. Código desconhecido é tratado como bloqueio, e
/// não como sucesso: o dia em que o banco ganhar um quarto status, a tela para
/// e mostra o texto de alerta em vez de dizer "entregue" sobre o que não foi.
StatusEntrega statusEntregaDe(String codigo) => switch (codigo) {
  'ENTREGUE' => StatusEntrega.entregue,
  'REORDENADA' => StatusEntrega.reordenada,
  _ => StatusEntrega.bloqueadaSemEstoque,
};

// ---------------------------------------------------------------------------
// Lógica de tela — situação, resumo e textos
// ---------------------------------------------------------------------------

enum SituacaoItem { entregue, proxima, pendente }

SituacaoItem situacaoDe(ItemTrilha item) => item.entregue
    ? SituacaoItem.entregue
    : item.proximo
    ? SituacaoItem.proxima
    : SituacaoItem.pendente;

/// A coluna "Situação" do wireframe §6.3. O saldo entra só na próxima, e é o
/// "(est. 7)" do desenho — informativo, do lado do item que a pessoa vai
/// entregar agora.
String rotuloSituacao(ItemTrilha item) => switch (situacaoDe(item)) {
  SituacaoItem.entregue =>
    item.dataEntrega == null
        ? 'entregue'
        : 'entregue ${formatarData(item.dataEntrega!)}',
  SituacaoItem.proxima => 'próxima · est. ${item.saldo}',
  SituacaoItem.pendente => 'pendente',
};

/// O cabeçalho da aba: "3 entregues, 11 pendentes" (wireframe §6.3).
@immutable
class ResumoTrilha {
  const ResumoTrilha({required this.entregues, required this.pendentes});

  final int entregues;
  final int pendentes;

  int get total => entregues + pendentes;

  /// Trilha existe e nada está pendente. É diferente de trilha VAZIA — e é a
  /// distinção que `fn_trilha_em_fim` não faz (card 6.2), por isso a tela
  /// pergunta à view.
  bool get emFim => total > 0 && pendentes == 0;

  String get texto =>
      '$entregues ${_plural(entregues, 'entregue', 'entregues')}'
      ', $pendentes ${_plural(pendentes, 'pendente', 'pendentes')}';

  static String _plural(int n, String um, String varios) =>
      n == 1 ? um : varios;
}

ResumoTrilha resumirTrilha(List<ItemTrilha> itens) {
  var entregues = 0;
  for (final i in itens) {
    if (i.entregue) entregues++;
  }
  return ResumoTrilha(
    entregues: entregues,
    pendentes: itens.length - entregues,
  );
}

/// O item marcado como próximo, ou nulo (trilha vazia ou em fim).
ItemTrilha? proximoDaTrilha(List<ItemTrilha> itens) {
  for (final i in itens) {
    if (i.proximo) return i;
  }
  return null;
}

/// Os candidatos a inclusão na trilha: material do método do aluno, ativo, que
/// ainda não está lá. Filtrar aqui não é pré-verificar regra — é não oferecer o
/// que o banco vai recusar com `MATERIAL_JA_NA_TRILHA` (wireframe §2.2).
List<T> candidatosParaTrilha<T>(
  List<T> materiais, {
  required String Function(T) idDe,
  required String Function(T) metodoDe,
  required bool Function(T) ativoDe,
  required String metodoDoAluno,
  required Set<String> jaNaTrilha,
}) => [
  for (final m in materiais)
    if (metodoDe(m) == metodoDoAluno &&
        ativoDe(m) &&
        !jaNaTrilha.contains(idDe(m)))
      m,
];

// ---------------------------------------------------------------------------
// Textos dos resultados — docs/design-system.md §7.3, palavra por palavra
// ---------------------------------------------------------------------------

/// Título e mensagem do diálogo de resultado da entrega.
///
/// ⚠️ **Diálogo, e não snackbar** (design-system §5.8): os três resultados mudam
/// o que a pessoa fará em seguida — entregar a próxima, procurar a apostila
/// pulada, abrir a pendência de compra —, e um snackbar some antes de ser lido.
///
/// [nomeDoMaterial] resolve o id para "INT-04 Intermediário 1"; devolve um
/// traço quando o material não está no catálogo carregado, que é melhor do que
/// mostrar um UUID.
({String titulo, String mensagem}) textoResultadoEntrega(
  ResultadoEntrega resultado, {
  required String Function(String? id) nomeDoMaterial,
}) {
  switch (resultado.status) {
    case StatusEntrega.entregue:
      final entregue = nomeDoMaterial(resultado.materialId);
      if (resultado.emFim) {
        // ⚠️ **Divergência do design-system §7.3, registrada no §11:** o texto
        // fechado lá traz um emoji de formatura ("Trilha concluída 🎓 — …") e
        // ele **não pode ir para a tela**. O app carrega Inter/Roboto, que não
        // têm o glifo, e a CSP do card 3.8 impede o download de uma fonte de
        // emoji: o que apareceria é uma caixa vazia no meio da única frase
        // comemorativa do sistema. Quem mede isso é o `texto_de_tela_test`
        // (card 5.11), e foi ele que reprovou esta linha.
        return (
          titulo: 'Entrega registrada',
          mensagem:
              '$entregue foi entregue. Trilha concluída — o checklist de '
              'certificado foi aberto.',
        );
      }
      return (
        titulo: 'Entrega registrada',
        mensagem:
            '$entregue foi entregue. A próxima apostila é '
            '${nomeDoMaterial(resultado.proximoMaterialId)}.',
      );
    case StatusEntrega.reordenada:
      final pulada = nomeDoMaterial(resultado.materialSolicitado);
      final entregue = nomeDoMaterial(resultado.materialId);
      return (
        titulo: 'Trilha reordenada',
        mensagem:
            'Sem estoque de $pulada; foi entregue $entregue. $pulada continua '
            'pendente e volta a ser a próxima quando houver estoque.',
      );
    case StatusEntrega.bloqueadaSemEstoque:
      return (
        titulo: 'Entrega bloqueada',
        mensagem:
            'Nenhuma apostila da trilha tem estoque. A entrega não foi '
            'registrada; foi aberta uma pendência de compra.',
      );
  }
}

/// Os dois últimos status abriram (ou tocaram) uma pendência, e o diálogo leva
/// para ela — é o "+ link" do §7.3.
bool resultadoTemPendencia(ResultadoEntrega resultado) =>
    resultado.status != StatusEntrega.entregue;

// --- textos de tela ---------------------------------------------------------

/// design-system §7.2, linha "Ficha → Trilha".
const vazioTrilha =
    'Este aluno não tem trilha. Gere a partir do combo em Editar trilha.';

/// A aba exige `estoque.ler`, que a rota da ficha não exige (rota 3b do
/// card 2.4 §6). Sem ela o saldo viria 0 em toda linha **sem erro nenhum**, e
/// toda entrega seria recusada por falta de um estoque que existe — por isso a
/// aba diz o que falta em vez de mostrar a lista mentindo.
const semAcessoTrilha =
    'A trilha deste aluno não aparece para o seu perfil. Peça a permissão de '
    'ver estoque a quem administra o acesso.';

/// O aluno não é ATIVO nem ACELERAR: `fn_registrar_entrega` recusaria com
/// `ALUNO_INATIVO`. Botão visível e desabilitado com o motivo — sem estado, não
/// sem permissão (design-system §5.7).
const motivoAlunoInativo =
    'Só aluno ATIVO ou ACELERAR recebe apostila. Altere o status para '
    'registrar entrega.';

const motivoTrilhaEmFim =
    'A trilha deste aluno está concluída — não há apostila pendente para '
    'entregar.';

const motivoTrilhaVazia =
    'Este aluno ainda não tem trilha. Gere a trilha a partir do combo.';

const motivoSemMovimento =
    'Esta entrega não tem movimento de estoque vinculado e não pode ser '
    'estornada.';
