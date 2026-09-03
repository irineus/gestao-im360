/// A administração como o app a vê (card 4.7): os modelos das tabelas de
/// organização e acesso do card 3.3 que a tela lê e escreve (`usuario`,
/// `usuario_perfil`, `perfil`, `permissao`, `perfil_permissao`, `parametro`),
/// o histórico da matriz do card 4.7.5 e a lógica **pura** da tela —
/// agrupamento por domínio, quem está sem perfil, o plano de perfis de um
/// usuário, validação de formato dos parâmetros e filtros.
///
/// Pura de propósito: é o que se testa sem rede e sem cliente Supabase
/// (card 2.8 §9.3). Quem decide o que cada perfil pode é a matriz no banco;
/// aqui só há forma.
library;

import 'package:flutter/foundation.dart';

import '../infraestrutura/infraestrutura.dart' show dataIso, lerData;

/// Os 12 domínios do catálogo (card 2.4 §2), na ordem do menu do wireframe —
/// operação primeiro, material depois, administração por último. A chave é
/// `permissao.dominio`; o app nunca compara pelo rótulo.
const dominios = <String, String>{
  'alunos': 'Alunos',
  'turmas': 'Turmas',
  'pendencias': 'Pendências',
  'materiais': 'Materiais',
  'estoque': 'Estoque',
  'compras': 'Compras',
  'certificados': 'Certificados',
  'salas': 'Salas e PCs',
  'professores': 'Professores',
  'admin': 'Administração',
  'unidades': 'Unidades',
  'parametros': 'Parâmetros',
};

String rotuloDominio(String dominio) => dominios[dominio] ?? dominio;

/// Conjunto fechado no `check` de `parametro.tipo` (card 3.3).
const tiposParametro = <String, String>{
  'TEXTO': 'Texto',
  'INTEIRO': 'Inteiro',
  'DECIMAL': 'Decimal',
  'BOOLEANO': 'Sim/não',
  'DATA': 'Data',
};

String rotuloTipoParametro(String tipo) => tiposParametro[tipo] ?? tipo;

// ---------------------------------------------------------------------------
// Modelos
// ---------------------------------------------------------------------------

@immutable
class UsuarioAdmin {
  const UsuarioAdmin({
    required this.id,
    required this.nome,
    required this.email,
    this.ativo = true,
    this.perfisIds = const {},
    this.convitePendente = false,
  });

  factory UsuarioAdmin.deLinha(
    Map<String, dynamic> linha, {
    Set<String> perfisIds = const {},
    bool convitePendente = false,
  }) => UsuarioAdmin(
    id: '${linha['id']}',
    nome: '${linha['nome']}',
    email: '${linha['email']}',
    ativo: linha['ativo'] as bool? ?? true,
    perfisIds: perfisIds,
    convitePendente: convitePendente,
  );

  final String id;
  final String nome;

  /// Espelho do Auth (card 3.5): a tela mostra, nunca edita — `EMAIL_IMUTAVEL`.
  final String email;
  final bool ativo;
  final Set<String> perfisIds;

  /// Entra e não vê nada (docs/acesso-autenticacao.md §3.1). É o que a tela
  /// tem de MOSTRAR — hoje só se descobre quando a pessoa tenta entrar
  /// (ajuste do card 3.7).
  bool get semPerfil => perfisIds.isEmpty;

  /// Ainda não abriu o link do convite nem definiu senha
  /// (`auth.users.email_confirmed_at is null`, via `fn_convites_pendentes`).
  ///
  /// É o mesmo pivô que o GoTrue usa para decidir entre reenviar o convite e
  /// recusar com `email_exists` (card 4.7,7), então diz **exatamente** para
  /// quem "Reenviar convite" funciona — e não uma aproximação disso.
  final bool convitePendente;

  UsuarioAdmin copiar({
    String? nome,
    bool? ativo,
    Set<String>? perfisIds,
    bool? convitePendente,
  }) => UsuarioAdmin(
    id: id,
    nome: nome ?? this.nome,
    email: email,
    ativo: ativo ?? this.ativo,
    perfisIds: perfisIds ?? this.perfisIds,
    convitePendente: convitePendente ?? this.convitePendente,
  );

  /// Só o que o app pode mudar: nome e ativo. E-mail é do Auth; unidade não
  /// muda de usuário.
  Map<String, dynamic> paraLinha() => {'nome': nome.trim(), 'ativo': ativo};
}

@immutable
class Perfil {
  const Perfil({
    this.id,
    required this.codigo,
    required this.nome,
    this.ativo = true,
  });

