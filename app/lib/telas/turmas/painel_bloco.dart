import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../catalogo/catalogo.dart';
import '../../catalogo/catalogo_provider.dart';
import '../../erros/erro_app.dart';
import '../../pendencias/pendencias_provider.dart';
import '../../rotas/rotas.dart';
import '../../sessao/sessao_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../turmas/turmas.dart';
import '../../turmas/turmas_provider.dart';
import '../../turmas/turmas_widgets.dart';
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
///
/// **Marcar presença mora aqui** (revisão da fase 05, item A4): quem lançou a
/// reposição está nesta tela, e é aqui que ele vê se o aluno veio. Antes o
/// Veio/Faltou existia só na central de pendências, e o veredito da virada —
/// que o §7.2 manda mostrar "na mão de quem lançou" — nunca chegava a quem
/// lançou.
class PainelBloco extends ConsumerStatefulWidget {
  const PainelBloco({super.key, required this.celula});

  final CelulaGrade celula;

  @override
  ConsumerState<PainelBloco> createState() => _PainelBlocoState();
}

class _PainelBlocoState extends ConsumerState<PainelBloco> {
  /// O erro de marcar presença, no bloco — `registrarReposicao` é a única
  /// escrita desta tela que não passa por um `FormularioIm360`, então o banner
  /// dele é responsabilidade daqui (design-system §5.4).
  String? _erro;

