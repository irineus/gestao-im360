import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../erros/erro_app.dart';
import '../sessao/sessao_provider.dart';
import '../util/seletor_arquivo.dart';
import 'importacao.dart';
import 'importacao_repositorio.dart';

/// Repositório da importação — sobrescrito nos widget tests com dados
/// (card 2.8 §9.3).
final importacaoRepositorioProvider = Provider<ImportacaoRepositorio>(
  (ref) => ImportacaoRepositorioSupabase(ref.watch(clienteSupabaseProvider)),
);

/// O seletor de arquivo, atrás de provider pelo mesmo motivo do repositório: no
/// widget test não há navegador, e sem esta injeção a tela cairia direto no
/// estado "a importação é feita no navegador" — os quatro passos ficariam sem
/// nenhum teste, que é como os dois defeitos bloqueantes do card 8.1,5
/// atravessaram todo o CI.
final seletorArquivoProvider = Provider<Future<ArquivoEscolhido?> Function()>(
  (ref) => escolherArquivo,
);

/// Se existe seletor nesta plataforma. Separado do de cima porque a tela
/// precisa saber ANTES de desenhar o botão (design-system §5.7: sem estado,
/// visível e desabilitado com o motivo — aqui nem botão faz sentido).
final seletorDisponivelProvider = Provider<bool>(
  (ref) => seletorDeArquivoDisponivel,
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

/// Versão da importação em memória: toda leitura a observa e toda escrita a
/// incrementa (mesmo desenho da `VersaoCertificados` do card 8.6).
///
/// ⚠️ Aqui ela vale mais do que nas outras telas: aplicar um lote muda **o
/// sistema inteiro** — alunos, materiais, turmas, estoque. Quem estiver com a
/// tela de Alunos aberta noutra aba não é assunto desta versão; o que ela
/// garante é que a própria tela 13 não continue mostrando "Validada" depois de
/// aplicar.
class VersaoImportacao extends Notifier<int> {
  @override
  int build() => 0;

  void incrementar() => state++;
}

final versaoImportacaoProvider = NotifierProvider<VersaoImportacao, int>(
  VersaoImportacao.new,
);

ImportacaoRepositorio _repositorio(Ref ref) {
  ref.watch(versaoImportacaoProvider);
  return ref.watch(importacaoRepositorioProvider);
}

/// Os lotes desta unidade — o histórico do §16, que é o que torna a importação
/// **auditável** (plano §8).
final lotesImportacaoProvider = FutureProvider<List<LoteImportacao>>(
  (ref) => _traduzindo(() => _repositorio(ref).lotes()),
);

/// Um lote. `family` porque a tela acompanha o que acabou de criar.
final loteImportacaoProvider = FutureProvider.family<LoteImportacao?, String>(
  (ref, id) => _traduzindo(() => _repositorio(ref).lote(id)),
);

/// O relatório de um lote, já na ordem de trabalho (ERRO primeiro).
final ocorrenciasImportacaoProvider =
    FutureProvider.family<List<OcorrenciaImportacao>, String>(
      (ref, id) => _traduzindo(
        () async => ordenarOcorrencias(await _repositorio(ref).ocorrencias(id)),
      ),
    );

/// As duas escritas. Não são providers de leitura: quem as chama é o botão, e
/// quem mostra o resultado é a tela, relendo o lote pela versão.
class AcoesImportacao {
  const AcoesImportacao(this._ref);

  final Ref _ref;

  Future<String> registrar({
    required String arquivo,
    required DateTime snapshotEm,
    required Map<String, dynamic> dados,
  }) => _traduzindo(() async {
    final id = await _ref
        .read(importacaoRepositorioProvider)
        .registrar(arquivo: arquivo, snapshotEm: snapshotEm, dados: dados);
    _ref.read(versaoImportacaoProvider.notifier).incrementar();
    return id;
  });

  Future<Map<String, dynamic>> aplicar(String id, {required bool simular}) =>
      _traduzindo(() async {
        final resultado = await _ref
            .read(importacaoRepositorioProvider)
            .aplicar(id, simular: simular);
        _ref.read(versaoImportacaoProvider.notifier).incrementar();
        return resultado;
      });
}

final acoesImportacaoProvider = Provider<AcoesImportacao>(AcoesImportacao.new);
