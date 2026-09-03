import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../erros/erro_app.dart';
import '../../infraestrutura/infraestrutura.dart';
import '../../infraestrutura/infraestrutura_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../widgets/botoes.dart';
import '../../widgets/confirmacao.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';
import '../../widgets/painel_detalhe.dart';
import 'formularios.dart';

/// O painel da sala: cabeçalho com nominal × efetiva, a lista de PCs com a
/// situação de cada um e a ação contextual da linha — Manutenção, Encerrar ou
/// Reativar (docs/wireframes.md §13). No mobile, é a jornada nº 3 do monitor:
/// a manutenção fica a dois toques da lista de salas.
class DetalheSala extends ConsumerWidget {
  const DetalheSala({super.key, required this.salaId});

  final String salaId;

  Future<void> _abrirPc(BuildContext context, {Pc? pc}) async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) => FormularioPc(pc: pc, salaId: salaId),
    );
    if (resultado != null && context.mounted) {
      confirmarEfemero(
        context,
        resultado == 'excluido' ? 'PC excluído.' : 'PC salvo.',
      );
    }
  }

  Future<void> _acao(BuildContext context, Pc pc, PcManutencao? aberta) async {
    final acao = acaoContextual(pc, aberta);
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) => switch (acao) {
        AcaoPc.registrarManutencao => FormularioManutencao(pc: pc),
        AcaoPc.encerrarManutencao => FormularioEncerrarManutencao(
          pc: pc,
          manutencao: aberta!,
        ),
        AcaoPc.reativar => FormularioReativarPc(pc: pc),
      },
    );
    if (resultado != null && context.mounted) {
      confirmarEfemero(context, switch (acao) {
        AcaoPc.registrarManutencao => 'Manutenção registrada.',
        AcaoPc.encerrarManutencao => 'Manutenção encerrada.',
        AcaoPc.reativar => 'PC reativado.',
      });
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salas = ref.watch(salasProvider).value ?? const <Sala>[];
    Sala? sala;
    for (final s in salas) {
      if (s.id == salaId) sala = s;
    }
    if (sala == null) {
      // Excluída por outra pessoa enquanto o painel estava aberto.
      return const PainelDetalhe(
        titulo: 'Sala',
        subtitulo: '',
        acoes: [],
        filho: EstadoVazio(mensagem: 'Esta sala não existe mais.'),
      );
    }
    final salaAtual = sala;

    final pcs = ref.watch(pcsProvider);
    final manutencoes =
        ref.watch(manutencoesProvider).value ?? const <PcManutencao>[];
    final abertas = manutencoesAbertas(manutencoes, DateTime.now());
    final pcsDaSala = [
      for (final p in pcs.value ?? const <Pc>[])
        if (p.salaId == salaId) p,
    ]..sort((a, b) => a.identificador.compareTo(b.identificador));
    final resumo =
        resumirSalas([salaAtual], pcsDaSala)[salaId] ?? ResumoSala.vazio;

    return PainelDetalhe(
      titulo: salaAtual.nome,
      subtitulo: [
        rotuloTipoSala(salaAtual.tipo),
        'cap. nominal ${salaAtual.capacidadeNominal}',
        'efetiva ${resumo.efetiva}',
        if (!salaAtual.ativo) 'inativa',
      ].join(' · '),
      acoes: [
        BotaoAcao(
          rotulo: 'Editar',
          nivel: NivelBotao.secundario,
          exigePermissao: 'salas.editar',
          icone: Icons.edit_outlined,
          aoTocar: () async {
            final resultado = await mostrarFormulario<String>(
              context,
              construtor: (_) => FormularioSala(sala: salaAtual),
            );
            if (!context.mounted || resultado == null) return;
            if (resultado == 'excluido') {
              Navigator.of(context).pop('excluido');
            } else {
              confirmarEfemero(context, 'Sala salva.');
            }
          },
        ),
        BotaoAcao(
          rotulo: 'Novo PC',
          nivel: NivelBotao.secundario,
          exigePermissao: 'salas.criar',
          icone: Icons.add,
          aoTocar: () => _abrirPc(context),
        ),
      ],
      filho: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TituloSecao(
            texto: 'Computadores',
            apoio:
                'A capacidade efetiva conta os PCs operacionais até o teto '
                'nominal da sala. O efeito nos blocos de horário aparece na '
                'grade de turmas.',
          ),
          pcs.when(
            loading: () => const EstadoCarregando(linhas: 3),
            error: (erro, _) => EstadoErro(
              mensagem: (erro is ErroApp ? erro : traduzirErro(erro)).mensagem,
              aoRepetir: ref
                  .read(versaoInfraestruturaProvider.notifier)
                  .incrementar,
            ),
            data: (_) => pcsDaSala.isEmpty
                ? Text(
                    'Nenhum computador nesta sala.',
                    style: Tipografia.corpoTabela.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
                : Column(
                    children: [
                      for (final pc in pcsDaSala)
                        _LinhaPc(
                          pc: pc,
                          aberta: abertas[pc.id],
                          aoAbrir: () => _abrirPc(context, pc: pc),
                          aoAgir: () => _acao(context, pc, abertas[pc.id]),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _LinhaPc extends StatelessWidget {
  const _LinhaPc({
    required this.pc,
    required this.aberta,
    required this.aoAbrir,
    required this.aoAgir,
  });

  final Pc pc;
  final PcManutencao? aberta;
  final VoidCallback aoAbrir;
  final VoidCallback aoAgir;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final acao = acaoContextual(pc, aberta);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: Dim.alvoMobile,
      // O ícone acompanha o status, mas quem carrega o significado é o texto
      // da linha — cor e forma nunca sozinhas (design-system §8).
      leading: Icon(switch (pc.status) {
        'MANUTENCAO' => Icons.build_outlined,
        'DESATIVADO' => Icons.desktop_access_disabled,
        _ => Icons.desktop_windows_outlined,
      }, color: cores.onSurfaceVariant),
      title: Text(pc.identificador, style: Tipografia.corpoTabela),
      subtitle: Text(
        situacaoPc(pc, aberta),
        style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
      ),
      trailing: BotaoAcao(
        rotulo: switch (acao) {
          AcaoPc.registrarManutencao => 'Manutenção',
          AcaoPc.encerrarManutencao => 'Encerrar',
          AcaoPc.reativar => 'Reativar',
        },
        nivel: NivelBotao.terciario,
        exigePermissao: switch (acao) {
          AcaoPc.reativar => 'salas.editar',
          _ => 'salas.registrar_manutencao',
        },
        aoTocar: aoAgir,
      ),
      onTap: aoAbrir,
    );
  }
}
