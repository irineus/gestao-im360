/// A importação como o app a vê (card 9.1): os modelos de `v_importacao` e
/// `v_importacao_ocorrencia`, os totais do passo 4 e a **leitura do arquivo** —
/// a única parte da importação que roda em Dart.
///
/// Pura de propósito: é o que se testa sem rede e sem cliente Supabase
/// (card 2.8 §9.3).
///
/// ⚠️ **Nada neste arquivo valida nada.** Quem valida é `fn_importacao_validar`,
/// com as dezesseis verificações de `docs/importacao.md` §4, e quem aplica é
/// `fn_importacao_aplicar`. O que a tela faz aqui é abrir o arquivo, conferir
/// que é um objeto JSON e CONTAR o que ele traz por entidade — o "265 alunos
/// lidos" do passo 3 do wireframe. Uma segunda validação em Dart seria a
/// "terceira implementação" que o card 2.3 §4.1 proíbe, e divergiria da do
/// banco no primeiro caso de borda.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// As dezoito entidades do arquivo, na ORDEM DE DEPENDÊNCIA
// ---------------------------------------------------------------------------

/// Cópia literal da lista de `fn_importacao_registrar` (migração
/// `20260906120000_importacao.sql`) e de `docs/importacao.md` §3.
///
/// A ordem é a de aplicação: professor antes de bloco, material antes de
/// trilha. A tela a usa para listar as contagens na mesma ordem em que o banco
/// escreve — ler o relatório de cima para baixo é ler a ordem dos fatos.
const entidadesImportacao = <String>[
  'professor',
  'sala',
  'pc',
  'pc_manutencao',
  'material',
  'curso',
  'curso_material',
  'modulo',
  'combo',
  'combo_curso',
  'aluno',
  'bloco_horario',
  'bloco_aluno',
  'turma_modular',
  'turma_modular_modulo',
  'turma_modular_aluno',
  'aluno_material',
  'movimento_estoque',
];

/// Rótulo em português da entidade. Código desconhecido volta como veio —
/// inventar rótulo para uma entidade que o banco passou a conhecer esconderia
/// justamente a novidade (mesma regra de `rotuloRegra` no card 8.5).
String rotuloEntidade(String codigo) => switch (codigo) {
  'professor' => 'Professores',
  'sala' => 'Salas',
  'pc' => 'PCs',
  'pc_manutencao' => 'Manutenções de PC',
  'material' => 'Materiais',
  'curso' => 'Cursos',
  'curso_material' => 'Sequência do curso',
  'modulo' => 'Módulos',
  'combo' => 'Combos',
  'combo_curso' => 'Cursos do combo',
  'aluno' => 'Alunos',
  'bloco_horario' => 'Blocos de horário',
  'bloco_aluno' => 'Alunos em blocos',
  'turma_modular' => 'Turmas Modular',
  'turma_modular_modulo' => 'Cronograma Modular',
  'turma_modular_aluno' => 'Alunos em turmas Modular',
  'aluno_material' => 'Trilhas',
  'movimento_estoque' => 'Movimentos de estoque',
  'importacao' => 'Importação',
  _ => codigo,
};

// ---------------------------------------------------------------------------
// O arquivo lido da máquina de quem importa
// ---------------------------------------------------------------------------

/// O que o seletor de arquivo devolve: nome e conteúdo em texto.
@immutable
class ArquivoEscolhido {
  const ArquivoEscolhido({required this.nome, required this.conteudo});

  final String nome;
  final String conteudo;
}

/// O arquivo já aberto: ou o objeto JSON pronto para ir ao banco, ou o motivo
/// de não dar.
///
/// ⚠️ O formato é **JSON**, um objeto com um array por entidade — e não os
/// "CSVs normalizados" que o plano §8 escreveu em 30/08/2026, quando a carga
/// ainda seria feita por script na linha de comando. Divergência registrada em
/// `docs/importacao.md` §2: dezoito entidades em CSV são dezoito arquivos (ou um
/// zip que o navegador não abre sem dependência nova), e o produtor do arquivo é
/// nosso — o card 9.2. JSON também carrega tipo: `10` continua número e `"10"`
/// continua texto, o que num CSV se perde e vira adivinhação na hora de
/// converter.
@immutable
class ArquivoImportacao {
  const ArquivoImportacao._({this.dados, this.erro, this.snapshotEm});

  /// O objeto pronto para `fn_importacao_registrar`. Nulo quando [erro] está
  /// preenchido.
  final Map<String, dynamic>? dados;

  /// Mensagem em português do que impediu a leitura. Nula quando deu certo.
  final String? erro;

