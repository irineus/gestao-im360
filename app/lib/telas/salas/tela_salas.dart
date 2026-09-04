import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../infraestrutura/infraestrutura.dart';
import '../../infraestrutura/infraestrutura_provider.dart';
import '../../sessao/sessao_provider.dart';
import '../../widgets/abertura_por_url.dart';
import '../../widgets/botoes.dart';
import '../../widgets/confirmacao.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';
import '../../widgets/painel_detalhe.dart';
import '../../widgets/tabela_im360.dart';
import 'detalhe_sala.dart';
import 'filtros_salas.dart';
import 'formularios.dart';

/// Tela 10 — Salas e PCs (docs/wireframes.md §13), card 4.5: as salas com os
/// seus PCs, a manutenção de cada PC, a credencial de acesso (política do card
/// 2.9 §8) e, na segunda aba, os professores — que moram aqui, junto do uso, e
/// não na Administração (card 2.6, apontamento 1).
///
/// O que fica para a Fase 5, e a tela diz onde: o impacto da manutenção nos
/// blocos de horário ("Blocos desta sala" do wireframe) é a grade do card 5.6,
/// e amarrar `pc.status` à manutenção em aberto é a regra do card 5.4. Aqui a
/// capacidade efetiva é **informativa** — PCs operacionais até o teto nominal.
class TelaSalas extends StatelessWidget {
  const TelaSalas({super.key, this.pcId});

