import 'package:flutter/material.dart';

import '../theme/dimensoes.dart';
import '../theme/tipografia.dart';

/// A barra de ocupação das duas grades semanais — Turmas (tela 4) e o
/// Dashboard (tela 2) —, igual nas duas (card 9.2,61).
///
/// ⚠️ Existe porque as duas grades escreviam o MESMO bloco como fração com
/// leituras opostas: `0/10` em Turmas (alocados/capacidade — vazio) e `10/10`
/// no Dashboard (vagas/capacidade — dez livres). `n/m` se lê universalmente
/// como "ocupados de total", e a legenda do Dashboard ficava abaixo da grade,
/// onde ninguém lê antes de decidir. Nenhum teste pegava: os números estavam
/// certos, a leitura é que se invertia. Agora nenhuma célula escreve fração —
/// o texto diz a palavra (`9 de 10`, `10 livres`, `lotado`) — e a barra mostra
/// o mesmo desenho nas duas telas: cheia é cheia, dos dois lados.
///
/// [fracao] é a parte OCUPADA, de 0 a 1. Acima da capacidade a barra fica
/// cheia e na cor de erro; o número de quantos passaram é do texto, não dela.
class BarraOcupacao extends StatelessWidget {
  const BarraOcupacao({
    super.key,
    required this.fracao,
    this.acimaCapacidade = false,
  });

  final double fracao;
  final bool acimaCapacidade;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final valor = acimaCapacidade ? 1.0 : fracao.clamp(0.0, 1.0);
    // Decorativa para o leitor de tela: o `Semantics` da célula já diz os
    // números por extenso, e "barra de progresso 90 por cento" repetiria o
    // mesmo fato com outra unidade.
    // ⚠️ `Align` + `FractionallySizedBox`, e NUNCA dentro de um
    // `Stack(fit: StackFit.expand)`: o `expand` força constraints justas no
    // filho, o `widthFactor` é ignorado e a barra sai CHEIA para todo bloco —
    // "10 livres" com a barra de lotado. Passou em todos os widget tests e só
    // apareceu no navegador (card 9.2,61); `barra_ocupacao_test` mede a
    // largura desde então.
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: SizedBox(
          height: 4,
          // `outline`, e não `outlineVariant`: o tema NÃO declara
          // `outlineVariant`, e o Flutter devolve uma cor quase preta no lugar
          // — o trilho vazio saía da cor do preenchido (visto no navegador,
          // card 9.2,61; a mesma família do `tertiary` do card 8.1,5).
          child: ColoredBox(
            color: cores.outline,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                key: chavePreenchimentoOcupacao,
                widthFactor: valor,
                heightFactor: 1,
                child: ColoredBox(
                  color: acimaCapacidade ? cores.error : cores.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `⊘ lotado` — ícone **e** texto, nas duas grades (card 9.2,61).
///
/// Antes lotado era só o peso da fonte, que no print mal se distingue do peso
/// normal. Continua **neutro** (cor de apoio, não de alerta): lotado é o
/// sistema funcionando, e cor de alerta gastaria o alerta que a turma ACIMA da
/// capacidade precisa (design-system §6).
class MarcaLotado extends StatelessWidget {
  const MarcaLotado({super.key, this.cor});

  /// Nulo = `onSurface`. A célula de erro passa `onErrorContainer`.
  final Color? cor;

  @override
  Widget build(BuildContext context) {
    final c = cor ?? Theme.of(context).colorScheme.onSurface;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.block, size: 14, color: c),
        const SizedBox(width: Dim.e4),
        Text(
          rotuloLotado,
          style: Tipografia.rotulo.copyWith(
            color: c,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// A parte preenchida da [BarraOcupacao] — é por ela que o teste mede a largura.
const chavePreenchimentoOcupacao = Key('barra-ocupacao-preenchida');

/// Texto único, para as duas grades, as legendas e os testes.
const rotuloLotado = 'lotado';
