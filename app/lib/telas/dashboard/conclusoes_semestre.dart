import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dashboard/dashboard.dart';
import '../../dashboard/dashboard_provider.dart';
import '../../theme/cores.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../widgets/card_dashboard.dart';
import '../../widgets/estados.dart';

/// A região "Conclusões por semestre (por método)" do wireframe §5 — card 8.7,
/// consumidora de `v_dashboard_conclusoes_semestre`.
///
/// ⚠️ **As vencidas aparecem, sempre.** Previsão no passado não é descartada:
/// fica no semestre dela e vai ao lado do total (wireframes §5 — "mostrar
/// `qtd_vencidas` junto, nunca escondê-las"). É o mesmo fato que a rotina da
/// madrugada transforma em pendência de previsão vencida, visto pelo lado do
/// planejamento — e some-o e a conferência contra a planilha não fecha, porque
/// a migração vai trazer previsões de 2023 e de 2050.
///
/// ⚠️ **O "sem previsão" fecha a conta.** Esta região só enxerga quem tem data
/// informada; sem o número de quem não tem, a soma dos semestres não bate com o
/// total de ativos do cartão logo acima e ninguém sabe se faltou aluno ou
/// faltou data (docs/views-leitura.md §8.1). O dashboard mostra a conta
/// fechando, não números soltos.
class ConclusoesSemestre extends ConsumerWidget {
  const ConclusoesSemestre({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cores = Theme.of(context).colorScheme;
    final conclusoes = ref.watch(conclusoesPrevistasProvider);
    final semestres = ref.watch(semestresConclusaoProvider);
    final alunos = ref.watch(alunosPorMetodoProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tituloConclusoes, style: Tipografia.subtitulo),
        const SizedBox(height: Dim.e4),
        // `hasError` antes de `hasValue` (design-system §5.6).
        if (conclusoes.hasError)
          EstadoErro(
            mensagem: erroConclusoes,
            aoRepetir: () => ref.invalidate(conclusoesPrevistasProvider),
          )
        else if (!conclusoes.hasValue)
          const EstadoCarregando(linhas: 2)
        else if (semestres.isEmpty)
          Text(
            vazioConclusoes,
            style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
          )
        else
          _Cartoes(semestres: semestres),
        // ⚠️ A linha só aparece com a leitura dos alunos **de fato pronta**: em
        // `loading` ou em `error`, `0 sem previsão` seria um número que ninguém
        // mediu dizendo que está tudo preenchido — o defeito B1 do card 5.11
        // (`AsyncValue` que decide texto precisa dos três estados). Quando a
        // leitura falhou, quem diz isso é a região de cima, com a saída de
        // "Tentar de novo".
        if (alunos.hasValue && !alunos.hasError) ...[
          const SizedBox(height: Dim.e8),
          Text(
            textoSemPrevisao(totalSemPrevisao(alunos.requireValue)),
            style: Tipografia.numero(Tipografia.apoio)
                .copyWith(color: cores.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

const tituloConclusoes = 'Conclusões previstas por semestre';

/// Substitui os números quando a leitura falha — nunca um zero.
const erroConclusoes =
    'Não foi possível ler as conclusões previstas agora. Tente de novo.';

/// Nenhum aluno em curso com data informada. A previsão de conclusão é
/// **informada à mão** na ficha do aluno (não há regra que a calcule), e é isso
/// que a frase precisa dizer — senão parece que o sistema deixou de calcular.
const vazioConclusoes =
    'Nenhum aluno em curso com previsão de conclusão informada. A previsão é '
    'preenchida na ficha do aluno.';

/// A linha que fecha a conta com o total de ativos.
String textoSemPrevisao(int quantos) => quantos == 0
    ? 'Todos os alunos em curso têm previsão de conclusão informada.'
    : '$quantos ${quantos == 1 ? 'aluno em curso ainda não tem' : 'alunos em '
                    'curso ainda não têm'} previsão de conclusão informada e não '
          'entram nesta conta.';

class _Cartoes extends StatelessWidget {
  const _Cartoes({required this.semestres});

  final List<SemestreConclusoes> semestres;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, restricoes) {
      final mobile = faixaDe(restricoes.maxWidth) == Faixa.mobile;
      final cartoes = [
        for (final semestre in semestres)
          _CartaoSemestre(
            semestre: semestre,
            largura: mobile ? null : larguraCardDashboard,
          ),
      ];

      return mobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final cartao in cartoes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Dim.e12),
                    child: cartao,
                  ),
              ],
            )
          : Wrap(spacing: Dim.e12, runSpacing: Dim.e12, children: cartoes);
    },
  );
}

class _CartaoSemestre extends StatelessWidget {
  const _CartaoSemestre({required this.semestre, this.largura});

  final SemestreConclusoes semestre;
  final double? largura;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    // Vencida é **âmbar**, não vermelho: a previsão passou e o aluno continua
    // em curso — é atenção, não dado inconsistente. O vermelho desta tela está
    // reservado à turma acima da capacidade (design-system §6).
    final atencao = tema.brightness == Brightness.dark
        ? Cores.atencaoEscuro
        : Cores.atencao;

    return CardDashboard(
      largura: largura,
      semantica: descricaoSemestre(semestre),
      filho: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            semestre.rotulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Tipografia.numero(Tipografia.badge)
                .copyWith(color: cores.onSurfaceVariant),
          ),
          const SizedBox(height: Dim.e4),
          Text(
            '${semestre.qtdAlunos}',
            style: Tipografia.numero(Tipografia.titulo),
          ),
          Text(
            semestre.qtdAlunos == 1 ? 'aluno' : 'alunos',
            style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
          ),
          if (semestre.temVencidas) ...[
            const SizedBox(height: Dim.e4),
            // Cor nunca é portador único (design-system §8.2): ícone + texto.
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.event_busy_outlined, size: 14, color: atencao),
                const SizedBox(width: Dim.e4),
                Flexible(
                  child: Text(
                    semestre.vencidasTexto,
                    style: Tipografia.numero(Tipografia.apoio)
                        .copyWith(color: atencao),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: Dim.e8),
          // A quebra por método é o que cumpre o "(por método)" do título:
          // somar sem mostrá-la faria a direção planejar a compra de um método
          // olhando o número de outro.
          Text(
            semestre.resumoMetodos,
            style: Tipografia.numero(Tipografia.apoio),
          ),
        ],
      ),
    );
  }
}
