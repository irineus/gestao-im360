import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../erros/erro_app.dart';
import '../../rotas/rotas.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../turmas/turmas.dart';
import '../../turmas/turmas_provider.dart';
import '../../widgets/badge_status.dart';
import '../../widgets/badge_tipo.dart';
import '../../widgets/botoes.dart';
import '../../widgets/confirmacao.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';
import '../../widgets/painel_detalhe.dart';
import 'formularios.dart';
import 'formularios_alocacao.dart';

/// A lista de alunos de um bloco numa data — tela 4b do wireframe (§7.2),
/// card 5.7. Abre do clique na célula da grade, e é a célula que dá a **data**:
/// a alocação vale toda semana, a reposição vale só no dia (card 2.1 §8), então
/// "os alunos do bloco" só existe com uma data ao lado.
///
/// A tela **orquestra** as funções do card 5.3 e não reescreve regra nenhuma: a
/// vaga é conferida por `tg_bloco_aluno_admissao` com o advisory lock, o
/// `BLOCO_LOTADO` chega traduzido pelo código, e o veredito da virada REP vem de
/// `fn_reposicao_registrar`. O que há aqui de decisão é o que **não** oferecer —
/// sem `turmas.alocar` os botões não são renderizados (card 2.6 decisão 1).
class PainelBloco extends ConsumerWidget {
  const PainelBloco({super.key, required this.celula});

  final CelulaGrade celula;