  /// `?pc=<id>` — o atalho da central de pendências (`PC_SEM_SUBSTITUTO` leva
  /// para cá, wireframe §14.3). A tela abre o detalhe da **sala daquele PC**;
  /// sem o id, "Ver PC" abria a lista de salas e a pessoa procurava de novo o
  /// que a pendência já sabia.
  final String? pcId;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Column(
      children: [
        const TabBar(
          tabs: [
            Tab(text: 'Salas e PCs'),
            Tab(text: 'Professores'),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              AbaSalas(pcId: pcId),
              const AbaProfessores(),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Estado vazio da tela (design-system §7.2) — os textos são os do card 2.7;
/// "com esses filtros" segue o padrão que a tela de Materiais abriu.
const vazioSalas = 'Nenhuma sala cadastrada.';
const vazioSalasFiltro = 'Nenhuma sala com esses filtros.';
const vazioProfessores = 'Nenhum professor cadastrado.';
const vazioProfessoresFiltro = 'Nenhum professor com esses filtros.';

// ---------------------------------------------------------------------------
// Salas e PCs
// ---------------------------------------------------------------------------

class AbaSalas extends ConsumerStatefulWidget {
  const AbaSalas({super.key, this.pcId});

  /// O PC pedido na URL — a aba abre o detalhe da sala dele.
  final String? pcId;

  @override
  ConsumerState<AbaSalas> createState() => _AbaSalasState();
}

class _AbaSalasState extends ConsumerState<AbaSalas>
    with AberturaPorUrl<AbaSalas> {
  @override
  void didUpdateWidget(AbaSalas anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.pcId != widget.pcId) reabrirNaProxima();
  }

  Future<void> _novaSala(BuildContext context) async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) => const FormularioSala(),
    );
    if (resultado != null && context.mounted) {
      confirmarEfemero(context, 'Sala salva.');
    }
  }

  Future<void> _novoPc(BuildContext context) async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) => const FormularioPc(),
    );
    if (resultado != null && context.mounted) {
      confirmarEfemero(context, 'PC salvo.');
    }
  }

  Future<void> _detalhe(BuildContext context, Sala sala) =>
      _detalhePorId(context, sala.id!);

  Future<void> _detalhePorId(BuildContext context, String salaId) async {
    final resultado = await mostrarFormulario<String>(
      context,
      largura: larguraDetalhe,
      construtor: (_) => DetalheSala(salaId: salaId),
    );
    if (resultado == 'excluido' && context.mounted) {
      confirmarEfemero(context, 'Sala excluída.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final salas = ref.watch(salasProvider);
    final pcs = ref.watch(pcsProvider).value ?? const <Pc>[];

    // O atalho da pendência traz o **PC**; a tela de destino é a sala dele.
    final pedido = widget.pcId;
    if (pedido != null && salas.hasValue) {
      String? salaDoPc;
      for (final pc in pcs) {
        if (pc.id == pedido) salaDoPc = pc.salaId;
      }
      abrirUmaVez(salaDoPc, (salaId) => _detalhePorId(context, salaId));
    }
    final resumo = resumirSalas(salas.value ?? const <Sala>[], pcs);
    final filtro = ref.watch(filtroSalasProvider);
    final permissoes = ref.watch(permissoesProvider);
    final haCadastro = salas.value?.isNotEmpty ?? false;
    ResumoSala resumoDe(Sala s) => resumo[s.id] ?? ResumoSala.vazio;

    return TabelaIm360<Sala>(
      filtros: const FiltrosSalas(),
      filtrosAtivos: filtro.ativos,
      acoes: [
        BotaoAcao(
          rotulo: 'Novo PC',
          icone: Icons.add,
          nivel: NivelBotao.secundario,
          exigePermissao: 'salas.criar',
          aoTocar: () => _novoPc(context),
        ),
        BotaoAcao(
          rotulo: 'Nova sala',
          icone: Icons.add,
          exigePermissao: 'salas.criar',
          aoTocar: () => _novaSala(context),
        ),
      ],
      colunas: [
        ColunaIm360(
          titulo: 'Sala',
          texto: (s) => s.nome,
          flex: 3,
          larguraMin: 200,
        ),
        ColunaIm360(
          titulo: 'Tipo',
          texto: (s) => rotuloTipoSala(s.tipo),
          prioridade: 2,
          larguraMin: 130,
        ),
        // "operacionais/total": os dois números que o card 5.4 separa — o PC
        // parado continua cadastrado e continua fora da capacidade.
        ColunaIm360(
          titulo: 'PCs',
          texto: (s) => '${resumoDe(s).operacionais}/${resumoDe(s).total}',
          numerica: true,
          prioridade: 2,
          flex: 1,
          larguraMin: 90,
        ),
        ColunaIm360(
          titulo: 'Cap. nominal',
          texto: (s) => '${s.capacidadeNominal}',
          numerica: true,
          prioridade: 3,
          flex: 1,
          larguraMin: 110,
        ),
        ColunaIm360(
          titulo: 'Cap. efetiva',
          texto: (s) => '${resumoDe(s).efetiva}',
          numerica: true,
          flex: 1,
          larguraMin: 110,
        ),
        ColunaIm360(
          titulo: 'Situação',
          texto: (s) => s.ativo ? 'Ativa' : 'Inativa',
          prioridade: 3,
          flex: 1,
          larguraMin: 100,
        ),
      ],
      linhas: salas.whenData((lista) => filtrarSalas(lista, filtro)),
      cartao: (s) => CartaoIm360(
        titulo: s.nome,
        subtitulo:
            '${rotuloTipoSala(s.tipo)} · ${resumoDe(s).operacionais}/'
            '${resumoDe(s).total} PCs operacionais',
        apoio: s.ativo ? null : 'Inativa',
        destaque: 'cap. ${resumoDe(s).efetiva}',
      ),
      estadoVazio: haCadastro
          ? EstadoVazio(
              mensagem: vazioSalasFiltro,
              icone: Icons.filter_alt_off_outlined,
              rotuloAcao: 'Limpar filtros',
              aoAgir: ref.read(filtroSalasProvider.notifier).limpar,
            )
          : EstadoVazio(
              mensagem: vazioSalas,
              rotuloAcao: permissoes.contains('salas.criar')
                  ? '+ Nova sala'
                  : null,
              aoAgir: () => _novaSala(context),
            ),
      aoTocarLinha: (s) => _detalhe(context, s),
      aoRepetir: ref.read(versaoInfraestruturaProvider.notifier).incrementar,
    );
  }
}

// ---------------------------------------------------------------------------
// Professores
// ---------------------------------------------------------------------------

class AbaProfessores extends ConsumerWidget {
  const AbaProfessores({super.key});

  Future<void> _abrir(BuildContext context, Professor? professor) async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) => FormularioProfessor(professor: professor),
    );
    if (resultado != null && context.mounted) {
      confirmarEfemero(context, 'Professor salvo.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final professores = ref.watch(professoresProvider);
    final filtro = ref.watch(filtroProfessoresProvider);
    final permissoes = ref.watch(permissoesProvider);
    final haCadastro = professores.value?.isNotEmpty ?? false;

    return TabelaIm360<Professor>(
      filtros: const FiltrosProfessores(),
      filtrosAtivos: filtro.ativos,
      acoes: [
        BotaoAcao(
          rotulo: 'Novo professor',
          icone: Icons.add,
          exigePermissao: 'professores.criar',
          aoTocar: () => _abrir(context, null),
        ),
      ],
      colunas: [
        ColunaIm360(
          titulo: 'Professor',
          texto: (p) => p.nome,
          flex: 3,
          larguraMin: 200,
        ),
        ColunaIm360(
          titulo: 'Situação',
          texto: (p) => p.ativo ? 'Ativo' : 'Inativo',
          prioridade: 2,
          flex: 1,
          larguraMin: 100,
        ),
      ],
      linhas: professores.whenData(
        (lista) => filtrarProfessores(lista, filtro),
      ),
      cartao: (p) =>
          CartaoIm360(titulo: p.nome, apoio: p.ativo ? null : 'Inativo'),
      estadoVazio: haCadastro
          ? EstadoVazio(
              mensagem: vazioProfessoresFiltro,
              icone: Icons.filter_alt_off_outlined,
              rotuloAcao: 'Limpar filtros',
              aoAgir: ref.read(filtroProfessoresProvider.notifier).limpar,
            )
          : EstadoVazio(
              mensagem: vazioProfessores,
              rotuloAcao: permissoes.contains('professores.criar')
                  ? '+ Novo professor'
                  : null,
              aoAgir: () => _abrir(context, null),
            ),
      aoTocarLinha: (p) => _abrir(context, p),
      aoRepetir: ref.read(versaoInfraestruturaProvider.notifier).incrementar,
    );
  }
}
