import 'package:flutter/material.dart';

import '../../dashboard/dashboard.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../util/datas.dart';
import '../../widgets/matriz_semanal.dart';

/// A grade de vagas do wireframe §5: dia × horário, cada célula com **vagas
/// livres / capacidade** — a leitura que responde "onde ainda cabe alguém".
///
/// ⚠️ É a leitura **oposta** à da célula da tela de Turmas (card 5.6), que
/// mostra alocados/capacidade. As duas saem da mesma view e nunca divergem em
/// número; o que pode divergir é quem lê `2/10`. Por isso a legenda é parte da
/// grade e não um enfeite abaixo dela, e cada célula carrega um `Semantics` que
/// diz "2 vagas livres de 10" por extenso.
///
/// A forma — matriz no desktop e no tablet, **abas Seg–Sáb no mobile** — é a
/// [MatrizSemanal], a mesma da tela de Turmas. As duas telas usavam formas
/// diferentes no celular (aqui, lista vertical por dia); Irineu decidiu por
/// abas nas duas em 04/09/2026, e o design-system §6 já mandava isso para as
/// telas 2 e 4 — a divergência estava no wireframe §5, corrigido.
class GradeVagas extends StatelessWidget {
  const GradeVagas({super.key, required this.grade, this.aoTocarCelula});

  final GradeSemana grade;

  /// Nulo deixa a célula sem toque. Toda célula/número do dashboard é atalho
  /// (wireframes §3.3), e o destino daqui é a grade de Turmas — mas quem não
  /// pode abri-la não recebe um atalho que leva a "Sem acesso" (card 5.8 (1)).
  final void Function(int dia, String hora)? aoTocarCelula;

  @override
  Widget build(BuildContext context) => MatrizSemanal(
    dias: grade.dias,
    horas: grade.horas,
    dataDe: grade.dataDe,
    temConteudo: (dia, hora) => grade.em(dia, hora).isNotEmpty,
    // Abre no dia de hoje: quem consulta vaga na quinta quer a quinta.
    diaInicial: hojeSaoPaulo().weekday,
    padding: EdgeInsets.zero,
    // A caixinha de vagas é baixa; a grade de Turmas desenha cartões.
    alturaLinhaMobile: 64,
    celula: (dia, hora) => _CelulaVagas(
      dia: dia,
      hora: hora,
      vagas: vagasDa(grade.em(dia, hora)),
      aoTocar: aoTocarCelula,
    ),
    legenda: const LegendaVagas(),
  );
}

/// `2/10` = duas vagas livres de dez lugares. A cor nunca é o único portador do
/// significado (card 1.9): acima da capacidade tem o seu ícone e o seu texto na
/// legenda; **lotada não tem ícone nenhum**, e isso é a regra do §6 — lotado é
/// fato, não problema.
class _CelulaVagas extends StatelessWidget {
  const _CelulaVagas({
    required this.dia,
    required this.hora,
    required this.vagas,
    this.aoTocar,
  });

  final int dia;
  final String hora;
  final VagasNaCelula vagas;
  final void Function(int dia, String hora)? aoTocar;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;

    if (vagas.semBloco) {
      // Traço e não "·": o ponto médio é decoração e o leitor de tela o
      // anuncia como pontuação. E a célula vazia também é anunciada — antes
      // ficava fora do `Semantics` e sumia da leitura (§8.5).
      return Semantics(
        label: descricaoCelula(dia, hora, vagas),
        excludeSemantics: true,
        child: SizedBox(
          height: Dim.alturaBotao,
          child: Center(
            child: Text(
              '—',
              style: Tipografia.apoio.copyWith(color: cores.outlineVariant),
            ),
          ),
        ),
      );
    }

    final corTexto = vagas.acimaCapacidade
        ? cores.onErrorContainer
        : cores.onSurface;

    final conteudo = Container(
      // Alvo de toque do §8.4: a célula é atalho para a grade de Turmas, e 32
      // px ficavam abaixo do mínimo do desktop, quanto mais do celular.
      height: Dim.alturaBotao,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(
          color: vagas.acimaCapacidade ? cores.error : cores.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(Dim.raio),
        color: vagas.acimaCapacidade ? cores.errorContainer : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            vagas.texto,
            style: Tipografia.numero(Tipografia.rotulo).copyWith(
              color: corTexto,
              // Lotada é **peso**, não cor e não ícone (design-system §6).
              fontWeight: vagas.lotada ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
          if (vagas.acimaCapacidade) ...[
            const SizedBox(width: Dim.e4),
            Icon(Icons.warning_amber_rounded, size: 14, color: cores.error),
          ],
          if (vagas.salas > 1) ...[
            const SizedBox(width: Dim.e4),
            Text(
              '${vagas.salas}×',
              style: Tipografia.apoio.copyWith(
                color: vagas.acimaCapacidade
                    ? cores.onErrorContainer
                    : cores.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );

    return Semantics(
      button: aoTocar != null,
      label: descricaoCelula(dia, hora, vagas),
      excludeSemantics: true,
      child: aoTocar == null
          ? conteudo
          : InkWell(
              onTap: () => aoTocar!(dia, hora),
              borderRadius: BorderRadius.circular(Dim.raio),
              child: conteudo,
            ),
    );
  }
}

/// A legenda existe porque `2/10` tem duas leituras possíveis dentro deste mesmo
/// sistema, e a grade de Turmas usa a outra.
class LegendaVagas extends StatelessWidget {
  const LegendaVagas({super.key});

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final estilo = Tipografia.apoio.copyWith(color: cores.onSurfaceVariant);

    return Wrap(
      spacing: Dim.e16,
      runSpacing: Dim.e4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(rotuloLegendaVagas, style: estilo),
        Text(
          'bloco lotado',
          style: estilo.copyWith(fontWeight: FontWeight.w600),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, size: 14, color: cores.error),
            const SizedBox(width: Dim.e4),
            Text('acima da capacidade', style: estilo),
          ],
        ),
        Text('2× = duas salas no mesmo horário', style: estilo),
      ],
    );
  }
}

/// Texto único, para a tela e o teste lerem a mesma frase.
const rotuloLegendaVagas = 'Célula: vagas livres / capacidade';
