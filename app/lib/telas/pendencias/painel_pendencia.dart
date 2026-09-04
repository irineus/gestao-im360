import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../pendencias/pendencias.dart';
import '../../pendencias/pendencias_provider.dart';
import '../../rotas/rotas.dart';
import '../../sessao/sessao_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../turmas/turmas.dart';
import '../../turmas/turmas_provider.dart';
import '../../widgets/botoes.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';
import '../../widgets/painel_detalhe.dart';
import '../turmas/formularios.dart' show recarregarTurmas;
import 'formularios.dart';
import 'severidade.dart';
import 'tela_pendencias.dart';

/// O detalhe de uma pendência e o lugar de onde se age sobre ela (wireframe
/// §14.2 e §14.3), card 5.8.
///
/// Três blocos, na ordem em que se lê: **o que é** (descrição com os números do
/// dia, referência, idade e a promessa de fechamento automático), **o que a
/// resolve** (a ação contextual, que leva à tela onde o problema se desfaz), e
/// **como encerrá-la** (resolver ou ignorar).
///
/// `REP_VIRADA` ganha um quarto bloco, e é o motivo de o painel existir: os
/// números do critério do card 2.5 e as reposições previstas do aluno, com a
/// marcação de presença ao lado. Marcar presença é o que muda o débito — e era
/// a função entregue e sem chamador que o card 5.7 registrou.
class PainelPendencia extends ConsumerWidget {
  const PainelPendencia({super.key, required this.pendenciaId});

  final String pendenciaId;

