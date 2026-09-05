/// Os certificados como o app os vê (card 8.6): o modelo de
/// `v_certificado_fila` (a fila da tela 9) e o de `certificado_checklist` (o
/// checklist, que é o mesmo componente na tela 9 e na aba Certificado da ficha),
/// mais a lógica **pura** — rótulos, filtros e textos de estado.
///
/// Pura de propósito: é o que se testa sem rede e sem cliente Supabase
/// (card 2.8 §9.3).
///
/// ⚠️ **Nada neste arquivo decide nada.** Quem diz se um aluno está chegando ao
/// fim é `v_certificado_fila`; quem marca item e muda status são
/// `fn_certificado_marcar` e `fn_certificado_status`; quem sugere FORMADO é
/// `tg_certificado_sugere_formado`. Aqui só se traduz o que o banco devolveu.
library;

import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// Situação na fila — as duas do card 2.3 §8.1
// ---------------------------------------------------------------------------

/// Um item pendente: o aluno está **recebendo** a última apostila e ainda tem
/// aula pela frente. É esta metade da fila que dá tempo de pedir o certificado.
const situacaoUltimoLivro = 'ULTIMO_LIVRO';

/// Nenhum item pendente: a trilha acabou, e é aqui que a entrega abriu o
/// checklist sozinha.
const situacaoFim = 'FIM';

/// As duas, na ordem em que a tela as lista — FIM primeiro, porque quem já
/// terminou não tem mais prazo nenhum pela frente.
const situacoesDaFila = <String>[situacaoFim, situacaoUltimoLivro];

/// Código desconhecido volta como veio: inventar rótulo para uma situação que o
/// banco passou a usar esconderia justamente a novidade.
String rotuloSituacao(String codigo) => switch (codigo) {
  situacaoFim => 'Fim do curso',
  situacaoUltimoLivro => 'Último livro',
  _ => codigo,
};

// ---------------------------------------------------------------------------
// Status do certificado
// ---------------------------------------------------------------------------

/// `NAO_PEDIDO` → `PEDIDO` → `ENTREGUE`, na ordem da sequência.
///
/// ⚠️ A ordem é de leitura, não de máquina de estados: a volta é permitida de
/// propósito (card 8.3), porque "pedido por engano" e "entregue e devolvido para
/// corrigir o nome" são casos reais da secretaria.
const statusDoCertificado = <String>['NAO_PEDIDO', 'PEDIDO', 'ENTREGUE'];

String rotuloStatusCertificado(String codigo) => switch (codigo) {
  'NAO_PEDIDO' => 'Não pedido',
  'PEDIDO' => 'Pedido',
  'ENTREGUE' => 'Entregue',
  _ => codigo,
};

// ---------------------------------------------------------------------------
// Os itens do checklist
// ---------------------------------------------------------------------------

/// Os três itens do checklist e a permissão de **cada um** (card 2.2 §8).
///
/// A separação não é decorativa: marcar "financeiro OK" é a única marca do
/// checklist que o monitor faz, e é a jornada nº 2 dele (wireframe §12.2).
/// Pedagógico e formatura andam juntos porque os dois são do pedagógico.
enum ItemChecklist {
  pedagogico(
    'PEDAGOGICO',
    'Pedagógico OK',
    'P',
    'certificados.marcar_pedagogico',
  ),
  financeiro(
    'FINANCEIRO',
    'Financeiro OK',
    'F',
    'certificados.marcar_financeiro',
  ),
  formatura('FORMATURA', 'Formatura', 'Fo', 'certificados.marcar_pedagogico');

  const ItemChecklist(this.codigo, this.rotulo, this.sigla, this.permissao);

  /// O que `fn_certificado_marcar` recebe em `p_item`.
  final String codigo;

  final String rotulo;

  /// A abreviação da coluna Checklist da fila (wireframe §12.1).
  final String sigla;

  final String permissao;
}

// ---------------------------------------------------------------------------
// Fila — uma linha de v_certificado_fila
// ---------------------------------------------------------------------------

/// Um aluno chegando ao fim do curso, com o resumo do checklist ao lado.
///
/// ⚠️ **As cinco colunas do checklist são nulas quando ele ainda não existe**, e
/// nulo não é `false`: "ninguém abriu o checklist deste aluno" e "o checklist
/// existe e o pedagógico ainda não assinou" são coisas diferentes. O checklist
/// nasce na entrega que fecha a trilha; quem está em [situacaoUltimoLivro] ainda
/// não tem um, e é a tela que oferece abri-lo.
@immutable
class LinhaFilaCertificado {
  const LinhaFilaCertificado({
    required this.alunoId,
    required this.alunoNome,
    required this.codigoSgf,
    required this.alunoStatus,
    required this.metodoId,
    required this.metodoNome,
    required this.situacao,
    required this.itensPendentes,
    this.checklistId,
    this.dataFimCurso,
    this.pedagogicoOk,
    this.financeiroOk,
    this.formatura,
    this.certificadoStatus,
  });

