import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../infraestrutura/infraestrutura.dart';
import '../../infraestrutura/infraestrutura_provider.dart';
import '../../theme/tipografia.dart';
import '../../util/async_valor.dart';
import '../../widgets/estados.dart';
import '../../widgets/tabela_im360.dart';
import 'filtros_salas.dart';

/// Estado vazio da aba (design-system §7.2): o motivo, não só a ausência. Sem
/// registro nenhum a frase diz onde se registra — a ação mora na linha do PC,
/// não aqui; com filtro, o vazio é do filtro e se desfaz por ele.
const vazioManutencoes =
    'Nenhuma manutenção registrada. Registre pela linha do PC, na aba '
    'Salas e PCs.';
const vazioManutencoesFiltro = 'Nenhuma manutenção com esses filtros.';

/// A aba "Manutenções" da tela 10 (card 9.2,78): o histórico de manutenções
/// dos PCs, da mais recente para a mais antiga — o que o monitor procurou na
/// rodada de 30/09/2026 e não achou ("não sei se não existe ou se não tenho
/// permissão para ver"). Não era permissão: o banco guardava tudo e nenhuma
/// tela listava as encerradas.
///
/// Só leitura. Registrar e encerrar continuam na linha do PC (aba Salas e
/// PCs), onde a ação contextual decide entre "Manutenção" e "Encerrar".
///
/// ⚠️ **Onde ela mora é decisão reversível da sessão**, não do monitor (que
/// pediu "uma tela"): aba dentro de Salas e PCs, no molde de Materiais e
/// estoque e de Compras, em vez de um 14º item no menu. Para virar tela
/// própria: uma `Rota` nova em `rotas/rotas.dart` (`exige: {'salas.ler'}` —
/// é tudo o que esta aba lê), a entrada dela no mapa de `rotas/roteador.dart`
/// devolvendo `const AbaManutencoes()`, e tirá-la do `TabBar` de `TelaSalas`.
/// A aba não depende de nada da tela que a hospeda.
class AbaManutencoes extends ConsumerWidget {
  const AbaManutencoes({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historico = ref.watch(historicoManutencoesProvider);
    final pcsAsync = ref.watch(pcsProvider);
    final salasAsync = ref.watch(salasProvider);
    final filtro = ref.watch(filtroManutencoesProvider);
    final haRegistro = historico.value?.isNotEmpty ?? false;
    final hoje = DateTime.now();

    final pcs = {for (final pc in pcsAsync.value ?? const <Pc>[]) pc.id: pc};
    final salas = {
      for (final s in salasAsync.value ?? const <Sala>[]) s.id: s.nome,
    };

    // Os três estados da leitura dos PCs (card 9.2,62): sem eles a máquina
    // sairia em branco enquanto carrega e para sempre se a leitura falhasse —
    // uma manutenção sem dizer de que máquina.
    String doPc(String Function() texto, AsyncValue<Object?> leitura) =>
        leitura.hasError
        ? textoNaoLido
        : !leitura.hasValue
        ? '…'
        : texto();
    String maquina(PcManutencao m) =>
        doPc(() => pcs[m.pcId]?.identificador ?? '?', pcsAsync);
    String sala(PcManutencao m) => doPc(
      () => salas[pcs[m.pcId]?.salaId] ?? '?',
      pcsAsync.hasError ? pcsAsync : salasAsync,
    );
    String periodo(PcManutencao m) =>
        formatarPeriodo(m.dataInicio, m.dataFim, hoje);
    String autor(PcManutencao m) => m.criadoPorNome ?? semAutor;

    return TabelaIm360<PcManutencao>(
      filtros: const FiltrosManutencoes(),
      filtrosAtivos: filtro.ativos,
      colunas: [
        ColunaIm360(
          titulo: 'Máquina',
          texto: maquina,
          flex: 1,
          larguraMin: 110,
        ),
        ColunaIm360(
          titulo: 'Sala',
          texto: sala,
          prioridade: 3,
          larguraMin: 140,
        ),
        ColunaIm360(
          titulo: 'Tipo',
          texto: (m) => rotuloTipoManutencao(m.tipo),
          prioridade: 2,
          flex: 1,
          larguraMin: 120,
        ),
        // Data é número: tabular, mas alinhada à esquerda como o texto que
        // ela também é ("desde 30/09").
        ColunaIm360(
          titulo: 'Período',
          texto: periodo,
          larguraMin: 150,
          celula: (m) => Text(
            periodo(m),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Tipografia.numero(Tipografia.corpoTabela),
          ),
        ),
        ColunaIm360(
          titulo: 'Registrada por',
          texto: autor,
          prioridade: 2,
          larguraMin: 150,
        ),
        ColunaIm360(
          titulo: 'O que foi feito',
          texto: (m) => m.descricao ?? '—',
          flex: 4,
          larguraMin: 200,
        ),
      ],
      linhas: historico.derivar(
        (lista) => ordenarHistorico(filtrarManutencoes(lista, filtro)),
      ),
      cartao: (m) => CartaoIm360(
        titulo: maquina(m),
        subtitulo: [
          rotuloTipoManutencao(m.tipo),
          if (salas.length > 1) sala(m),
        ].join(' · '),
        destaque: periodo(m),
        informacao: m.descricao,
        apoio: m.criadoPorNome == null
            ? null
            : 'Registrada por ${m.criadoPorNome}',
      ),
      estadoVazio: haRegistro
          ? EstadoVazio(
              mensagem: vazioManutencoesFiltro,
              icone: Icons.filter_alt_off_outlined,
              rotuloAcao: 'Limpar filtros',
              aoAgir: ref.read(filtroManutencoesProvider.notifier).limpar,
            )
          : const EstadoVazio(
              mensagem: vazioManutencoes,
              icone: Icons.build_outlined,
            ),
      aoRepetir: ref.read(versaoInfraestruturaProvider.notifier).incrementar,
    );
  }
}
