import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/administracao/administracao.dart';

import 'apoio/administracao_falso.dart';

/// A lógica pura da administração (card 4.7): o que a tela deriva sem rede.
void main() {
  final fixture = AdministracaoFalso.fixture();

  group('agruparPorDominio', () {
    test('segue a ordem do menu e ordena por código dentro do domínio', () {
      final grupos = agruparPorDominio(fixture.permissoes_);
      expect(grupos.map((g) => g.dominio), [
        'alunos',
        'estoque',
        'compras',
        'admin',
        'parametros',
      ]);
      expect(grupos.first.rotulo, 'Alunos');
      expect(grupos.first.permissoes.map((p) => p.codigo), [
        'alunos.ler',
        'alunos.reverter_status',
      ]);
    });

    test('domínio que o app não conhece vai para o fim, sem sumir', () {
      final grupos = agruparPorDominio([
        ...fixture.permissoes_,
        const Permissao(
          id: 'x',
          codigo: 'zeta.ler',
          descricao: 'código novo',
          dominio: 'zeta',
        ),
      ]);
      expect(grupos.last.dominio, 'zeta');
      expect(grupos.last.rotulo, 'zeta');
    });
  });

  group('usuários', () {
    final perfisPorId = {for (final p in fixture.perfis_) p.id!: p};

    test('rotuloPerfis lista os códigos em ordem, ou "sem perfil"', () {
      expect(
        rotuloPerfis(
          const UsuarioAdmin(
            id: 'u',
            nome: 'n',
            email: 'e',
            perfisIds: {'p-monitor', 'p-direcao'},
          ),
          perfisPorId,
        ),
        'DIRECAO, MONITOR',
      );
      expect(
        rotuloPerfis(
          const UsuarioAdmin(id: 'u', nome: 'n', email: 'e'),
          perfisPorId,
        ),
        'sem perfil',
      );
    });

    test('contarSemPerfil ignora o desativado — ele não entra de qualquer '
        'jeito', () {
      expect(contarSemPerfil(fixture.usuarios_), 1);
      expect(
        contarSemPerfil([
          const UsuarioAdmin(id: 'u', nome: 'n', email: 'e', ativo: false),
        ]),
        0,
      );
    });

    test('situacaoUsuario: desativado vence convite pendente', () {
      const convidada = UsuarioAdmin(
        id: 'u',
        nome: 'n',
        email: 'e',
        convitePendente: true,
      );
      expect(situacaoUsuario(convidada), 'Convite pendente');
      expect(
        situacaoUsuario(convidada.copiar(ativo: false)),
        'Desativado',
        reason: 'quem não pode entrar não tem convite a reenviar',
      );
      expect(
        situacaoUsuario(const UsuarioAdmin(id: 'u', nome: 'n', email: 'e')),
        'Ativo',
      );
    });

    test('podeReenviarConvite: só quem ainda não aceitou E está ativo', () {
      // Para quem já definiu senha o GoTrue recusa com email_exists: oferecer
      // o botão seria oferecer um clique que só sabe falhar (card 4.7,7).
      const aceitou = UsuarioAdmin(id: 'u', nome: 'n', email: 'e');
      expect(podeReenviarConvite(aceitou), isFalse);
      expect(
        podeReenviarConvite(aceitou.copiar(convitePendente: true)),
        isTrue,
      );
      expect(
        podeReenviarConvite(
          aceitou.copiar(convitePendente: true, ativo: false),
        ),
        isFalse,
      );
    });

    test('apoioUsuario acumula os perfis e o convite pendente', () {
      const base = UsuarioAdmin(
        id: 'u',
        nome: 'n',
        email: 'e',
        perfisIds: {'p-monitor'},
      );
      expect(apoioUsuario(base, perfisPorId), 'MONITOR');
      expect(
        apoioUsuario(base.copiar(convitePendente: true), perfisPorId),
        'MONITOR · convite pendente',
      );
      expect(
        apoioUsuario(
          const UsuarioAdmin(
            id: 'u',
            nome: 'n',
            email: 'e',
            convitePendente: true,
          ),
          perfisPorId,
        ),
        '⚠ sem perfil · convite pendente',
        reason: 'sem perfil e convite pendente são coisas diferentes',
      );
      expect(
        apoioUsuario(
          base.copiar(ativo: false, convitePendente: true),
          perfisPorId,
        ),
        'Desativado',
      );
    });

    test('planejarPerfis: insere o que falta, remove o que sobra', () {
      final plano = planejarPerfis({'a', 'b'}, {'b', 'c'});
      expect(plano.inserir, {'c'});
      expect(plano.remover, {'a'});
      expect(plano.vazio, isFalse);
      expect(planejarPerfis({'a'}, {'a'}).vazio, isTrue);
    });

    test(
      'filtro: só ativos por padrão, busca por nome ou e-mail, sem perfil',
      () {
        const padrao = FiltroUsuarios();
        expect(
          filtrarUsuarios(fixture.usuarios_, padrao).map((u) => u.id),
          isNot(contains('u-desativado')),
        );
        expect(
          filtrarUsuarios(
            fixture.usuarios_,
            FiltroUsuarios.semFiltro,
          ).map((u) => u.id),
          contains('u-desativado'),
        );
        expect(
          filtrarUsuarios(
            fixture.usuarios_,
            const FiltroUsuarios(busca: 'MONITOR@'),
          ).map((u) => u.id),
          ['u-monitor'],
        );
        expect(
          filtrarUsuarios(
            fixture.usuarios_,
            const FiltroUsuarios(soSemPerfil: true),
          ).map((u) => u.id),
          ['u-semperfil'],
        );
        expect(const FiltroUsuarios(busca: 'x', soSemPerfil: true).ativos, 3);
        expect(FiltroUsuarios.semFiltro.ativos, 0);
      },
    );

    test('paraLinha nunca leva e-mail nem unidade — só o que o app edita', () {
      expect(fixture.usuarios_.first.paraLinha().keys, ['nome', 'ativo']);
    });
  });

  group('parâmetros', () {
    test('aviso de rotina para rep_*, projecao_*, ritmo_* e standby_*; nenhum '
        'para os demais', () {
      for (final chave in [
        'rep_prazo_dias',
        'projecao_horizonte_dias',
        'ritmo_janela_entregas',
        'standby_alerta_dias',
      ]) {
        expect(avisoParametro(chave), avisoParametroRotina, reason: chave);
      }
      expect(avisoParametro('direcao_inicial_email'), isNull);
    });

    test('validação por tipo é só de formato', () {
      expect(validarValorParametro('INTEIRO', '60'), isNull);
      expect(validarValorParametro('INTEIRO', '6,5'), isNotNull);
      expect(validarValorParametro('INTEIRO', ''), 'Campo obrigatório.');
      expect(validarValorParametro('DECIMAL', '6,5'), isNull);
      expect(validarValorParametro('DECIMAL', 'abc'), isNotNull);
      expect(validarValorParametro('BOOLEANO', 'TRUE'), isNull);
      expect(validarValorParametro('BOOLEANO', 'sim'), isNotNull);
      expect(validarValorParametro('DATA', '31/12/2026'), isNull);
      expect(validarValorParametro('DATA', '31/02/2026'), isNotNull);
      expect(validarValorParametro('TEXTO', 'qualquer coisa'), isNull);
    });

    test('normalização: decimal com ponto, booleano minúsculo, data ISO', () {
      expect(normalizarValorParametro('DECIMAL', '6,5'), '6.5');
      expect(normalizarValorParametro('BOOLEANO', 'TRUE'), 'true');
      expect(normalizarValorParametro('DATA', '31/12/2026'), '2026-12-31');
      expect(normalizarValorParametro('TEXTO', '  x '), 'x');
    });

    test('exibição: data volta a dd/mm/aaaa; o resto como está', () {
      expect(
        exibirValorParametro(
          const Parametro(chave: 'k', valor: '2026-12-31', tipo: 'DATA'),
        ),
        '31/12/2026',
      );
      expect(
        exibirValorParametro(const Parametro(chave: 'k', valor: '60')),
        '60',
      );
    });

    test('chave em snake_case; código de perfil em caixa alta', () {
      expect(validarChaveParametro('standby_alerta_dias'), isNull);
      expect(validarChaveParametro('ritmo_padrao_dias_INTERATIVO'), isNull);
      expect(validarChaveParametro('Standby'), isNotNull);
      expect(validarChaveParametro(''), 'Campo obrigatório.');
      expect(validarCodigoPerfil('COORDENACAO'), isNull);
      expect(validarCodigoPerfil('coordenacao'), isNull, reason: 'caixa alta');
      expect(validarCodigoPerfil('1A'), isNotNull);
      expect(validarCodigoPerfil('COORD-ENACAO'), isNotNull);
    });
  });

  group('histórico', () {
    test('rótulos de ação e de autor; sistema quando foi o seed', () {
      expect(rotuloAcaoHistorico('CONCEDIDA'), 'Concedida');
      expect(rotuloAcaoHistorico('REMOVIDA'), 'Removida');
      expect(rotuloAutorHistorico(null), 'sistema (seed)');
      expect(rotuloAutorHistorico('Direção A'), 'Direção A');
    });

    test('formatarQuando é dd/mm/aaaa hh:mm', () {
      expect(formatarQuando(DateTime(2026, 9, 3, 7, 5)), '03/09/2026 07:05');
    });
  });

  test('contarMarcadas: zero sem perfil selecionado', () {
    expect(contarMarcadas(fixture.matriz_, null), 0);
    expect(contarMarcadas(fixture.matriz_, 'p-secretaria'), 3);
  });
}
