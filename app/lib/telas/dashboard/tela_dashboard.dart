import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../dashboard/dashboard_provider.dart';
import '../../erros/erro_app.dart';
import '../../rotas/rotas.dart';
import '../../sessao/sessao_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../turmas/turmas.dart';
import '../../turmas/turmas_provider.dart';
import '../../widgets/estados.dart';
import 'cartoes_metodo.dart';
import 'grade_vagas.dart';
import 'pendencias_abertas.dart';

/// Tela 2 — Dashboard, **versão 1** (docs/wireframes.md §5), card 5.9: vagas
/// livres por método e por dia/horário, na semana corrente.
///
/// **Este card é consumidor, não criador.** A fonte é `v_bloco_vagas_semana`,
/// entregue pelo card 5.6 junto com `fn_grade_semana`; a grade daqui é a mesma
/// conta em outra apresentação, e nada nesta tela recalcula capacidade,
/// ocupação ou vaga — o card 5.2 é o dono da fórmula (docs/views-leitura.md §7).
///
/// **Sem navegação de semanas, e isso é decisão.** A tela de Turmas (5.6) navega
/// porque é onde se monta a grade; o dashboard é o retrato de **hoje**, e a
/// semana dele é a que o banco fixa com `fn_hoje()`. Um segundo navegador de
/// semanas produziria duas telas quase idênticas paradas em semanas diferentes,
/// e a de baixo — com o rótulo "semana corrente" em cima — mentiria. Divergência
/// registrada com o `[semana ◄ atual ►]` que o wireframe §5 desenha no
/// cabeçalho; o resto do §5 diz "(semana corrente)", e a view do §7 só existe
/// nessa forma.
///
/// **As pendências abertas entram aqui, e não na fase 8** — divergência
/// registrada com a Nota do card, que as manda para lá junto com os cards de
/// aluno. Três razões: o ajuste que o card 5.8 deixou escrito para o 5.9; o
/// custo, que é zero (o shell já carrega `pendenciasProvider` em toda tela, para
/// o contador do menu); e o fato de que sem elas `pendencias.ler` ficaria no
/// conjunto mínimo desta rota **sem consumidor nenhum**, que é justamente o que
/// o card 2.4 (a) recusa.
///
/// **O que ainda não está aqui é do card 8.7** (alunos por método, conclusões
/// por semestre e tipos por bloco): as três `v_dashboard_*` são dele
/// (docs/views-leitura.md §12), e é por elas que `alunos.ler` segue no conjunto
/// mínimo sem consumidor até lá. A tela diz isso em rodapé em vez de deixar o
/// espaço vazio parecendo defeito.
class TelaDashboard extends ConsumerWidget {
  const TelaDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vagas = ref.watch(vagasSemanaProvider);
    final grade = ref.watch(gradeVagasProvider);
    final visivel = ref.watch(metodoVisivelProvider);
    final permissoes = ref.watch(permissoesProvider);
    final podeVerTurmas = podeAbrir(_rotaTurmas, permissoes);