  factory Perfil.deLinha(Map<String, dynamic> linha) => Perfil(
    id: '${linha['id']}',
    codigo: '${linha['codigo']}',
    nome: '${linha['nome']}',
    ativo: linha['ativo'] as bool? ?? true,
  );

  /// Nulo = ainda não gravado.
  final String? id;

  /// Chave natural (`perfil_codigo_uk`), imutável depois de criado: é o que o
  /// histórico da matriz grava em texto.
  final String codigo;
  final String nome;

  /// Perfil desativado não concede nada, mesmo com a matriz intacta
  /// (`tem_permissao`, card 3.4).
  final bool ativo;

  Map<String, dynamic> paraLinha(String unidadeId) => {
    'unidade_id': unidadeId,
    'codigo': codigo.trim(),
    'nome': nome.trim(),
    'ativo': ativo,
  };
}

@immutable
class Permissao {
  const Permissao({
    required this.id,
    required this.codigo,
    required this.descricao,
    required this.dominio,
    this.ativo = true,
  });

  factory Permissao.deLinha(Map<String, dynamic> linha) => Permissao(
    id: '${linha['id']}',
    codigo: '${linha['codigo']}',
    descricao: '${linha['descricao']}',
    dominio: '${linha['dominio']}',
    ativo: linha['ativo'] as bool? ?? true,
  );

  final String id;
  final String codigo;

  /// É para isto que a descrição existe no seed (card 2.4 §8):
  /// "`estoque.ajustar` sozinho não diz a ninguém o que acontece se a caixa for
  /// marcada".
  final String descricao;
  final String dominio;
  final bool ativo;
}

@immutable
class Parametro {
  const Parametro({
    this.id,
    required this.chave,
    required this.valor,
    this.tipo = 'INTEIRO',
    this.descricao,
  });

  factory Parametro.deLinha(Map<String, dynamic> linha) => Parametro(
    id: '${linha['id']}',
    chave: '${linha['chave']}',
    valor: '${linha['valor']}',
    tipo: '${linha['tipo']}',
    descricao: linha['descricao'] as String?,
  );

  final String? id;
  final String chave;

  /// Sempre texto no banco (`parametro.valor`); quem o interpreta é
  /// `fn_param_int`/`fn_param_txt`. Datas ficam em `yyyy-mm-dd`.
  final String valor;
  final String tipo;
  final String? descricao;

  Map<String, dynamic> paraLinha(String unidadeId) => {
    'unidade_id': unidadeId,
    'chave': chave.trim(),
    'valor': valor,
    'tipo': tipo,
    'descricao': (descricao == null || descricao!.trim().isEmpty)
        ? null
        : descricao!.trim(),
  };
}

/// Uma linha de `perfil_permissao_hist` (card 4.7.5), já com o nome de quem
/// mexeu. `porNome` nulo = a migração (seed), não uma pessoa.
@immutable
class LinhaHistoricoMatriz {
  const LinhaHistoricoMatriz({
    required this.perfilCodigo,
    required this.permissaoCodigo,
    required this.acao,
    required this.em,
    this.porNome,
  });

  final String perfilCodigo;
  final String permissaoCodigo;

  /// `CONCEDIDA` ou `REMOVIDA`.
  final String acao;
  final DateTime em;
  final String? porNome;
}

const acoesHistorico = <String, String>{
  'CONCEDIDA': 'Concedida',
  'REMOVIDA': 'Removida',
};

String rotuloAcaoHistorico(String acao) => acoesHistorico[acao] ?? acao;

/// Quem fez: o nome, ou "sistema" quando foi a migração.
String rotuloAutorHistorico(String? porNome) => porNome ?? 'sistema (seed)';

String _dois(int n) => n.toString().padLeft(2, '0');

/// `dd/mm/aaaa hh:mm`, para os carimbos do histórico.
String formatarQuando(DateTime d) {
  final l = d.toLocal();
  return '${_dois(l.day)}/${_dois(l.month)}/${l.year} '
      '${_dois(l.hour)}:${_dois(l.minute)}';
}

// ---------------------------------------------------------------------------
// Derivações — informativas, nunca regra (card 2.6 decisão 2)
// ---------------------------------------------------------------------------

/// Um domínio da matriz, com as suas permissões em ordem de código.
@immutable
class GrupoPermissoes {
  const GrupoPermissoes({
    required this.dominio,
    required this.rotulo,
    required this.permissoes,
  });

  final String dominio;
  final String rotulo;
  final List<Permissao> permissoes;
}

