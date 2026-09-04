import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/pendencias/pendencias_provider.dart';
import 'package:gestao_im360/rotas/rotas.dart';
import 'package:gestao_im360/sessao/sessao_provider.dart';
import 'package:gestao_im360/theme/dimensoes.dart';
import 'package:gestao_im360/widgets/shell_im360.dart';

import 'apoio/app_de_teste.dart';
import 'apoio/pendencias_falso.dart';

/// Card 2.8 §9.1: `faixaDe(largura)` devolve menu/trilho/barra inferior nos
/// limites 600 e 1024. A troca de linhas por cartões da `TabelaIm360` está em
/// `tabela_im360_test.dart` (card 4.4, que criou o componente).
void main() {
  group('faixaDe', () {
    test(
      'os limites são fechados embaixo — 600 já é tablet, 1024 já é desktop',
      () {
        expect(faixaDe(599.9), Faixa.mobile);
        expect(faixaDe(Dim.bpTablet), Faixa.tablet);
        expect(faixaDe(1023.9), Faixa.tablet);
        expect(faixaDe(Dim.bpDesktop), Faixa.desktop);
      },
    );

    test('larguras típicas caem na faixa certa', () {
      expect(faixaDe(390), Faixa.mobile); // celular do monitor
      expect(faixaDe(820), Faixa.tablet);
      expect(faixaDe(1440), Faixa.desktop); // balcão da secretaria
      expect(faixaDe(3440), Faixa.desktop); // ultrawide
    });
  });

  group('o shell escolhe a navegação pela largura disponível', () {
    const permissoesDirecao = {
      'unidades.ler',
      'alunos.ler',
      'materiais.ler',
      'turmas.ler',
      'salas.ler',
      'professores.ler',
      'estoque.ler',
      'compras.ler',
      'certificados.ler',
      'pendencias.ler',
      'admin.ler',
    };

    Future<void> montar(WidgetTester tester, Size tamanho) async {
      tester.view.physicalSize = tamanho;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // O shell passou a observar o contador de pendências (card 5.8):
            // sem o repositório injetado ele iria ao `Supabase.instance`.
            pendenciasRepositorioProvider.overrideWithValue(
              PendenciasFalso(pendencias: const []),
            ),
            permissoesProvider.overrideWithValue(permissoesDirecao),
            resumoUsuarioProvider.overrideWithValue(
              const ResumoUsuario(
                nome: 'Direção',
                unidade: 'Instituto Mix Charqueadas',
              ),
            ),
          ],
          child: appDeTeste(
            rotaInicial: rotasAplicacao.first.caminho,
            construtor: (filho) => ShellIm360(filho: filho),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('desktop: menu lateral, sem barra inferior', (tester) async {
      await montar(tester, const Size(1400, 900));
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.text('Dashboard'), findsWidgets);
    });

    testWidgets('tablet: trilho de ícones', (tester) async {
      await montar(tester, const Size(800, 900));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('mobile: barra inferior com Alunos primeiro e Mais no fim', (
      tester,
    ) async {
      await montar(tester, const Size(390, 800));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);

      final barra = tester.widget<NavigationBar>(find.byType(NavigationBar));
      final rotulos = barra.destinations
          .cast<NavigationDestination>()
          .map((d) => d.label)
          .toList();
      // A jornada do monitor primeiro (docs/wireframes.md §3.2).
      expect(rotulos, ['Alunos', 'Turmas', 'Pendências', 'Mais']);
    });
  });
}
