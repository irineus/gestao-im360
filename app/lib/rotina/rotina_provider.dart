import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../compras/compras_provider.dart';
import '../erros/erro_app.dart';
import '../estoque/estoque_provider.dart';
import '../infraestrutura/infraestrutura_provider.dart';
import '../pendencias/pendencias_provider.dart';
import '../projecao/projecao_provider.dart';
import '../sessao/sessao_provider.dart';
import '../turmas/turmas_provider.dart';
import 'rotina.dart';
import 'rotina_repositorio.dart';

/// Repositório da rotina sob demanda — sobrescrito nos widget tests.
final rotinaRepositorioProvider = Provider<RotinaRepositorio>(
  (ref) => RotinaRepositorioSupabase(ref.watch(clienteSupabaseProvider)),
);

/// Executa a rotina da unidade e, quando ela rodou, recarrega o que ela
/// escreve: projeção e seu carimbo (`versaoEstoque` alimenta o "calculada em"
/// de Compras), pedido sugerido, pendências, capacidades e REP (turmas) e o
/// estado dos PCs (infraestrutura).
///
/// ⚠️ Com [ResultadoRotina.jaEmExecucao] nada é recarregado: a outra execução
/// ainda não terminou, e recarregar agora mostraria o estado de antes dela.
Future<ResultadoRotina> recalcularAgora(WidgetRef ref) async {
  final ResultadoRotina resultado;
  try {
    resultado = await ref.read(rotinaRepositorioProvider).executarAgora();
  } catch (erro) {
    throw traduzirErro(erro);
  }
  if (resultado == ResultadoRotina.executada) {
    ref.read(versaoProjecaoProvider.notifier).incrementar();
    ref.read(versaoComprasProvider.notifier).incrementar();
    ref.read(versaoEstoqueProvider.notifier).incrementar();
    ref.read(versaoPendenciasProvider.notifier).incrementar();
    ref.read(versaoTurmasProvider.notifier).incrementar();
    ref.read(versaoInfraestruturaProvider.notifier).incrementar();
  }
  return resultado;
}
