import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/config/politica_retry.dart';
import 'package:gestao_im360/rotas/roteador.dart';
import 'package:gestao_im360/sessao/sessao.dart';
import 'package:gestao_im360/sessao/sessao_provider.dart';
import 'package:gestao_im360/sessao/sessao_repositorio.dart';
import 'package:gestao_im360/telas/sem_acesso.dart';
import 'package:gestao_im360/theme/tema.dart';
import 'package:gestao_im360/widgets/estados.dart';

/// Uma sessão que nunca termina de carregar — a janela de um a três segundos
/// da abertura do app, esticada para o teste poder olhá-la.
class _SessaoEternamenteCarregando implements SessaoRepositorio {
  @override
  Future<EstadoSessao> carregar() => Completer<EstadoSessao>().future;

  @override
  Future<void> entrar({required String email, required String senha}) async {}

  @override
  Future<void> recuperarSenha(
    String email, {
    required String redirecionarPara,
  }) async {}

  @override
  Future<void> trocarSenha(String novaSenha) async {}

  @override
  Future<void> sair() async {}
}

/// Card 9.2,63: durante `SessaoCarregando` as permissões são o conjunto VAZIO,
/// e a guarda de rota mostrava "Sem acesso" com TODAS as permissões
/// "faltando" a cada abertura do app — a tela afirmava o que não sabia.
void main() {
  for (final tamanho in const [Size(1400, 900), Size(390, 800)]) {
    testWidgets('enquanto a sessão carrega, a rota mostra CARREGANDO e nunca '
        '"Sem acesso" (${tamanho.width.toInt()} px)', (tester) async {
      tester.view.physicalSize = tamanho;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        retry: semRetryAutomatico,
        overrides: [
          sessaoRepositorioProvider.overrideWithValue(
            _SessaoEternamenteCarregando(),
          ),
          fluxoAuthProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: temaClaro(),
            routerConfig: container.read(roteadorProvider),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(container.read(sessaoProvider), isA<SessaoCarregando>());
      expect(find.byType(TelaSemAcesso), findsNothing);
      expect(find.byType(EstadoCarregando), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  // Card 9.2,64 (DECISÃO adotada): no celular o app abre na primeira tela da
  // BARRA que a pessoa consegue abrir — Alunos, para o monitor —, e não no
  // Dashboard, que não está na barra. Decide a largura, nunca o perfil.
  for (final (tamanho, destino) in const [
    (Size(390, 800), '/alunos'),
    (Size(1400, 900), '/'),
  ]) {
    testWidgets('com sessão, o app abre em $destino '
        '(${tamanho.width.toInt()} px)', (tester) async {
      tester.view.physicalSize = tamanho;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        retry: semRetryAutomatico,
        overrides: [
          sessaoRepositorioProvider.overrideWithValue(_SessaoPronta()),
          fluxoAuthProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);
      final roteador = container.read(roteadorProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(theme: temaClaro(), routerConfig: roteador),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // As telas de destino tentam o Supabase, que o teste não inicializa: o
      // que se mede aqui é só PARA ONDE o roteador levou.
      tester.takeException();

      expect(roteador.routerDelegate.currentConfiguration.uri.path, destino);
    });
  }
}

/// A sessão do monitor, pronta: o conjunto que abre Alunos, Turmas e
/// Pendências — e também o Dashboard, que é o ponto do teste.
class _SessaoPronta extends _SessaoEternamenteCarregando {
  @override
  Future<EstadoSessao> carregar() async => const SessaoAtiva(
    Sessao(
      usuarioId: 'u-monitor',
      nome: 'Monitor',
      email: 'monitor@escola-a.test',
      unidadeId: 'unidade-teste',
      permissoes: {
        'alunos.ler',
        'materiais.ler',
        'turmas.ler',
        'salas.ler',
        'professores.ler',
        'pendencias.ler',
        'estoque.ler',
        'estoque.lancar_saida',
      },
    ),
  );
}
