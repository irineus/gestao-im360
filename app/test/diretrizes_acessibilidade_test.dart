import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/alunos/alunos_provider.dart';
import 'package:gestao_im360/catalogo/catalogo_provider.dart';
import 'package:gestao_im360/config/politica_retry.dart';
import 'package:gestao_im360/dashboard/dashboard_provider.dart';
import 'package:gestao_im360/infraestrutura/infraestrutura_provider.dart';
import 'package:gestao_im360/pendencias/pendencias_provider.dart';
import 'package:gestao_im360/sessao/sessao_provider.dart';
import 'package:gestao_im360/telas/alunos/tela_alunos.dart';
import 'package:gestao_im360/telas/dashboard/tela_dashboard.dart';
import 'package:gestao_im360/theme/dimensoes.dart';
import 'package:gestao_im360/theme/tema.dart';
import 'package:gestao_im360/turmas/modular_provider.dart';
import 'package:gestao_im360/turmas/turmas_provider.dart';
import 'package:go_router/go_router.dart';

import 'apoio/alunos_falso.dart';
import 'apoio/carregar.dart';
import 'apoio/catalogo_falso.dart';
import 'apoio/dashboard_falso.dart';
import 'apoio/infraestrutura_falso.dart';
import 'apoio/modular_falso.dart';
import 'apoio/pendencias_falso.dart';
import 'apoio/turmas_falso.dart';

/// Contraste e alvo mínimo medidos pela máquina (card 9.2,72).
///
/// A estratégia de testes §18.2 deixou "um teste automático de contraste e de
/// alvo mínimo" fora da v1: o card 2.7 conferiu contraste par a par no papel. O
/// 9.2,72 avaliou e trouxe para dentro — e a PRIMEIRA execução achou um
/// defeito real, recém-introduzido: as linhas zeradas dos cartões do Dashboard
/// (card 9.2,71) com transparência 0,75 tinham contraste 2,96, abaixo dos 4,5
/// do WCAG AA. Conferência no papel não pega o que alguém muda depois.
///
/// As três diretrizes do próprio Flutter, sobre a árvore de semântica:
///   • `iOSTapTargetGuideline` — alvo tocável de pelo menos 44 × 44 px, o
///     `Dim.alvoMobile` do design-system §8.4 (e o AAA do WCAG 2.5.5). A de
///     Android pede 48 dp: fica de fora de propósito, ver design-system §11;
///   • `labeledTapTargetGuideline` — todo alvo tocável tem rótulo;
///   • `textContrastGuideline` — texto com contraste AA sobre o fundo real.
///
/// Duas telas, as de mais tráfego — Dashboard e lista de Alunos —, em 390 px e
/// desktop. Tela nova entra aqui com uma linha na lista.
void main() {
  const permissoes = {
    'alunos.ler',
    'materiais.ler',
    'turmas.ler',
    'salas.ler',
    'pendencias.ler',
    'professores.ler',
  };

  final telas = <(String, Widget, String)>[
    ('Dashboard', const TelaDashboard(), '/'),
    ('Alunos', const TelaAlunos(), '/alunos'),
  ];

  for (final (nomeTela, tela, rota) in telas) {
    for (final (nomeTamanho, tamanho) in [
      ('390 px', const Size(390, 800)),
      ('desktop', const Size(1400, 900)),
    ]) {
      testWidgets('$nomeTela, $nomeTamanho: contraste AA, alvo de 44 px e '
          'rótulo em todo alvo', (tester) async {
        final semantica = tester.ensureSemantics();
        tester.view.physicalSize = tamanho;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            retry: semRetryAutomatico,
            overrides: [
              dashboardRepositorioProvider.overrideWithValue(DashboardFalso()),
              pendenciasRepositorioProvider.overrideWithValue(
                PendenciasFalso.fixture(),
              ),
              modularRepositorioProvider.overrideWithValue(
                ModularFalso.fixture(),
              ),
              alunosRepositorioProvider.overrideWithValue(
                AlunosFalso.fixture(),
              ),
              catalogoRepositorioProvider.overrideWithValue(
                CatalogoFalso.fixture(),
              ),
              turmasRepositorioProvider.overrideWithValue(
                TurmasFalso.fixture(),
              ),
              infraestruturaRepositorioProvider.overrideWithValue(
                InfraestruturaFalso.fixture(),
              ),
              permissoesProvider.overrideWithValue(permissoes),
              unidadeAtualProvider.overrideWithValue('unidade-teste'),
            ],
            // O tema da FAIXA, como o `main.dart` escolhe: densidade compacta
            // só no desktop. Com o tema compacto em 390 px o teste mediria um
            // app que ninguém usa.
            child: MaterialApp.router(
              theme: temaClaro(
                compacto: faixaDe(tamanho.width) != Faixa.mobile,
              ),
              routerConfig: GoRouter(
                initialLocation: rota,
                routes: [
                  GoRoute(
                    path: rota,
                    builder: (_, _) => Scaffold(body: tela),
                  ),
                ],
              ),
            ),
          ),
        );
        await carregar(tester);

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        // 44 px no celular (§8.4); no desktop, os 40 px de `Dim.alturaBotao`,
        // que é o alvo de ponteiro do próprio design-system.
        await expectLater(
          tester,
          meetsGuideline(
            tamanho.width < 600
                ? iOSTapTargetGuideline
                : const MinimumTapTargetGuideline(
                    size: Size(Dim.alturaBotao, Dim.alturaBotao),
                    link: 'docs/design-system.md §8.4',
                  ),
          ),
        );
        semantica.dispose();
      });
    }
  }
}