/// Agrupa pelos 12 domínios, na ordem do menu; domínio que o app não conhece
/// (código novo de uma migração futura) vai para o fim, em ordem alfabética,
/// em vez de sumir.
List<GrupoPermissoes> agruparPorDominio(Iterable<Permissao> permissoes) {
  final porDominio = <String, List<Permissao>>{};
  for (final p in permissoes) {
    porDominio.putIfAbsent(p.dominio, () => []).add(p);
  }
  final conhecidos = dominios.keys.where(porDominio.containsKey);
  final desconhecidos =
      porDominio.keys.where((d) => !dominios.containsKey(d)).toList()..sort();
  return [
    for (final d in [...conhecidos, ...desconhecidos])
      GrupoPermissoes(
        dominio: d,
        rotulo: rotuloDominio(d),
        permissoes: porDominio[d]!
          ..sort((a, b) => a.codigo.compareTo(b.codigo)),
      ),
  ];
}

/// Os códigos dos perfis do usuário, em ordem — ou "sem perfil".
String rotuloPerfis(UsuarioAdmin usuario, Map<String, Perfil> perfisPorId) {
  if (usuario.semPerfil) return 'sem perfil';
  final codigos = [
    for (final id in usuario.perfisIds) perfisPorId[id]?.codigo ?? '?',
  ]..sort();
  return codigos.join(', ');
}

/// Quantos usuários ATIVOS estão sem perfil — o número que a tela destaca.
/// Desativado sem perfil não é problema: não entra de qualquer jeito.
int contarSemPerfil(Iterable<UsuarioAdmin> usuarios) =>
    usuarios.where((u) => u.ativo && u.semPerfil).length;

/// A situação da pessoa em uma palavra, na coluna da lista. A ordem é a
/// decisão: desativado vence convite pendente, porque reenviar convite a quem
/// não pode entrar não resolve nada — e é o estado mais consequente dos dois.
String situacaoUsuario(UsuarioAdmin usuario) => !usuario.ativo
    ? 'Desativado'
    : usuario.convitePendente
    ? 'Convite pendente'
    : 'Ativo';

/// A linha de apoio do cartão no mobile, onde não há coluna "Situação" para o
/// convite pendente aparecer: os perfis (ou a falta deles) e, quando for o
/// caso, o convite ainda não aceito. Os dois cabem, e respondem perguntas
/// diferentes — "o que essa pessoa pode" e "ela já entrou alguma vez".
String apoioUsuario(UsuarioAdmin usuario, Map<String, Perfil> perfisPorId) {
  if (!usuario.ativo) return 'Desativado';
  final perfis = usuario.semPerfil
      ? '⚠ sem perfil'
      : rotuloPerfis(usuario, perfisPorId);
  return usuario.convitePendente ? '$perfis · convite pendente' : perfis;
}

/// Quando "Reenviar convite" é oferecido (card 4.7,7): só a quem ainda não
/// aceitou **e** está ativo. Para quem já definiu senha o GoTrue recusa com
/// `email_exists`, e botão que só sabe falhar é pior do que botão nenhum.
bool podeReenviarConvite(UsuarioAdmin usuario) =>
    usuario.ativo && usuario.convitePendente;

/// O que muda em `usuario_perfil` para o usuário ficar com [desejados]:
/// inserir o que falta, apagar o que sobra. A tabela não tem `update`
/// (card 2.4 §4) — é sempre insert e delete.
@immutable
class PlanoPerfis {
  const PlanoPerfis({required this.inserir, required this.remover});

  final Set<String> inserir;
  final Set<String> remover;

  bool get vazio => inserir.isEmpty && remover.isEmpty;
}

PlanoPerfis planejarPerfis(Set<String> atuais, Set<String> desejados) =>
    PlanoPerfis(
      inserir: desejados.difference(atuais),
      remover: atuais.difference(desejados),
    );

/// Quantas permissões cada perfil tem — o "n de 50" do cabeçalho da matriz.
int contarMarcadas(Map<String, Set<String>> matriz, String? perfilId) =>
    perfilId == null ? 0 : (matriz[perfilId]?.length ?? 0);

/// Aviso de consequência ao editar parâmetro (design-system §7.3): os que as
/// rotinas `pg_cron` leem só valem na próxima execução. `rep_*` e
/// `projecao_*` são os do card 2.7; `ritmo_*` e `standby_*` são lidos pelas
/// mesmas rotinas (cards 2.5 e Ordem 5) e recebem o mesmo aviso.
const avisoParametroRotina =
    'Vale a partir da próxima execução da rotina diária (madrugada).';

String? avisoParametro(String chave) {
  const prefixos = ['rep_', 'projecao_', 'ritmo_', 'standby_'];
  return prefixos.any(chave.startsWith) ? avisoParametroRotina : null;
}