  /// `snapshot_em` do próprio arquivo, quando o extrator o escreveu. É uma
  /// SUGESTÃO para o campo da tela, não um valor imposto: quem responde pela
  /// data do snapshot é quem importa (card 9.4).
  final DateTime? snapshotEm;

  bool get valido => dados != null;

  /// Quantas linhas o arquivo traz por entidade, na ordem de aplicação. Só as
  /// entidades presentes entram — listar dezoito zeros esconderia as que vieram.
  List<MapEntry<String, int>> get contagens => [
    for (final entidade in entidadesImportacao)
      if (dados?[entidade] is List)
        MapEntry(entidade, (dados![entidade] as List).length),
  ];

  int get totalLinhas =>
      contagens.fold(0, (soma, entrada) => soma + entrada.value);

  /// Chaves que a importação não conhece. O banco também avisa (verificação V1),
  /// e aqui a mesma pergunta é respondida **antes do upload** — é a diferença
  /// entre descobrir a aba renomeada agora e descobrir depois de mandar 4 MB.
  List<String> get entidadesDesconhecidas => [
    for (final chave in (dados?.keys ?? const <String>[]))
      if (chave != 'snapshot_em' && !entidadesImportacao.contains(chave)) chave,
  ];

  static ArquivoImportacao erroDe(String mensagem) =>
      ArquivoImportacao._(erro: mensagem);

  /// Abre o conteúdo do arquivo. Não valida negócio nenhum: só garante que dá
  /// para mandar ao banco.
  factory ArquivoImportacao.deTexto(String conteudo) {
    if (conteudo.trim().isEmpty) {
      return ArquivoImportacao.erroDe('O arquivo escolhido está vazio.');
    }

    final Object? decodificado;
    try {
      decodificado = jsonDecode(conteudo);
    } on FormatException catch (e) {
      // A posição ajuda de verdade num arquivo de milhares de linhas, e é o que
      // o extrator do card 9.2 usa para achar o próprio defeito.
      return ArquivoImportacao.erroDe(
        'O arquivo não é um JSON válido${e.offset == null ? '' : ' (posição ${e.offset})'}. '
        'Ele é gerado pelo script de extração da planilha.',
      );
    }

    if (decodificado is! Map<String, dynamic>) {
      return ArquivoImportacao.erroDe(
        'O arquivo precisa ser um objeto JSON com uma lista por entidade '
        '(alunos, materiais, turmas…), e este não é.',
      );
    }

    // Cópia local depois da checagem: uma variável só atribuída dentro do `try`
    // não é promovida DENTRO DE CLOSURE, e o `any` abaixo é uma. Sem esta
    // linha o analisador reprova com "receiver can be null".
    final mapa = decodificado;

    if (!entidadesImportacao.any((e) => mapa[e] is List)) {
      return ArquivoImportacao.erroDe(
        'O arquivo não traz nenhuma das entidades conhecidas. '
        'Confira se ele foi gerado pelo script de extração desta versão.',
      );
    }

    return ArquivoImportacao._(
      dados: mapa,
      snapshotEm: DateTime.tryParse('${mapa['snapshot_em']}'),
    );
  }
}

// ---------------------------------------------------------------------------
// O lote — `v_importacao`
// ---------------------------------------------------------------------------

/// Os quatro estados de `importacao.status`, com o rótulo que a tela mostra.
String rotuloStatusLote(String status) => switch (status) {
  'VALIDADA' => 'Validada',
  'REPROVADA' => 'Reprovada',
  'APLICADA' => 'Aplicada',
  'FALHOU' => 'Falhou',
  _ => status,
};

@immutable
class LoteImportacao {
  const LoteImportacao({
    required this.id,
    required this.arquivo,
    required this.snapshotEm,
    required this.status,
    required this.erros,
    required this.avisos,
    required this.criadoEm,
    this.totais,
    this.simuladoEm,
    this.aplicadoEm,
    this.aplicadoPorNome,
  });

  final String id;
  final String arquivo;
  final DateTime? snapshotEm;
  final String status;
  final int erros;
  final int avisos;
  final DateTime? criadoEm;
  final Map<String, dynamic>? totais;
  final DateTime? simuladoEm;
  final DateTime? aplicadoEm;
  final String? aplicadoPorNome;

  bool get podeAplicar => status == 'VALIDADA';
  bool get aplicado => status == 'APLICADA';