    return vagas.when(
      loading: () => const EstadoCarregando(),
      error: (erro, _) {
        final traduzido = erro is ErroApp ? erro : traduzirErro(erro);
        return EstadoErro(
          mensagem: traduzido.mensagem,
          codigoTecnico: traduzido.traduzido ? null : traduzido.codigo,
          aoRepetir: () => ref.invalidate(vagasSemanaProvider),
        );
      },
      // A região sem dado **diz** por que não há número, e não some — a regra do
      // design-system §7.2 para o dashboard. Por isso o estado vazio substitui a
      // região de vagas, e não a tela: as pendências abertas continuam à vista
      // numa escola que ainda não tem bloco nenhum cadastrado.
      data: (linhas) => SingleChildScrollView(
        padding: const EdgeInsets.all(Dim.e16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (grade == null || visivel == null)
              SizedBox(
                height: _alturaVazio,
                child: EstadoVazio(
                  mensagem: vazioDashboard,
                  icone: Icons.grid_view_outlined,
                  rotuloAcao: podeVerTurmas ? 'Ir para Turmas' : null,
                  aoAgir: podeVerTurmas
                      ? () => context.go(_rotaTurmas.caminho)
                      : null,
                ),
              )
            else ...[
              _TituloSemana(segunda: grade.segunda, dias: grade.dias),
              const SizedBox(height: Dim.e12),
              const CartoesMetodo(),
              const SizedBox(height: Dim.e24),
              Text(
                'Vagas por dia e horário — ${visivel.metodoCodigo}',
                style: Tipografia.subtitulo,
              ),
              Text(
                textoUmMetodoPorVez,
                style: Tipografia.apoio.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Dim.e12),
              GradeVagas(
                grade: grade,
                // Toda célula do dashboard é atalho (wireframes §3.3), e o
                // destino desta é a grade de Turmas — mas só para quem pode
                // abri-la: botão que leva a "Sem acesso" ensina a não clicar
                // nos outros (card 5.8, decisão 1).
                aoTocarCelula: podeVerTurmas
                    ? (_, _) => _irParaTurmas(context, ref, visivel.metodoId)
                    : null,
              ),
            ],
            const SizedBox(height: Dim.e24),
            const Divider(),
            const SizedBox(height: Dim.e8),
            const PendenciasAbertas(),
            const SizedBox(height: Dim.e24),
            _NotaDoQueFalta(linhas: linhas.length),
          ],
        ),
      ),
    );
  }

  /// O atalho leva à **mesma** semana e ao **mesmo** método que se acabou de
  /// tocar: sem isso a grade de Turmas abriria na semana e nos filtros em que
  /// alguém a deixou (o estado sobrevive à navegação, card 5.6), e a pessoa
  /// procuraria na tela de destino a célula que clicou na de origem.
  void _irParaTurmas(BuildContext context, WidgetRef ref, String metodoId) {
    ref.read(semanaProvider.notifier).hoje();
    ref
        .read(filtroGradeProvider.notifier)
        .definir(FiltroGrade(metodoId: metodoId));
    context.go(_rotaTurmas.caminho);
  }
}

/// Estado vazio da tela (design-system §7.2). A regra daquela tabela para o
/// dashboard é *"região mostra zero real, nunca some — número que desaparece
/// parece erro"*, e ela vale nas duas escalas: método sem vaga nenhuma continua
/// no cartão com `0 vagas livres`, célula sem vaga continua com `0/10`, e só
/// quando não existe bloco nenhum é que a região passa a **dizer** por que não
/// há número — em vez de sumir.
const vazioDashboard =
    'Nenhum bloco de horário cadastrado — não há vaga a mostrar.';

/// O estado vazio é um componente centrado, e aqui ele vive dentro de uma
/// coluna rolável: sem altura ele tentaria ocupar o infinito.
const _alturaVazio = 260.0;

/// A frase que explica por que a grade é de um método por vez. Constante para a
/// tela e o teste lerem a mesma.
const textoUmMetodoPorVez =
    'Um método por vez: vaga de um método não serve a aluno de outro.';

Rota get _rotaTurmas =>
    rotasAplicacao.firstWhere((rota) => rota.id == 'turmas');

class _TituloSemana extends StatelessWidget {
  const _TituloSemana({required this.segunda, required this.dias});

  final DateTime segunda;
  final List<int> dias;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Vagas na semana', style: Tipografia.subtitulo),
        Text(
          // A data vem de `data_referencia`, isto é, do banco — e não do
          // relógio do aparelho (ver `segundaDaGrade`).
          '${rotuloSemana(segunda, incluiDomingo: dias.contains(7))} '
          '· semana corrente',
          style: Tipografia.numero(Tipografia.apoio)
              .copyWith(color: cores.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// O placeholder de tela inteira (`TelaEmConstrucao`) diz qual card entrega a
/// tela para não virar destino permanente (wireframes §18). Aqui a tela existe e
/// é **parcial**, então quem diz é esta linha — sem ela, a secretaria reporta
/// como defeito a metade que ainda não foi escrita (é o aviso que o marco 4.8
/// registrou nas Notas).
class _NotaDoQueFalta extends StatelessWidget {
  const _NotaDoQueFalta({required this.linhas});

  final int linhas;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: Dim.e8),
        Text(
          textoRestanteDoDashboard,
          style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
        ),
        Text(
          '$linhas ${linhas == 1 ? 'bloco ativo' : 'blocos ativos'} nesta '
          'semana.',
          style: Tipografia.numero(Tipografia.apoio)
              .copyWith(color: cores.onSurfaceVariant),
        ),
      ],
    );
  }
}

const textoRestanteDoDashboard =
    'Alunos por método, conclusões por semestre e tipos por bloco chegam numa '
    'próxima versão, junto com a lotação das turmas Modular.';