  Future<void> _adicionar(BuildContext context) async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) => FormularioAdicionarAluno(celula: celula),
    );
    if (resultado != null && context.mounted) {
      confirmarEfemero(context, 'Aluno adicionado à turma.');
    }
  }

  Future<void> _lancarReposicao(BuildContext context) async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) => FormularioLancarReposicao(celula: celula),
    );
    if (resultado != null && context.mounted) {
      confirmarEfemero(context, 'Reposição lançada.');
    }
  }

  /// Editar o bloco fecha o painel devolvendo o resultado: quem abriu é a
  /// grade, e é ela que mostra a confirmação e recarrega — o painel podia estar
  /// descrevendo um bloco que acabou de ser excluído.
  Future<void> _editar(BuildContext context) async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) => FormularioBloco(bloco: celula.bloco, celula: celula),
    );
    if (resultado != null && context.mounted) {
      Navigator.of(context).pop(resultado);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chave = BlocoNaData(celula.blocoId, celula.dataReferencia);
    final lista = ref.watch(alunosDoBlocoProvider(chave));

    final cabecalho = [
      rotuloBloco(celula.diaSemana, celula.horaInicio),
      celula.metodoCodigo,
      celula.salaNome,
      celula.professorNome ?? 'sem professor',
    ].join(' · ');

    return PainelDetalhe(
      titulo: cabecalho,
      // A ocupação sai da LISTA e não da célula: a célula é a grade de quando o
      // painel abriu, e depois de adicionar alguém ela mentiria por um número.
      subtitulo: lista.hasValue
          ? '${resumoLotacao(lista.requireValue, capacidade: celula.capacidade)}'
                ' · ${formatarData(celula.dataReferencia)}'
          : 'Lotação de ${formatarData(celula.dataReferencia)}',
      acoes: [
        BotaoAcao(
          rotulo: 'Editar bloco',
          nivel: NivelBotao.terciario,
          exigePermissao: 'turmas.editar',
          aoTocar: () => _editar(context),
        ),
      ],
      filho: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (celula.acimaCapacidade)
            const Padding(
              padding: EdgeInsets.only(bottom: Dim.e16),
              child: AvisoTonal(mensagem: avisoAcimaCapacidade, erro: true),
            ),
          lista.when(
            loading: () => const EstadoCarregando(linhas: 4),
            error: (erro, _) {
              final traduzido = erro is ErroApp ? erro : traduzirErro(erro);
              return EstadoErro(
                mensagem: traduzido.mensagem,
                codigoTecnico: traduzido.traduzido ? null : traduzido.codigo,
                aoRepetir: ref.read(versaoTurmasProvider.notifier).incrementar,
              );
            },
            data: (alunos) => alunos.isEmpty
                ? const EstadoVazio(
                    mensagem: vazioBloco,
                    icone: Icons.person_outline,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final aluno in alunos)
                        _LinhaAluno(aluno: aluno, celula: celula),
                    ],
                  ),
          ),
          const SizedBox(height: Dim.e16),
          Wrap(
            spacing: Dim.e8,
            runSpacing: Dim.e8,
            children: [
              BotaoAcao(
                rotulo: 'Adicionar aluno',
                icone: Icons.person_add_alt_1_outlined,
                exigePermissao: 'turmas.alocar',
                aoTocar: () => _adicionar(context),
              ),
              BotaoAcao(
                rotulo: 'Lançar reposição',
                icone: Icons.event_repeat_outlined,
                nivel: NivelBotao.secundario,
                exigePermissao: 'turmas.alocar',
                aoTocar: () => _lancarReposicao(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const vazioBloco = 'Nenhum aluno neste bloco nesta data.';

const avisoAcimaCapacidade =
    'Este bloco está acima da capacidade. Novas admissões estão bloqueadas até '
    'normalizar — remova alguém, aumente a capacidade manual ou devolva um PC à '
    'operação.';

/// Uma linha da lista: nome, badge do tipo, "desde", e a ação que cabe àquela
/// metade do REP híbrido — remover (alocação) ou desmarcar (reposição).
class _LinhaAluno extends ConsumerWidget {
  const _LinhaAluno({required this.aluno, required this.celula});

  final AlunoDoBloco aluno;
  final CelulaGrade celula;

  Future<void> _remover(BuildContext context) async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) => FormularioRemoverAluno(aluno: aluno, celula: celula),
    );
    if (resultado != null && context.mounted) {
      confirmarEfemero(
        context,
        aluno.ehReposicao ? 'Reposição desmarcada.' : 'Aluno removido.',
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cores = Theme.of(context).colorScheme;
    final apoio = <String>[
      if (aluno.codigoSgf != null) aluno.codigoSgf!,
      if (aluno.ehReposicao)
        aluno.rotuloReposicao!
      else if (aluno.tipoDesde != null)
        'desde ${formatarData(aluno.tipoDesde!)}',
      if (!aluno.ehReposicao &&
          aluno.tipo == 'NOVO' &&
          aluno.dataInicioPrevista != null)
        'início previsto ${formatarData(aluno.dataInicioPrevista!)}',
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: Dim.e8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: Dim.e8,
                  runSpacing: Dim.e4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // O nome leva à ficha: daqui se chega à Trilha, que é a
                    // jornada nº 1 do monitor (card 2.6 §3.2).
                    InkWell(
                      onTap: () => context.go(caminhoFichaAluno(aluno.alunoId)),
                      child: Text(
                        aluno.alunoNome,
                        style: Tipografia.rotulo.copyWith(
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    BadgeTipo(aluno.tipo),
                    if (aluno.ehReposicao)
                      Text(
                        'pontual',
                        style: Tipografia.apoio.copyWith(
                          color: cores.onSurfaceVariant,
                        ),
                      ),
                    // O status só aparece quando NÃO é o esperado: dez badges
                    // "ATIVO" iguais não informam nada e escondem o décimo
                    // primeiro, que é o que importa.
                    if (aluno.alunoStatus != 'ATIVO')
                      BadgeStatus(aluno.alunoStatus),
                  ],
                ),
                if (apoio.isNotEmpty)
                  Text(
                    apoio.join(' · '),
                    style: Tipografia.apoio.copyWith(
                      color: cores.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Dim.e8),
          BotaoAcao(
            rotulo: aluno.ehReposicao ? 'Desmarcar' : 'Remover',
            nivel: NivelBotao.terciario,
            exigePermissao: 'turmas.alocar',
            aoTocar: () => _remover(context),
          ),
        ],
      ),
    );
  }
}