  /// A tela que abriu é quem confirma e recarrega — o painel pode estar
  /// descrevendo uma pendência que acabou de sair da lista.
  Future<void> _fechar(
    BuildContext context,
    Pendencia pendencia,
    String resolucao,
  ) async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) =>
          FormularioFecharPendencia(pendencia: pendencia, resolucao: resolucao),
    );
    if (resultado != null && context.mounted) {
      Navigator.of(context).pop(resultado);
    }
  }

  Future<void> _executar(BuildContext context, Pendencia pendencia) async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) => pendencia.sentido == SentidoVirada.continuo
          ? FormularioVirarContinuo(pendencia: pendencia)
          : FormularioVoltarPontual(pendencia: pendencia),
    );
    if (resultado != null && context.mounted) {
      Navigator.of(context).pop(resultado);
    }
  }

  /// Navegar fecha o painel primeiro: o `GoRouter` é capturado antes do `pop`
  /// porque depois dele o contexto do diálogo já não serve para navegar.
  void _ir(BuildContext context, String caminho) {
    final roteador = GoRouter.of(context);
    Navigator.of(context).pop();
    roteador.go(caminho);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendencia = ref.watch(pendenciaProvider(pendenciaId));
    if (pendencia == null) {
      return const PainelDetalhe(
        titulo: 'Pendência',
        subtitulo: 'Já não está aberta',
        acoes: [],
        filho: EstadoVazio(
          mensagem: pendenciaSumiu,
          icone: Icons.check_circle_outline,
        ),
      );
    }

    final automatico = fechamentoAutomatico(pendencia.tipo);
    final ehVirada =
        pendencia.tipo == 'REP_VIRADA' && pendencia.sentido != null;

    return PainelDetalhe(
      titulo: rotuloTipoPendencia(pendencia.tipo),
      subtitulo:
          '${rotuloSeveridade(pendencia.severidade)} · aberta '
          '${rotuloIdade(pendencia.diasAberta)} '
          '(${formatarData(pendencia.criadoEm)})',
      acoes: [Severidade(pendencia.severidade)],
      filho: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinhaDetalhe(rotulo: 'Descrição', valor: pendencia.descricao),
          LinhaDetalhe(rotulo: 'Referência', valor: pendencia.referencia),
          if (pendencia.referenciaOculta) ...[
            const AvisoTonal(mensagem: avisoReferenciaOculta),
            const SizedBox(height: Dim.e16),
          ],
          if (automatico != null) ...[
            AvisoTonal(mensagem: automatico),
            const SizedBox(height: Dim.e16),
          ],
          if (ehVirada) _BlocoVirada(pendencia: pendencia),
          const SizedBox(height: Dim.e8),
          Wrap(
            spacing: Dim.e8,
            runSpacing: Dim.e8,
            children: [
              if (ehVirada)
                BotaoAcao(
                  rotulo: 'Executar',
                  icone: Icons.play_arrow_outlined,
                  exigePermissao: 'turmas.alocar',
                  aoTocar: () => _executar(context, pendencia),
                )
              else
                _AcaoContextual(
                  pendencia: pendencia,
                  aoIr: (caminho) => _ir(context, caminho),
                ),
              BotaoAcao(
                rotulo: 'Resolver',
                icone: Icons.check,
                nivel: ehVirada ? NivelBotao.secundario : NivelBotao.primario,
                exigePermissao: 'pendencias.resolver',
                aoTocar: () => _fechar(context, pendencia, resolucaoResolvida),
              ),
              BotaoAcao(
                rotulo: 'Ignorar',
                nivel: NivelBotao.terciario,
                exigePermissao: 'pendencias.resolver',
                aoTocar: () => _fechar(context, pendencia, resolucaoIgnorada),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const pendenciaSumiu =
    'Esta pendência já foi encerrada — por outra pessoa, ou pela rotina, quando '
    'a condição deixou de valer.';

/// ⚠️ Referência que o leitor não alcança é `—` na lista, e aqui é uma frase.
/// Sem ela, "—" pareceria dado faltando no banco em vez de permissão faltando
/// no perfil — e a pendência continua sendo verdadeira e resolvível por quem
/// enxerga o outro lado (card 2.3 §9).
const avisoReferenciaOculta =
    'Esta pendência aponta para um registro que o seu perfil não pode ler. Ela '
    'continua valendo — quem tiver a permissão de leitura correspondente vê de '
    'quem se trata.';

/// A ação primária do tipo (wireframe §14.3), quando há para onde ir.
///
/// **Não é renderizada** quando a referência não chegou (RLS) ou quando o
/// usuário não abre a tela de destino: oferecer o que vai falhar é o que o card
/// 4.4 (d) recusa, e um botão que leva a "Sem acesso" ensina a não clicar nos
/// outros. `ROTINA_FALHOU` não tem destino de propósito — o detalhe técnico já
/// está na descrição, e é para a direção.
class _AcaoContextual extends ConsumerWidget {
  const _AcaoContextual({required this.pendencia, required this.aoIr});

  final Pendencia pendencia;
  final void Function(String caminho) aoIr;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acao = acaoDe(pendencia.tipo);
    final rotaId = rotaDaAcao(acao);
    if (rotaId == null || !referenciaDaAcaoPresente(pendencia)) {
      return const SizedBox.shrink();
    }

    Rota? destino;
    for (final rota in rotasAplicacao) {
      if (rota.id == rotaId) destino = rota;
    }
    if (destino == null || !podeAbrir(destino, ref.watch(permissoesProvider))) {
      return const SizedBox.shrink();
    }

    final caminho = acao == AcaoPendencia.verAluno
        ? caminhoFichaAluno(pendencia.alunoId!)
        : destino.caminho;

    return BotaoAcao(
      rotulo: rotuloAcao(acao),
      icone: Icons.arrow_forward,
      aoTocar: () => aoIr(caminho),
    );
  }
}

/// O bloco do `REP_VIRADA`: os números do critério do card 2.5 e as reposições
/// **previstas** do aluno, com a marcação de presença.
///
/// A situação vem de `fn_rep_situacao` — a mesma frase da aba Turmas da ficha,
/// escrita uma vez em `turmas.dart`. Marcar presença chama
/// `fn_reposicao_registrar`, que devolve o **veredito** recalculado: é o que
/// permite quitar o débito aqui mesmo e ver, na hora, que a virada deixou de ser
/// sugerida — em vez de esperar a rotina das 03:10 fechar a pendência.
class _BlocoVirada extends ConsumerWidget {
  const _BlocoVirada({required this.pendencia});

  final Pendencia pendencia;

  Future<void> _registrar(
    BuildContext context,
    WidgetRef ref,
    ReposicaoAluno reposicao, {
    required bool veio,
  }) async {
    final veredito = await ref
        .read(turmasRepositorioProvider)
        .registrarReposicao(reposicao.id, veio: veio);
    recarregarTurmas(ref);
    recarregarPendencias(ref);
    if (!context.mounted) return;

    // Resultado que muda a próxima ação é diálogo, nunca snackbar (card 2.7 f):
    // o veredito é o que diz se ainda há uma virada a decidir.
    final aviso = avisoVeredito(veredito);
    await showDialog<void>(
      context: context,
      builder: (contexto) => AlertDialog(
        title: Text(veio ? 'Presença registrada' : 'Falta registrada'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(aviso ?? avisoVereditoManter, style: Tipografia.corpo),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(contexto).pop(),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A aba Turmas da ficha faz o mesmo recorte, e pelo mesmo motivo: sem
    // `turmas.ler` a situação e as reposições viriam vazias, e "nenhuma
    // reposição prevista" seria indistinguível de "você não pode ver".
    if (!ref.watch(permissoesProvider).contains('turmas.ler')) {
      return const Padding(
        padding: EdgeInsets.only(bottom: Dim.e16),
        child: AvisoTonal(mensagem: avisoSemTurmasLer),
      );
    }

    final alunoId = pendencia.alunoId!;
    final situacao = ref.watch(situacaoRepProvider(alunoId)).value;
    final reposicoes = ref.watch(reposicoesAlunoProvider(alunoId)).value;
    final previstas = [
      for (final r in reposicoes ?? const <ReposicaoAluno>[])
        if (r.prevista) r,
    ]..sort((a, b) => a.data.compareTo(b.data));
    final blocos = ref.watch(blocosPorIdProvider);
    final hoje = soData(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TituloSecao(
          texto: 'Situação de reposição',
          apoio:
              'O débito de aulas cabe no prazo, ou a reposição '
              'vira contínua? A decisão é sua — o sistema só sugere.',
        ),
        if (situacao == null)
          const EstadoCarregando(linhas: 1)
        else
          Text(
            resumoSituacaoRep(situacao).join(' · '),
            style: Tipografia.corpoTabela,
          ),
        const SizedBox(height: Dim.e24),
        const TituloSecao(
          texto: 'Reposições previstas',
          apoio:
              'Marcar presença é o que quita a aula em aberto — e o que pode '
              'fazer a virada deixar de ser sugerida.',
        ),
        if (previstas.isEmpty)
          Text(
            semReposicaoPrevista,
            style: Tipografia.apoio.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final reposicao in previstas)
            _LinhaReposicao(
              reposicao: reposicao,
              rotuloDoBloco: () {
                final bloco = blocos[reposicao.blocoId];
                return bloco == null
                    ? '—'
                    : rotuloBloco(bloco.diaSemana, bloco.horaInicio);
              }(),
              futura: reposicao.data.isAfter(hoje),
              aoRegistrar: (veio) =>
                  _registrar(context, ref, reposicao, veio: veio),
            ),
        const SizedBox(height: Dim.e16),
      ],
    );
  }
}

const avisoVereditoManter =
    'A reposição foi registrada. A situação do débito continua como estava — '
    'a sugestão desta pendência não mudou.';

const avisoSemTurmasLer =
    'Esta pendência é sobre reposição, e o seu perfil não lê turmas. Os números '
    'do débito e as reposições previstas só aparecem para quem pode ver '
    'turmas. Peça essa permissão a quem administra o acesso.';

const semReposicaoPrevista =
    'Nenhuma reposição prevista para este aluno. As aulas em aberto continuam '
    'pesando no prazo até alguém remarcá-las pela grade.';

class _LinhaReposicao extends StatelessWidget {
  const _LinhaReposicao({
    required this.reposicao,
    required this.rotuloDoBloco,
    required this.futura,
    required this.aoRegistrar,
  });

  final ReposicaoAluno reposicao;
  final String rotuloDoBloco;
  final bool futura;
  final void Function(bool veio) aoRegistrar;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Dim.e8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${formatarData(reposicao.data)} · $rotuloDoBloco',
                  style: Tipografia.numero(Tipografia.corpoTabela),
                ),
                Text(
                  [
                    if (reposicao.dataOrigem != null)
                      'aula perdida em '
                          '${formatarData(reposicao.dataOrigem!)}'
                    else
                      'origem não informada',
                    // Marcar presença numa aula que ainda não aconteceu é
                    // possível e quase sempre engano — a linha diz isso em vez
                    // de esconder os botões, porque a escola remarca e antecipa.
                    if (futura) 'ainda vai acontecer',
                  ].join(' · '),
                  style: Tipografia.apoio.copyWith(
                    color: futura ? cores.tertiary : cores.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Dim.e8),
          BotaoAcao(
            rotulo: 'Veio',
            nivel: NivelBotao.secundario,
            exigePermissao: 'turmas.alocar',
            aoTocar: () => aoRegistrar(true),
          ),
          const SizedBox(width: Dim.e8),
          BotaoAcao(
            rotulo: 'Faltou',
            nivel: NivelBotao.terciario,
            exigePermissao: 'turmas.alocar',
            aoTocar: () => aoRegistrar(false),
          ),
        ],
      ),
    );
  }
}
