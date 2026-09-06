import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../erros/erro_app.dart';
import '../sessao/sessao_provider.dart';
import 'certificados.dart';
import 'certificados_repositorio.dart';

/// Repositório dos certificados — sobrescrito nos widget tests com dados
/// (card 2.8 §9.3).
final certificadosRepositorioProvider = Provider<CertificadosRepositorio>(
  (ref) => CertificadosRepositorioSupabase(ref.watch(clienteSupabaseProvider)),
);

/// Traduz **uma vez**, no provider — cada rebuild não reenvia o mesmo erro ao
/// Sentry (card 3.12).
Future<T> _traduzindo<T>(Future<T> Function() acao) async {
  try {
    return await acao();
  } catch (erro) {
    throw traduzirErro(erro);
  }
}

/// Versão dos certificados em memória: toda leitura a observa e toda escrita a
/// incrementa (mesmo desenho da `VersaoTrilha` do card 6.6).
///
/// ⚠️ Marcar um item muda **duas** leituras: o checklist do aluno e a linha dele
/// na fila (a coluna Checklist e o status). Uma versão só para as duas é o que
/// impede a fila de continuar mostrando "F pendente" depois de o monitor ter
/// marcado o financeiro no painel ao lado.
class VersaoCertificados extends Notifier<int> {
  @override
  int build() => 0;

  void incrementar() => state++;
}

final versaoCertificadosProvider = NotifierProvider<VersaoCertificados, int>(
  VersaoCertificados.new,
);

CertificadosRepositorio _repositorio(Ref ref) {
  ref.watch(versaoCertificadosProvider);
  return ref.watch(certificadosRepositorioProvider);
}

/// A fila da tela 9 — `v_certificado_fila`, já ordenada como a tela a lê.
final filaCertificadosProvider = FutureProvider<List<LinhaFilaCertificado>>(
  (ref) => _traduzindo(() async => ordenarFila(await _repositorio(ref).fila())),
);

/// O checklist de UM aluno. `family` pela mesma razão da trilha (card 6.6): o
/// painel é de um aluno, e a aba Certificado da ficha também.
///
/// Nulo = o aluno ainda não tem checklist, que é o caso normal de quem está no
/// último livro. Não é erro, e a tela oferece abrir.
final checklistAlunoProvider =
    FutureProvider.family<ChecklistCertificado?, String>(
      (ref, alunoId) => _traduzindo(() => _repositorio(ref).checklist(alunoId)),
    );

/// As três escritas do certificado, num lugar só — tradução do erro e versão
/// (o molde de `AcoesImportacao`, card 9.1).
///
/// Nasceu na revisão das telas 08/09 (item F2): a lista da tela 9 e o
/// `BlocoChecklist` faziam, cada um, a mesma tradução + versão, e duas cópias
/// da mesma escrita é o que fica livre para divergir. A **confirmação** continua
/// com cada tela, porque o texto é dela (na lista diz o nome do aluno; no painel
/// o nome está no título).
class AcoesCertificado {
  const AcoesCertificado(this._ref);

  final Ref _ref;

  Future<void> abrirChecklist(String alunoId) =>
      _escrever((repositorio) => repositorio.abrirChecklist(alunoId));

  Future<void> marcarItem(
    String alunoId, {
    required String item,
    required bool valor,
  }) => _escrever(
    (repositorio) => repositorio.marcarItem(alunoId, item: item, valor: valor),
  );

  Future<void> alterarStatus(String alunoId, {required String status}) =>
      _escrever(
        (repositorio) => repositorio.alterarStatus(alunoId, status: status),
      );

  Future<void> _escrever(
    Future<void> Function(CertificadosRepositorio repositorio) acao,
  ) => _traduzindo(() async {
    await acao(_ref.read(certificadosRepositorioProvider));
    _ref.read(versaoCertificadosProvider.notifier).incrementar();
  });
}

final acoesCertificadoProvider = Provider<AcoesCertificado>(
  AcoesCertificado.new,
);

/// Filtro da fila — estado da tela, sobrevive à navegação de ida e volta dentro
/// da sessão (design-system §5.3).
class FiltroCertificadosNotifier extends Notifier<FiltroCertificados> {
  @override
  FiltroCertificados build() => const FiltroCertificados();

  void definir(FiltroCertificados filtro) => state = filtro;

  void limpar() => state = const FiltroCertificados();
}

final filtroCertificadosProvider =
    NotifierProvider<FiltroCertificadosNotifier, FiltroCertificados>(
      FiltroCertificadosNotifier.new,
    );