  factory LinhaFilaCertificado.deLinha(Map<String, dynamic> linha) =>
      LinhaFilaCertificado(
        alunoId: '${linha['aluno_id']}',
        alunoNome: '${linha['aluno_nome']}',
        codigoSgf: linha['codigo_sgf'] as String?,
        alunoStatus: '${linha['aluno_status']}',
        metodoId: '${linha['metodo_id']}',
        metodoNome: '${linha['metodo_nome']}',
        situacao: '${linha['situacao']}',
        itensPendentes: (linha['itens_pendentes'] as num?)?.toInt() ?? 0,
        checklistId: linha['checklist_id'] as String?,
        dataFimCurso: linha['data_fim_curso'] == null
            ? null
            : DateTime.parse('${linha['data_fim_curso']}'),
        pedagogicoOk: linha['pedagogico_ok'] as bool?,
        financeiroOk: linha['financeiro_ok'] as bool?,
        formatura: linha['formatura'] as bool?,
        certificadoStatus: linha['certificado_status'] as String?,
      );

  final String alunoId;
  final String alunoNome;
  final String? codigoSgf;
  final String alunoStatus;
  final String metodoId;
  final String metodoNome;

  /// [situacaoFim] ou [situacaoUltimoLivro].
  final String situacao;
  final int itensPendentes;

  final String? checklistId;
  final DateTime? dataFimCurso;
  final bool? pedagogicoOk;
  final bool? financeiroOk;
  final bool? formatura;
  final String? certificadoStatus;

  bool get temChecklist => checklistId != null;

  /// O valor de um item, ou nulo quando não há checklist.
  bool? marca(ItemChecklist item) => switch (item) {
    ItemChecklist.pedagogico => pedagogicoOk,
    ItemChecklist.financeiro => financeiroOk,
    ItemChecklist.formatura => formatura,
  };

  String get rotuloAluno =>
      codigoSgf == null ? alunoNome : '$alunoNome ($codigoSgf)';
}

/// O resumo do checklist em palavras — é o que a coluna Checklist anuncia ao
/// leitor de tela, o que a busca enxerga e o que o cartão do celular mostra.
///
/// ⚠️ O wireframe §12.1 desenha `P ✓ F ✓ Fo ─`, e o `✓` **não vai para a tela**:
/// o app empacota só Inter e Roboto, e a CSP bloqueia o download da fonte de
/// emoji — o glifo viraria caixa vazia (o portão `texto_de_tela_test` reprova).
/// Na tela as marcas são ícones do Material; aqui está a forma legível.
/// Divergência registrada em docs/wireframes.md §17.
String resumoChecklist(LinhaFilaCertificado linha) {
  if (!linha.temChecklist) return semChecklist;
  return [
    for (final item in ItemChecklist.values)
      '${item.sigla} ${linha.marca(item) == true ? 'ok' : 'pendente'}',
  ].join(' · ');
}

/// O status do certificado de uma linha da fila. Sem checklist não há status —
/// e um "Não pedido" ali afirmaria que alguém já olhou o caso.
String rotuloStatusDaLinha(LinhaFilaCertificado linha) =>
    linha.certificadoStatus == null
    ? '—'
    : rotuloStatusCertificado(linha.certificadoStatus!);

// ---------------------------------------------------------------------------
// Checklist — uma linha de certificado_checklist
// ---------------------------------------------------------------------------

/// Quem marcou um item e quando. Gravados por trigger, nunca pelo chamador
/// (card 8.3) — vale inclusive para escrita direta pelo PostgREST.
///
/// [nome] é nulo quando a política de `usuario` não deixa ler a linha da pessoa:
/// só `admin.ler` e o próprio usuário leem `usuario`. A tela mostra "por Fulano"
/// quando existe e só a data quando não existe — é o mesmo desenho do histórico
/// de status da ficha (card 4.6).
@immutable
class AutoriaItem {
  const AutoriaItem({this.nome, this.quando});

  final String? nome;
  final DateTime? quando;

  bool get vazia => quando == null && nome == null;
}