  factory LoteImportacao.deLinha(Map<String, dynamic> linha) => LoteImportacao(
    id: linha['id'] as String,
    arquivo: (linha['arquivo'] ?? '') as String,
    snapshotEm: DateTime.tryParse('${linha['snapshot_em']}'),
    status: (linha['status'] ?? '') as String,
    erros: (linha['erros'] as num?)?.toInt() ?? 0,
    avisos: (linha['avisos'] as num?)?.toInt() ?? 0,
    criadoEm: DateTime.tryParse('${linha['criado_em']}'),
    totais: linha['totais'] as Map<String, dynamic>?,
    simuladoEm: DateTime.tryParse('${linha['simulado_em']}'),
    aplicadoEm: DateTime.tryParse('${linha['aplicado_em']}'),
    aplicadoPorNome: linha['aplicado_por_nome'] as String?,
  );
}

// ---------------------------------------------------------------------------
// O relatório — `v_importacao_ocorrencia`
// ---------------------------------------------------------------------------

@immutable
class OcorrenciaImportacao {
  const OcorrenciaImportacao({
    required this.id,
    required this.severidade,
    required this.entidade,
    required this.codigo,
    required this.mensagem,
    this.linha,
    this.valor,
  });

  final String id;
  final String severidade;
  final String entidade;
  final String codigo;

  /// Já vem em português do banco. A tela **não** traduz por código: o catálogo
  /// do card 2.8 §10 é dos erros que chegam como exceção, e ocorrência de
  /// relatório não é exceção — ela carrega o próprio texto, com os números do
  /// caso dentro (docs/importacao.md §4).
  final String mensagem;

  final int? linha;
  final String? valor;

  bool get bloqueia => severidade == 'ERRO';

  factory OcorrenciaImportacao.deLinha(Map<String, dynamic> linha) =>
      OcorrenciaImportacao(
        id: linha['id'] as String,
        severidade: (linha['severidade'] ?? '') as String,
        entidade: (linha['entidade'] ?? '') as String,
        codigo: (linha['codigo'] ?? '') as String,
        mensagem: (linha['mensagem'] ?? '') as String,
        linha: (linha['linha'] as num?)?.toInt(),
        valor: linha['valor'] as String?,
      );
}

/// ERRO primeiro, depois por entidade e por linha. O relatório é lista de
/// trabalho: o que bloqueia a carga vem antes do que só pede uma olhada.
List<OcorrenciaImportacao> ordenarOcorrencias(
  List<OcorrenciaImportacao> ocorrencias,
) {
  final ordenadas = [...ocorrencias];
  ordenadas.sort((a, b) {
    if (a.bloqueia != b.bloqueia) return a.bloqueia ? -1 : 1;
    final porEntidade = entidadesImportacao
        .indexOf(a.entidade)
        .compareTo(entidadesImportacao.indexOf(b.entidade));
    if (porEntidade != 0) return porEntidade;
    return (a.linha ?? 0).compareTo(b.linha ?? 0);
  });
  return ordenadas;
}

// ---------------------------------------------------------------------------
// Os totais do passo 4
// ---------------------------------------------------------------------------

/// Uma linha da conferência: o que o arquivo trazia, o que a importação
/// escreveu, o que ela deixou de fora e **quanto existe no sistema**.
///
/// A última coluna é a que se compara com o Dashboard da planilha (card 9.4);
/// as outras três explicam a diferença quando ela aparece.
@immutable
class TotalImportacao {
  const TotalImportacao({
    required this.entidade,
    required this.arquivo,
    required this.aplicadas,
    required this.ignoradas,
    required this.noSistema,
  });

  final String entidade;
  final int arquivo;
  final int aplicadas;
  final int ignoradas;
  final int noSistema;
}

/// Lê o `jsonb` de `importacao.totais`. Formato tolerante de propósito: um lote
/// antigo, ou um simulado que falhou antes de contar, não pode derrubar a tela
/// que mostra o histórico.
List<TotalImportacao> lerTotais(Map<String, dynamic>? totais) {
  if (totais == null) return const [];
  final noSistema = totais['no_sistema'];
  return [
    for (final entidade in entidadesImportacao)
      if (totais[entidade] is Map<String, dynamic>)
        TotalImportacao(
          entidade: entidade,
          arquivo: _inteiro((totais[entidade] as Map)['arquivo']),
          aplicadas: _inteiro((totais[entidade] as Map)['aplicadas']),
          ignoradas: _inteiro((totais[entidade] as Map)['ignoradas']),
          noSistema: noSistema is Map<String, dynamic>
              ? _inteiro(noSistema[entidade])
              : 0,
        ),
  ];
}

int _inteiro(Object? valor) => switch (valor) {
  final num n => n.toInt(),
  final String s => int.tryParse(s) ?? 0,
  _ => 0,
};
