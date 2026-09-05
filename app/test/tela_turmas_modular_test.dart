import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/alunos/alunos_provider.dart';
import 'package:gestao_im360/catalogo/catalogo_provider.dart';
import 'package:gestao_im360/config/politica_retry.dart';
import 'package:gestao_im360/erros/erro_app.dart';
import 'package:gestao_im360/infraestrutura/infraestrutura_provider.dart';
import 'package:gestao_im360/sessao/sessao_provider.dart';
import 'package:gestao_im360/telas/turmas/tela_turmas_modular.dart';
import 'package:gestao_im360/theme/tema.dart';
import 'package:gestao_im360/turmas/modular.dart';
import 'package:gestao_im360/turmas/modular_provider.dart';
import 'package:gestao_im360/widgets/formulario.dart';

import 'apoio/alunos_falso.dart';
import 'apoio/carregar.dart';
import 'apoio/catalogo_falso.dart';
import 'apoio/infraestrutura_falso.dart';
import 'apoio/modular_falso.dart';

/// A obrigação de teste de um card de **Tela** (card 2.8 §13): ocultação por
/// permissão e estado vazio com o texto do card 2.7 — a guarda de rota já está
/// tabelada em `guardas_rota_test.dart`. Mais o que esta tela tem de próprio, e
/// que nenhum catálogo enxerga:
///
///   • **os DOIS sentidos de "sem módulo corrente"** aparecem como avisos
///     diferentes, e o `[Avançar módulo]` fica desabilitado **com motivo
///     diferente** em cada um. Uma tela que tratasse os dois igual mandaria quem
///     nunca montou o cronograma procurar o erro no lugar errado — é a mesma
///     distinção que `fn_turma_modular_avancar` faz entre `TURMA_SEM_CRONOGRAMA`
///     e `TURMA_SEM_MODULO_CORRENTE`;
///
///   • **sem `alunos.ler` a região de alunos DIZ o que falta**, em vez de listar
///     vazio. A rota da tela não pede `alunos.ler` e a view junta `aluno`
///     internamente: uma turma "sem aluno nenhum" com `1/15` ao lado é a redução
///     silenciosa do card 2.3 §3.4 na forma mais enganosa que ela tem;
///
///   • **turma acima da capacidade não é "lotada"**: o aviso é outro, e a saída
///     também.
void main() {
  // O conjunto mínimo da rota `turmas_modular` (docs/permissoes-matriz.md §6,
  // linha 5) e as ações de cima dele, na matriz inicial do card 2.4 §5.
  const leitura = {'turmas.ler', 'salas.ler', 'materiais.ler', 'alunos.ler'};
  const secretaria = {
    ...leitura,
    'turmas.criar',
    'turmas.editar',
    'turmas.excluir',
    'turmas.alocar',
  };

  Future<ModularFalso> montar(
    WidgetTester tester, {
    ModularFalso? repositorio,
    Set<String> permissoes = leitura,
    Size tamanho = const Size(1400, 1200),
    String? turmaId,
  }) async {
    final modular = repositorio ?? ModularFalso.fixture();
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: semRetryAutomatico,
        overrides: [
          modularRepositorioProvider.overrideWithValue(modular),
          catalogoRepositorioProvider.overrideWithValue(
            CatalogoFalso.fixture(),
          ),
          infraestruturaRepositorioProvider.overrideWithValue(
            InfraestruturaFalso.fixture(),
          ),
          alunosRepositorioProvider.overrideWithValue(AlunosFalso.fixture()),
          permissoesProvider.overrideWithValue(permissoes),
          unidadeAtualProvider.overrideWithValue('unidade-teste'),
        ],
        child: MaterialApp(
          theme: temaClaro(),
          home: Scaffold(body: TelaTurmasModular(turmaId: turmaId)),
        ),
      ),
    );
    await carregar(tester);
    return modular;
  }

  Future<void> abrir(WidgetTester tester, String nome) async {
    await tester.tap(find.text(nome));
    await carregar(tester);
  }

  /// Toca no que pode estar abaixo da dobra. A turma de 16 alunos abre um cartão
  /// de ~1500 px e joga as ações para fora da viewport — sem rolar, o `tap`
  /// avisa que o alvo não recebe o toque e o teste mede o nada.
  Future<void> tocar(WidgetTester tester, Finder alvo) async {
    await tester.ensureVisible(alvo);
    await carregar(tester);
    await tester.tap(alvo);
    await carregar(tester);
  }

  testWidgets('a lista mostra turma, curso, sala e lotação', (tester) async {
    await montar(tester);
    expect(find.text('Eletricista 2026.1'), findsOneWidget);
    expect(
      find.text('Eletricista Instalador · Sala Eletricista · 1/15'),
      findsOneWidget,
    );
    expect(find.text('Depilação · Sala Eletricista · 16/15'), findsOneWidget);
  });

  testWidgets('turma acima da capacidade é marcada, e não como "lotada"', (
    tester,
  ) async {
    await montar(tester);
    expect(find.text('acima da capacidade'), findsOneWidget);
    expect(
      find.text('lotada'),
      findsNothing,
      reason:
          'a turma de 16 em 15 não é uma turma cheia: a saída é remover alguém '
          'ou aumentar a capacidade, e chamá-la de "lotada" esconderia isso',
    );
  });

  testWidgets('módulo corrente vencido aparece marcado como atrasado', (
    tester,
  ) async {
    await montar(tester);
    expect(find.text('módulo atrasado'), findsOneWidget);
    // E a turma em dia NÃO é marcada — sem esta metade, um `modulo_atrasado`
    // sempre verdadeiro passaria.
    expect(find.textContaining('Módulo corrente: 2.'), findsOneWidget);
  });

  testWidgets(
    'os DOIS sentidos de "sem módulo corrente" dão avisos diferentes',
    (tester) async {
      await montar(tester, permissoes: secretaria);

      // (a) turma sem cronograma nenhum.
      await abrir(tester, 'Eletricista 2026.2');
      expect(find.text(avisoSemCronograma), findsOneWidget);
      expect(find.text(avisoTurmaTerminou), findsNothing);
      expect(find.text('Montar cronograma'), findsOneWidget);

      // (b) turma cujo cronograma acabou — o avanço chega ao fim.
      final modular = ModularFalso.fixture();
      await modular.avancar(
        turmaId: 't-cheia',
        dataConclusao: DateTime(2026, 9, 1),
      );
      await montar(tester, repositorio: modular, permissoes: secretaria);
      await abrir(tester, 'Depilação 2026.1');
      expect(find.text(avisoTurmaTerminou), findsOneWidget);
      expect(find.text(avisoSemCronograma), findsNothing);
    },
  );

  testWidgets('o botão de avançar fica desabilitado COM MOTIVO, e o motivo '
      'distingue os dois casos', (tester) async {
    await montar(tester, permissoes: secretaria);
    await abrir(tester, 'Eletricista 2026.2');

    final botao = find.widgetWithText(FilledButton, 'Avançar módulo');
    expect(botao, findsOneWidget, reason: 'visível, não escondido');
    expect(
      tester.widget<FilledButton>(botao).onPressed,
      isNull,
      reason:
          'sem estado o botão é desabilitado com o motivo (design-system '
          '§5.7), nunca removido: removê-lo ensinaria que a ação não existe',
    );
    // O motivo aponta para a saída que a própria tela oferece.
    expect(
      find.byTooltip('Monte o cronograma da turma antes de avançar o módulo.'),
      findsOneWidget,
    );
  });

  testWidgets('o cronograma lista os módulos na ordem, com estado e período', (
    tester,
  ) async {
    await montar(tester);
    await abrir(tester, 'Eletricista 2026.1');

    expect(find.text('1. Módulo 1 — Comandos elétricos'), findsOneWidget);
    expect(find.text('2. Módulo 2 — Instalações prediais'), findsOneWidget);
    expect(find.text('3. Módulo 3 — Projetos'), findsOneWidget);
    // Estado em TEXTO ao lado do ícone: cor e símbolo nunca são portadores
    // únicos (design-system §8.2).
    expect(find.text('12/06–10/08 · concluído'), findsOneWidget);
    expect(find.text('11/08–10/10 · em curso'), findsOneWidget);
    expect(find.text('$semDatasTexto · a fazer'), findsOneWidget);
  });

  testWidgets('turma com o cronograma completo não oferece acrescentar; a '
      'parcial oferece', (tester) async {
    await montar(tester, permissoes: secretaria);

    await abrir(tester, 'Eletricista 2026.1');
    expect(find.textContaining('Acrescentar'), findsNothing);
    expect(find.text('Montar cronograma'), findsNothing);

    // Fecha a primeira e abre a de cronograma parcial: só um cartão por vez.
    await abrir(tester, 'Eletricista 2026.1');
    await abrir(tester, 'Eletricista 2025.2');
    expect(find.text('Acrescentar 2 módulo(s)'), findsOneWidget);
  });

  testWidgets('montar cronograma grava os módulos que faltam, sem datas', (
    tester,
  ) async {
    final modular = await montar(tester, permissoes: secretaria);
    await abrir(tester, 'Eletricista 2026.2');
    await tester.tap(find.text('Montar cronograma'));
    await carregar(tester);

    expect(find.text('Montar cronograma'), findsWidgets, reason: 'o título');
    await tester.tap(find.byKey(chaveBotaoSalvar));
    await carregar(tester);

    expect(modular.modulosIncluidos, ['t-nova|mod-1,mod-2,mod-3']);
  });

  testWidgets('os alunos da turma aparecem com "desde", e quem saiu vem '
      'separado com o motivo', (tester) async {
    await montar(tester);
    await abrir(tester, 'Eletricista 2026.1');

    expect(find.text('Eduarda Lima'), findsOneWidget);
    expect(find.text('3005 · desde 06/07/2026'), findsOneWidget);
    // A saída fica na lista: `motivo_saida` é a única leitura do sistema que
    // responde "por que fulano não está mais aqui".
    expect(find.text('Saíram'), findsOneWidget);
    expect(find.text('Rafael Souza'), findsOneWidget);
    expect(find.text('saiu — mudou de cidade'), findsOneWidget);
  });

  testWidgets('quem já saiu NÃO oferece "Remover"', (tester) async {
    await montar(tester, permissoes: secretaria);
    await abrir(tester, 'Eletricista 2026.1');
    // Um "Remover" só — o de Eduarda. Oferecer o do Rafael devolveria
    // ALOCACAO_INEXISTENTE, e oferecer o que vai falhar é o que a decisão 1 do
    // card 2.6 proíbe.
    expect(find.text('Remover'), findsOneWidget);
  });

  testWidgets('sem alunos.ler a região DIZ o que falta, em vez de listar '
      'vazio', (tester) async {
    await montar(
      tester,
      permissoes: const {'turmas.ler', 'salas.ler', 'materiais.ler'},
    );
    await abrir(tester, 'Eletricista 2026.1');

    expect(find.text(semAcessoAlunos), findsOneWidget);
    expect(find.textContaining('alunos.ler'), findsWidgets);
    expect(
      find.text(vazioAlunosTurmaModular),
      findsNothing,
      reason:
          '"nenhum aluno nesta turma" ao lado de uma lotação 1/15 seria falso — '
          'a RLS reduziu a lista, não a turma',
    );
    // E a lotação continua certa: ela não depende de `alunos.ler`.
    expect(
      find.text('Eletricista Instalador · Sala Eletricista · 1/15'),
      findsOneWidget,
    );
  });

  testWidgets('turma vazia mostra o estado vazio da região com a ação', (
    tester,
  ) async {
    await montar(tester, permissoes: secretaria);
    await abrir(tester, 'Eletricista 2025.2');
    expect(find.text(vazioAlunosTurmaModular), findsOneWidget);
    expect(find.text('+ Adicionar aluno'), findsOneWidget);
  });

  testWidgets('sem turmas.alocar o estado vazio não oferece adicionar', (
    tester,
  ) async {
    await montar(tester);
    await abrir(tester, 'Eletricista 2025.2');
    expect(find.text(vazioAlunosTurmaModular), findsOneWidget);
    expect(find.text('+ Adicionar aluno'), findsNothing);
  });

  testWidgets('sem permissão de escrita nenhum botão de ação é renderizado', (
    tester,
  ) async {
    await montar(tester);
    expect(find.text('Nova turma'), findsNothing);
    await abrir(tester, 'Eletricista 2026.1');
    expect(find.text('Adicionar aluno'), findsNothing);
    expect(find.text('Editar turma'), findsNothing);
    expect(find.text('Avançar módulo'), findsNothing);
    expect(find.text('Remover'), findsNothing);
  });

  testWidgets('com a matriz da secretaria os botões aparecem', (tester) async {
    await montar(tester, permissoes: secretaria);
    expect(find.text('Nova turma'), findsOneWidget);
    await abrir(tester, 'Eletricista 2026.1');
    expect(find.text('Adicionar aluno'), findsWidgets);
    expect(find.text('Editar turma'), findsOneWidget);
    expect(find.text('Avançar módulo'), findsOneWidget);
  });

  testWidgets('estado vazio da TELA traz o texto do card 2.7 e a ação', (
    tester,
  ) async {
    await montar(tester, repositorio: ModularFalso(), permissoes: secretaria);
    expect(find.text(vazioTurmasModular), findsOneWidget);
    expect(find.text('+ Nova turma'), findsOneWidget);
  });

  testWidgets('sem turmas.criar o vazio não oferece criar', (tester) async {
    await montar(tester, repositorio: ModularFalso());
    expect(find.text(vazioTurmasModular), findsOneWidget);
    expect(find.text('+ Nova turma'), findsNothing);
  });

  testWidgets('filtro que não casa dá o outro vazio, com "Limpar filtros"', (
    tester,
  ) async {
    await montar(tester);
    await tester.enterText(
      find.byKey(const Key('busca_turma_modular')),
      'inexistente',
    );
    await carregar(tester);
    expect(find.text(vazioTurmasModularFiltro), findsOneWidget);
    expect(find.text('Limpar filtros'), findsOneWidget);
    expect(
      find.text(vazioTurmasModular),
      findsNothing,
      reason:
          '"nenhuma turma cadastrada" com filtro ligado é falso, e não oferece '
          'a saída',
    );
  });

  testWidgets('erro de leitura mostra EstadoErro com "Tentar de novo"', (
    tester,
  ) async {
    await montar(tester, repositorio: ModularFalso.queFalha());
    expect(
      find.textContaining('Não foi possível falar com o servidor'),
      findsOneWidget,
    );
    expect(find.text('Tentar de novo'), findsOneWidget);
  });

  testWidgets('?turma= abre a turma pedida já expandida', (tester) async {
    await montar(tester, turmaId: 't-2025');
    // O cronograma da 2025.2 só aparece com o cartão aberto.
    expect(find.text('1. Módulo 1 — Comandos elétricos'), findsOneWidget);
  });

  testWidgets('adicionar aluno chama a função com a turma e o aluno', (
    tester,
  ) async {
    final modular = await montar(tester, permissoes: secretaria);
    await abrir(tester, 'Eletricista 2025.2');
    await tester.tap(find.text('+ Adicionar aluno'));
    await carregar(tester);

    // A fixture de alunos tem uma MODULAR (Eduarda), e ela não está na 2025.2.
    await tester.tap(find.text('Eduarda Lima (3005)'));
    await carregar(tester);
    await tester.tap(find.byKey(chaveBotaoSalvar));
    await carregar(tester);

    expect(modular.admitidos, ['t-2025|al-3005']);
  });

  testWidgets('o formulário de adicionar avisa quando não há vaga, e o aviso '
      'diz que quem decide é o banco', (tester) async {
    await montar(tester, permissoes: secretaria);
    await abrir(tester, 'Depilação 2026.1');
    await tocar(tester, find.text('Adicionar aluno').last);
    expect(find.textContaining('sem vaga livre'), findsOneWidget);
    expect(find.textContaining('confere ao salvar'), findsOneWidget);
  });

  testWidgets('TURMA_LOTADA do banco vira banner traduzido, e não erro cru', (
    tester,
  ) async {
    final modular = ModularFalso.fixture()
      ..erroAoAdmitir = const ErroApp(
        mensagem:
            'Esta turma está lotada. Remova um aluno, aumente a capacidade da '
            'turma ou use outra turma do curso.',
        codigo: 'TURMA_LOTADA',
        traduzido: true,
      );
    await montar(tester, repositorio: modular, permissoes: secretaria);
    await abrir(tester, 'Eletricista 2025.2');
    await tester.tap(find.text('+ Adicionar aluno'));
    await carregar(tester);
    await tester.tap(find.text('Eduarda Lima (3005)'));
    await carregar(tester);
    await tester.tap(find.byKey(chaveBotaoSalvar));
    await carregar(tester);

    expect(find.textContaining('Esta turma está lotada'), findsOneWidget);
  });

  testWidgets('avançar módulo manda a data e conclui o corrente', (
    tester,
  ) async {
    final modular = await montar(tester, permissoes: secretaria);
    await abrir(tester, 'Eletricista 2026.1');
    await tester.tap(find.text('Avançar módulo'));
    await carregar(tester);

    // O diálogo diz o que fecha e o que abre, antes do clique (wireframe §8).
    expect(
      find.textContaining('Fecha 2. Módulo 2 — Instalações prediais'),
      findsOneWidget,
    );
    expect(find.textContaining('Abre 3. Módulo 3 — Projetos'), findsOneWidget);
    expect(find.text(avisoAvancoConjunto), findsOneWidget);

    await tester.tap(find.byKey(chaveBotaoSalvar));
    await carregar(tester);

    expect(modular.avancos.single, startsWith('t-2026|'));
    expect(
      modular.cronograma_.firstWhere((m) => m.id == 'cr-2').concluido,
      isTrue,
    );
  });

  testWidgets('o avanço que fecha o ÚLTIMO módulo abre diálogo, e não '
      'snackbar', (tester) async {
    final modular = ModularFalso.fixture();
    await montar(tester, repositorio: modular, permissoes: secretaria);
    await abrir(tester, 'Depilação 2026.1');
    await tocar(tester, find.text('Avançar módulo'));
    await tocar(tester, find.byKey(chaveBotaoSalvar));

    // Resultado que muda a próxima ação é diálogo (design-system §5.8): um
    // snackbar de 4 s some antes de ser lido.
    expect(find.text('Turma terminou'), findsOneWidget);
    expect(find.text('Entendi'), findsOneWidget);
  });

  testWidgets('editar as datas de um módulo grava as duas, e permite apagar', (
    tester,
  ) async {
    final modular = await montar(tester, permissoes: secretaria);
    await abrir(tester, 'Eletricista 2026.1');
    await tester.tap(find.text('3. Módulo 3 — Projetos'));
    await carregar(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Início do módulo'),
      '01/11/2026',
    );
    await tester.tap(find.byKey(chaveBotaoSalvar));
    await carregar(tester);

    expect(modular.datasSalvas, ['cr-3|2026-11-01|']);
  });

  testWidgets('sem turmas.editar a linha do cronograma não é clicável', (
    tester,
  ) async {
    await montar(tester);
    await abrir(tester, 'Eletricista 2026.1');
    await tester.tap(find.text('3. Módulo 3 — Projetos'));
    await carregar(tester);
    // Nenhum formulário abriu: não há o que oferecer, e um toque que abre um
    // formulário só de leitura ensina a tocar em vão.
    expect(find.byType(FormularioIm360), findsNothing);
  });

  testWidgets('as turmas inativas ficam alcançáveis — desativar não é porta '
      'de mão única', (tester) async {
    await montar(tester, permissoes: secretaria);
    expect(find.text('Inativas (1)'), findsOneWidget);
    await tester.tap(find.text('Inativas (1)'));
    await carregar(tester);
    expect(find.text('Eletricista 2024.1'), findsOneWidget);
  });

  testWidgets('só um cartão fica aberto por vez', (tester) async {
    await montar(tester);
    await abrir(tester, 'Eletricista 2026.1');
    expect(find.text('Cronograma'), findsOneWidget);
    await abrir(tester, 'Eletricista 2025.2');
    expect(
      find.text('Cronograma'),
      findsOneWidget,
      reason:
          'o cartão anterior fechou: dois abertos empurram as outras turmas '
          'para fora da tela (wireframe §8)',
    );
  });
}