/// O checklist do certificado de um aluno (`certificado_checklist`).
@immutable
class ChecklistCertificado {
  const ChecklistCertificado({
    required this.id,
    required this.alunoId,
    required this.dataFimCurso,
    required this.pedagogicoOk,
    required this.financeiroOk,
    required this.formatura,
    required this.certificadoStatus,
    this.autorias = const {},
    this.autoriaStatus = const AutoriaItem(),
  });

  factory ChecklistCertificado.deLinha(Map<String, dynamic> linha) {
    String? nomeDe(String chave) {
      final valor = linha[chave];
      return valor is Map ? valor['nome'] as String? : null;
    }

    DateTime? quandoDe(String chave) {
      final valor = linha[chave];
      return valor == null ? null : DateTime.parse('$valor').toLocal();
    }

    return ChecklistCertificado(
      id: '${linha['id']}',
      alunoId: '${linha['aluno_id']}',
      dataFimCurso: DateTime.parse('${linha['data_fim_curso']}'),
      pedagogicoOk: linha['pedagogico_ok'] as bool? ?? false,
      financeiroOk: linha['financeiro_ok'] as bool? ?? false,
      formatura: linha['formatura'] as bool? ?? false,
      certificadoStatus: '${linha['certificado_status']}',
      autorias: {
        ItemChecklist.pedagogico: AutoriaItem(
          nome: nomeDe('pedagogico_usuario'),
          quando: quandoDe('pedagogico_em'),
        ),
        ItemChecklist.financeiro: AutoriaItem(
          nome: nomeDe('financeiro_usuario'),
          quando: quandoDe('financeiro_em'),
        ),
        ItemChecklist.formatura: AutoriaItem(
          nome: nomeDe('formatura_usuario'),
          quando: quandoDe('formatura_em'),
        ),
      },
      autoriaStatus: AutoriaItem(
        nome: nomeDe('certificado_usuario'),
        quando: quandoDe('certificado_em'),
      ),
    );
  }

  final String id;
  final String alunoId;
  final DateTime dataFimCurso;
  final bool pedagogicoOk;
  final bool financeiroOk;
  final bool formatura;
  final String certificadoStatus;
  final Map<ItemChecklist, AutoriaItem> autorias;
  final AutoriaItem autoriaStatus;

  bool marca(ItemChecklist item) => switch (item) {
    ItemChecklist.pedagogico => pedagogicoOk,
    ItemChecklist.financeiro => financeiroOk,
    ItemChecklist.formatura => formatura,
  };

  AutoriaItem autoria(ItemChecklist item) =>
      autorias[item] ?? const AutoriaItem();

  /// Os três itens marcados **e** o certificado entregue — a condição exata de
  /// `tg_certificado_sugere_formado`. A tela a usa só para dizer que a sugestão
  /// já foi feita; quem sugere é o banco, e quem forma é uma pessoa.
  bool get completo =>
      pedagogicoOk &&
      financeiroOk &&
      formatura &&
      certificadoStatus == 'ENTREGUE';
}

// ---------------------------------------------------------------------------
// Filtro da fila — wireframe §12.1
// ---------------------------------------------------------------------------

bool _casaBusca(String busca, Iterable<String?> campos) {
  final termo = busca.trim().toLowerCase();
  if (termo.isEmpty) return true;
  return campos.any((c) => c != null && c.toLowerCase().contains(termo));
}

@immutable
class FiltroCertificados {
  const FiltroCertificados({
    this.busca = '',
    this.metodoId,
    this.situacao,
    this.soFinanceiroPendente = false,
  });

  final String busca;
  final String? metodoId;

  /// [situacaoFim] ou [situacaoUltimoLivro].
  final String? situacao;

  /// A jornada nº 2 do monitor (wireframe §12.2): a fila filtrada por
  /// "financeiro pendente", com a caixa acionável na própria lista.
  ///
  /// ⚠️ Aluno **sem checklist** entra neste filtro: o financeiro dele está tão
  /// pendente quanto o de quem tem checklist com a caixa vazia — mais, até,
  /// porque nem o checklist existe. Deixá-lo de fora esconderia da fila do
  /// monitor exatamente quem precisa de uma ação a mais.
  final bool soFinanceiroPendente;

  int get ativos =>
      (busca.trim().isEmpty ? 0 : 1) +
      (metodoId == null ? 0 : 1) +
      (situacao == null ? 0 : 1) +
      (soFinanceiroPendente ? 1 : 0);