final _formatoCodigoPerfil = RegExp(r'^[A-Z][A-Z0-9_]*$');
final _formatoChave = RegExp(r'^[a-z][a-z0-9_]*[a-zA-Z0-9_]*$');
final _formatoDecimal = RegExp(r'^-?\d+([.,]\d+)?$');

/// Código de perfil: letras, dígitos e sublinhado, como os quatro do seed
/// (`DIRECAO`, `SECRETARIA`…). Validado já em caixa alta — é assim que o
/// formulário grava —, então `coordenacao` passa e vira `COORDENACAO`. É chave
/// natural e vai para o histórico.
String? validarCodigoPerfil(String? valor) {
  final texto = (valor?.trim() ?? '').toUpperCase();
  if (texto.isEmpty) return 'Campo obrigatório.';
  if (!_formatoCodigoPerfil.hasMatch(texto)) {
    return 'Use letras maiúsculas, dígitos e _ (ex.: COORDENACAO).';
  }
  return null;
}

/// Chave de parâmetro: `snake_case`, como as 16 do seed
/// (`ritmo_padrao_dias_INTERATIVO` inclusive).
String? validarChaveParametro(String? valor) {
  final texto = valor?.trim() ?? '';
  if (texto.isEmpty) return 'Campo obrigatório.';
  if (!_formatoChave.hasMatch(texto)) {
    return 'Use letras, dígitos e _, começando por letra minúscula.';
  }
  return null;
}

/// Validação local só de formato, por tipo (design-system §5.4). O que o
/// valor SIGNIFICA quem confere é a função que o lê.
String? validarValorParametro(String tipo, String? valor) {
  final texto = valor?.trim() ?? '';
  if (texto.isEmpty) return 'Campo obrigatório.';
  return switch (tipo) {
    'INTEIRO' =>
      int.tryParse(texto) == null ? 'Informe um número inteiro.' : null,
    'DECIMAL' => _formatoDecimal.hasMatch(texto) ? null : 'Informe um número.',
    'BOOLEANO' =>
      const {'true', 'false'}.contains(texto.toLowerCase())
          ? null
          : 'Informe true ou false.',
    'DATA' =>
      lerData(texto) == null ? 'Informe uma data como dd/mm/aaaa.' : null,
    _ => null,
  };
}

/// O texto digitado como o banco o guarda: decimal com ponto, booleano em
/// minúsculas, data em `yyyy-mm-dd`.
String normalizarValorParametro(String tipo, String valor) {
  final texto = valor.trim();
  return switch (tipo) {
    'DECIMAL' => texto.replaceAll(',', '.'),
    'BOOLEANO' => texto.toLowerCase(),
    'DATA' => lerData(texto) == null ? texto : dataIso(lerData(texto)!),
    _ => texto,
  };
}

/// O valor do banco como a pessoa o lê: data em dd/mm/aaaa, o resto como está.
String exibirValorParametro(Parametro p) {
  if (p.tipo != 'DATA') return p.valor;
  final data = DateTime.tryParse(p.valor);
  if (data == null) return p.valor;
  return '${_dois(data.day)}/${_dois(data.month)}/${data.year}';
}

// ---------------------------------------------------------------------------
// Filtros — estado da tela, desligável e visível (design-system §5.3)
// ---------------------------------------------------------------------------

@immutable
class FiltroUsuarios {
  const FiltroUsuarios({
    this.busca = '',
    this.soAtivos = true,
    this.soSemPerfil = false,
  });

  /// "Limpar filtros" mostra **tudo**, inclusive o desativado (card 4.4 (g)).
  static const semFiltro = FiltroUsuarios(soAtivos: false);

  final String busca;
  final bool soAtivos;
  final bool soSemPerfil;

  int get ativos =>
      (busca.trim().isNotEmpty ? 1 : 0) +
      (soAtivos ? 1 : 0) +
      (soSemPerfil ? 1 : 0);

  FiltroUsuarios copiar({String? busca, bool? soAtivos, bool? soSemPerfil}) =>
      FiltroUsuarios(
        busca: busca ?? this.busca,
        soAtivos: soAtivos ?? this.soAtivos,
        soSemPerfil: soSemPerfil ?? this.soSemPerfil,
      );
}

bool _casaBusca(String busca, Iterable<String> campos) {
  final termo = busca.trim().toLowerCase();
  if (termo.isEmpty) return true;
  return campos.any((c) => c.toLowerCase().contains(termo));
}

List<UsuarioAdmin> filtrarUsuarios(
  List<UsuarioAdmin> todos,
  FiltroUsuarios filtro,
) => [
  for (final u in todos)
    if ((!filtro.soAtivos || u.ativo) &&
        (!filtro.soSemPerfil || u.semPerfil) &&
        _casaBusca(filtro.busca, [u.nome, u.email]))
      u,
];
