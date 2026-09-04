import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../pendencias/pendencias.dart';
import '../../pendencias/pendencias_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../widgets/confirmacao.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';
import '../../widgets/painel_detalhe.dart';
import '../../widgets/tabela_im360.dart';
import 'filtros_pendencias.dart';
import 'painel_pendencia.dart';
import 'severidade.dart';

/// Tela 11 — Pendências, a central (docs/wireframes.md §14), card 5.8.
///
/// A fonte é `v_pendencias_abertas` (card 5.5). A tela **não** decide o que é
/// pendência: quem abre e quem fecha sozinha é a rotina diária das 03:10, e o
/// fechamento humano é `fn_pendencia_resolver_id`, que exige
/// `pendencias.resolver`. Aqui há forma e orquestração.
///
/// **Fila de trabalho, não relatório** (card 2.6 decisão 3): cada tipo tem uma
/// ação primária que leva à tela onde o problema se resolve, e `REP_VIRADA` é
/// *executada* daqui — a virada é sugerida, nunca automática (card 2.5), e
/// escolher o bloco é justamente a parte que o `pg_cron` não podia fazer.
///
/// ⚠️ **Divergência registrada com o §14.1**, que desenha `[Ver] [✓]` dentro da
/// linha: tocar a linha abre o [PainelPendencia], e as ações moram lá. Duas
/// razões, e a segunda é a que decide: numa fila de trabalho um `[✓]` na linha
/// deixa resolver sem ler **por que** a pendência existe; e o painel é o único
/// lugar onde cabem os números do `REP_VIRADA` — "3 aulas em aberto, prazo até
/// 12/10, cabem 2" —, que são o que torna a sugestão acionável (card 5.3). É o
/// mesmo desenho do painel do bloco (5.7) e do detalhe da sala (4.5).
class TelaPendencias extends ConsumerWidget {
  const TelaPendencias({super.key});

  Future<void> _abrir(BuildContext context, Pendencia pendencia) async {
    final resultado = await mostrarFormulario<String>(
      context,
      largura: larguraDetalhe,
      construtor: (_) => PainelPendencia(pendenciaId: pendencia.id),
    );
    if (resultado == null || !context.mounted) return;
    final texto = switch (resultado) {
      'RESOLVIDA' => 'Pendência resolvida.',
      'IGNORADA' => 'Pendência ignorada — ela volta enquanto a condição valer.',
      'virada' => 'Virada executada.',
      _ => null,
    };
    if (texto != null) confirmarEfemero(context, texto);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendencias = ref.watch(pendenciasProvider);
    final filtro = ref.watch(filtroPendenciasProvider);
    final todas = pendencias.value ?? const <Pendencia>[];
    final haPendencia = todas.isNotEmpty;

    // Os tipos do menu saem da lista com todo filtro aplicado MENOS o de tipo —
    // senão escolher um tipo esvaziaria o próprio menu.
    final tiposPresentes =
        filtrarPendencias(
          todas,
          filtro.copiar(tipo: () => null),
        ).map((p) => p.tipo).toSet().toList()..sort(
          (a, b) => rotuloTipoPendencia(a).compareTo(rotuloTipoPendencia(b)),
        );

    return TabelaIm360<Pendencia>(
      filtros: FiltrosPendencias(tiposPresentes: tiposPresentes),
      filtrosAtivos: filtro.ativos,
      colunas: [
        ColunaIm360(
          titulo: 'Sev.',
          texto: (p) => rotuloSeveridade(p.severidade),
          celula: (p) => Severidade(p.severidade),
          flex: 1,
          larguraMin: 90,
        ),
        ColunaIm360(
          titulo: 'Pendência',
          texto: (p) => rotuloTipoPendencia(p.tipo),
          flex: 2,
          larguraMin: 180,
        ),
        // A descrição carrega os NÚMEROS do dia (card 5.5 (b)) — é o que
        // distingue "este bloco estourou" de "10 alunos para capacidade de 9".
        // Por isso ela é coluna da lista, e não só do detalhe.
        ColunaIm360(
          titulo: 'Descrição',
          texto: (p) => p.descricao,
          flex: 4,
          prioridade: 2,
          larguraMin: 260,
        ),
        ColunaIm360(
          titulo: 'Referência',
          texto: (p) => p.referencia,
          flex: 2,
          prioridade: 3,
          larguraMin: 170,
        ),
        ColunaIm360(
          titulo: 'Aberta',
          texto: (p) => rotuloIdade(p.diasAberta),
          flex: 1,
          larguraMin: 110,
        ),
      ],
      linhas: pendencias.whenData((lista) => filtrarPendencias(lista, filtro)),
      cartao: (p) => CartaoIm360(
        titulo: rotuloTipoPendencia(p.tipo),
        subtitulo: p.descricao,
        apoio: '${p.referencia} · ${rotuloIdade(p.diasAberta)}',
        badge: Severidade(p.severidade),
      ),
      estadoVazio: haPendencia
          ? EstadoVazio(
              mensagem: vazioPendenciasFiltro,
              icone: Icons.filter_alt_off_outlined,
              rotuloAcao: 'Limpar filtros',
              aoAgir: ref.read(filtroPendenciasProvider.notifier).limpar,
            )
          : const EstadoVazio(
              mensagem: vazioPendencias,
              icone: Icons.check_circle_outline,
            ),
      aoTocarLinha: (p) => _abrir(context, p),
      aoRepetir: () => recarregarPendencias(ref),
    );
  }
}

/// Estado vazio da tela — os textos são os do card 2.7 (design-system §7.2).
///
/// A central vazia é o único estado vazio do sistema que é **boa notícia**, e o
/// texto diz isso: sem ele, uma tela sem linhas seria indistinguível de uma
/// rotina que não rodou — e é justamente essa confusão que a pendência
/// `ROTINA_FALHOU` existe para desfazer (card 5.5 (d)).
const vazioPendencias = 'Nenhuma pendência aberta. 🎉';
const vazioPendenciasFiltro = 'Nenhuma pendência com esses filtros.';

/// Uma linha de rótulo e valor do painel de detalhe — o par que a central
/// repete em "Descrição", "Referência" e "Aberta desde".
class LinhaDetalhe extends StatelessWidget {
  const LinhaDetalhe({super.key, required this.rotulo, required this.valor});

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Dim.e8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rotulo,
            style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
          ),
          Text(valor, style: Tipografia.corpo),
        ],
      ),
    );
  }
}