  FiltroCertificados copiar({
    String? busca,
    String? Function()? metodoId,
    String? Function()? situacao,
    bool? soFinanceiroPendente,
  }) => FiltroCertificados(
    busca: busca ?? this.busca,
    metodoId: metodoId == null ? this.metodoId : metodoId(),
    situacao: situacao == null ? this.situacao : situacao(),
    soFinanceiroPendente: soFinanceiroPendente ?? this.soFinanceiroPendente,
  );
}

List<LinhaFilaCertificado> filtrarFila(
  Iterable<LinhaFilaCertificado> todas,
  FiltroCertificados filtro,
) => [
  for (final l in todas)
    if ((filtro.metodoId == null || l.metodoId == filtro.metodoId) &&
        (filtro.situacao == null || l.situacao == filtro.situacao) &&
        (!filtro.soFinanceiroPendente || l.financeiroOk != true) &&
        _casaBusca(filtro.busca, [l.alunoNome, l.codigoSgf]))
      l,
];

/// A ordem da fila: **FIM primeiro** — quem já terminou não tem mais prazo —, e
/// dentro de cada situação a data de fim de curso mais antiga na frente.
///
/// ⚠️ Quem ainda não tem checklist não tem `data_fim_curso`, e vai para o fim do
/// próprio grupo: ordenar nulo como "muito antigo" poria na frente da fila
/// exatamente quem ninguém ainda começou a preparar.
List<LinhaFilaCertificado> ordenarFila(Iterable<LinhaFilaCertificado> fila) =>
    fila.toList()..sort((a, b) {
      final porSituacao = situacoesDaFila
          .indexOf(a.situacao)
          .compareTo(situacoesDaFila.indexOf(b.situacao));
      if (porSituacao != 0) return porSituacao;
      final da = a.dataFimCurso;
      final db = b.dataFimCurso;
      if (da != null && db != null && da != db) return da.compareTo(db);
      if (da == null && db != null) return 1;
      if (da != null && db == null) return -1;
      return a.alunoNome.compareTo(b.alunoNome);
    });

/// As situações presentes na fila de hoje, na ordem de leitura — o filtro só
/// oferece o que existe, senão a pessoa escolhe e recebe a lista vazia.
List<String> situacoesPresentes(Iterable<LinhaFilaCertificado> fila) {
  final presentes = {for (final l in fila) l.situacao};
  return [
    for (final s in situacoesDaFila)
      if (presentes.contains(s)) s,
    for (final s in (presentes.toList()..sort()))
      if (!situacoesDaFila.contains(s)) s,
  ];
}

// ---------------------------------------------------------------------------
// Textos de tela — docs/design-system.md §7.2 e §7.3
// ---------------------------------------------------------------------------

/// §7.2, linha "Certificados".
const vazioCertificados = 'Ninguém chegando ao fim do curso agora.';

const vazioCertificadosFiltro = 'Nenhum aluno com esses filtros.';

/// O que a coluna Checklist diz de quem ainda não tem um.
const semChecklist = 'Sem checklist';

/// O aluno da fila que ainda não tem checklist — e por que isso é normal.
const explicacaoSemChecklist =
    'O checklist é aberto sozinho quando o aluno recebe a última apostila da '
    'trilha. Dá para abrir antes, para adiantar o pedido do certificado.';

/// A nota do wireframe §12.2, palavra por palavra no que ela decide: o sistema
/// **sugere**, e quem forma o aluno é uma pessoa.
const avisoSugereFormado =
    'Com tudo marcado e o certificado entregue, o sistema sugere FORMADO como '
    'pendência — quem forma o aluno é uma pessoa.';

/// O mesmo aviso depois que a condição fechou.
const avisoFormadoSugerido =
    'Checklist completo: a sugestão de formar o aluno já está na central de '
    'Pendências.';

/// Confirmações efêmeras (design-system §5.8) — nenhuma delas muda o que a
/// pessoa fará em seguida, então snackbar basta.
const confirmacaoChecklistAberto = 'Checklist aberto.';
const confirmacaoItemMarcado = 'Checklist atualizado.';
const confirmacaoStatusAlterado = 'Status do certificado atualizado.';

/// "por Paula, 20/08" · "20/08" · "—" (wireframe §12.2).
String rotuloAutoria(AutoriaItem autoria, String Function(DateTime) formatar) {
  final quando = autoria.quando;
  if (quando == null) return '—';
  final nome = autoria.nome;
  return nome == null ? formatar(quando) : 'por $nome, ${formatar(quando)}';
}