  Future<void> _adicionar() async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) => FormularioAdicionarAluno(celula: widget.celula),
    );
    if (resultado != null && mounted) {
      confirmarEfemero(context, 'Aluno adicionado à turma.');
    }
  }

  Future<void> _lancarReposicao() async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) => FormularioLancarReposicao(celula: widget.celula),
    );
    if (resultado != null && mounted) {
      confirmarEfemero(context, 'Reposição lançada.');
    }
  }

  /// Editar o bloco fecha o painel devolvendo o resultado: quem abriu é a
  /// grade, e é ela que mostra a confirmação e recarrega — o painel podia estar
  /// descrevendo um bloco que acabou de ser excluído.
  Future<void> _editar() async {
    final resultado = await mostrarFormulario<String>(
      context,
      construtor: (_) =>
          FormularioBloco(bloco: widget.celula.bloco, celula: widget.celula),
    );
    if (resultado != null && mounted) {
      Navigator.of(context).pop(resultado);
    }
  }

  /// Veio / Faltou numa reposição do dia.
  ///
  /// ⚠️ Com `try/catch`: `REPOSICAO_NAO_PREVISTA` (alguém já marcou noutra
  /// aba), `SEM_PERMISSAO` e queda de rede são respostas esperadas, e sem isto
  /// viravam exceção crua — sem banner, e sem o gancho do Sentry ver o erro
  /// traduzido uma vez só (achado da revisão da fase 05, item A6).
  Future<void> _registrar(AlunoDoBloco aluno, {required bool veio}) async {
    setState(() => _erro = null);
    try {
      final veredito = await ref
          .read(turmasRepositorioProvider)
          .registrarReposicao(aluno.registroId, veio: veio);
      recarregarTurmas(ref);
      recarregarPendencias(ref);
      if (!mounted) return;
      await mostrarVeredito(context, veio: veio, veredito: veredito);
    } catch (erro) {
      final traduzido = erro is ErroApp ? erro : traduzirErro(erro);
      // A reposição já não está prevista: quem tem o dado certo é o banco, e a
      // lista precisa parar de oferecer o botão.
      if (traduzido.codigo == 'REPOSICAO_NAO_PREVISTA') recarregarTurmas(ref);
      if (mounted) setState(() => _erro = traduzido.mensagem);
    }
  }

  @override
  Widget build(BuildContext context) {
    final celula = widget.celula;
    final chave = BlocoNaData(celula.blocoId, celula.dataReferencia);
    final lista = ref.watch(alunosDoBlocoProvider(chave));

    // O nome do método, não o código: "Interativo" é como a escola o chama;
    // "INTERATIVO" é como o banco o guarda (wireframe §7.2).
    String nomeDoMetodo() {
      for (final m in ref.watch(metodosProvider).value ?? const <Metodo>[]) {
        if (m.id == celula.metodoId) return m.nome;
      }
      return celula.metodoCodigo;
    }

    final cabecalho = [
      rotuloBloco(celula.diaSemana, celula.horaInicio),
      nomeDoMetodo(),
      celula.salaNome,
      celula.professorNome ?? 'sem professor',
    ].join(' · ');

    // ⚠️ O banner sai da LISTA, não de `celula.acimaCapacidade`: a célula é o
    // retrato da grade de quando o painel abriu, e depois de remover o 11º
    // aluno ela continuaria dizendo que o bloco está estourado.
    final acima = lista.hasValue
        ? lista.requireValue.length > celula.capacidade
        : celula.acimaCapacidade;

    return PainelDetalhe(
      titulo: cabecalho,
      // A ocupação sai da LISTA e não da célula, pela mesma razão.
      subtitulo: lista.hasValue
          ? '${resumoLotacao(lista.requireValue, capacidade: celula.capacidade)}'
                ' · ${formatarData(celula.dataReferencia)}'
          : 'Lotação de ${formatarData(celula.dataReferencia)}',
      acoes: [
        BotaoAcao(
          rotulo: 'Editar bloco',
          nivel: NivelBotao.terciario,
          exigePermissao: 'turmas.editar',
          aoTocar: _editar,
        ),
      ],
      filho: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (acima)
            const Padding(
              padding: EdgeInsets.only(bottom: Dim.e16),
              child: AvisoTonal(mensagem: avisoAcimaCapacidade, erro: true),
            ),
          if (_erro != null) ...[
            AvisoTonal(mensagem: _erro!, erro: true),
            const SizedBox(height: Dim.e16),
          ],
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
                ? SizedBox(
                    height: _alturaVazio,
                    child: EstadoVazio(
                      mensagem: vazioBloco,
                      icone: Icons.person_outline,
                      rotuloAcao:
                          ref
                              .watch(permissoesProvider)
                              .contains('turmas.alocar')
                          ? '+ Adicionar aluno'
                          : null,
                      aoAgir: _adicionar,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final aluno in alunos)
                        _LinhaAluno(
                          aluno: aluno,
                          celula: celula,
                          aoRegistrar: (veio) => _registrar(aluno, veio: veio),
                        ),
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
                aoTocar: _adicionar,
              ),
              BotaoAcao(
                rotulo: 'Lançar reposição',
                icone: Icons.event_repeat_outlined,
                nivel: NivelBotao.secundario,
                exigePermissao: 'turmas.alocar',
                aoTocar: _lancarReposicao,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const vazioBloco = 'Nenhum aluno neste bloco nesta data.';

/// O estado vazio é centrado e vive dentro de uma coluna rolável: sem altura
/// ele tentaria ocupar o infinito.
const _alturaVazio = 260.0;

const avisoAcimaCapacidade =
    'Este bloco está acima da capacidade. Novas admissões estão bloqueadas até '
    'normalizar — remova alguém, aumente a capacidade manual ou devolva um PC à '
    'operação.';

/// Uma linha da lista: nome, badge do tipo, "desde", e a ação que cabe àquela
/// metade do REP híbrido — remover (alocação) ou, na reposição do dia, marcar
/// presença e desmarcar.
class _LinhaAluno extends ConsumerWidget {
  const _LinhaAluno({
    required this.aluno,
    required this.celula,
    required this.aoRegistrar,
  });

  final AlunoDoBloco aluno;
  final CelulaGrade celula;
  final void Function(bool veio) aoRegistrar;

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

    return LinhaTurma(
      titulo: aluno.alunoNome,
      // O nome leva à ficha: daqui se chega à Trilha, que é a jornada nº 1 do
      // monitor (card 2.6 §3.2).
      aoTocarTitulo: () => context.go(caminhoFichaAluno(aluno.alunoId)),
      badges: [
        BadgeTipo(aluno.tipo),
        if (aluno.ehReposicao)
          Text(
            'pontual',
            style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
          ),
        // O status só aparece quando NÃO é o esperado: dez badges "ATIVO"
        // iguais não informam nada e escondem o décimo primeiro, que é o que
        // importa.
        if (aluno.alunoStatus != 'ATIVO') BadgeStatus(aluno.alunoStatus),
      ],
      apoio: apoio.join(' · '),
      acao: Wrap(
        spacing: Dim.e8,
        children: [
          // Marcar presença é o que quita a aula em aberto — e é o que faz o
          // veredito da virada aparecer para quem lançou a reposição.
          if (aluno.ehReposicao) ...[
            BotaoAcao(
              rotulo: 'Veio',
              nivel: NivelBotao.secundario,
              exigePermissao: 'turmas.alocar',
              aoTocar: () => aoRegistrar(true),
            ),
            BotaoAcao(
              rotulo: 'Faltou',
              nivel: NivelBotao.terciario,
              exigePermissao: 'turmas.alocar',
              aoTocar: () => aoRegistrar(false),
            ),
          ],
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
