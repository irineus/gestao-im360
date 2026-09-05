import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../alunos/alunos.dart';
import '../../alunos/alunos_provider.dart';
import '../../dashboard/dashboard.dart';
import '../../dashboard/dashboard_provider.dart';
import '../../rotas/rotas.dart';
import '../../sessao/sessao_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../widgets/card_dashboard.dart';
import '../../widgets/estados.dart';

/// A região "cards por método" do wireframe §5 — card 8.7, e o primeiro
/// consumidor de `v_dashboard_alunos_metodo` e `v_dashboard_tipos_bloco`.
///
/// É o equivalente melhorado do Dashboard da planilha: por método, quantos
/// alunos estão em cada situação, quantos estão recebendo a última apostila e
/// quantos ainda não têm previsão de conclusão — mais os totais REM/PRE/REP/NOVO
/// na linha secundária, que é como a secretaria dimensiona as turmas.
///
/// ⚠️ **Os números chegam prontos do banco.** Nada aqui conta aluno a partir de
/// uma lista: o card 2.3 §4.1 proíbe a segunda implementação, e neste caso ela
/// seria pior que o normal — a lista que a tela de Alunos carrega passa pela
/// RLS e por filtros de tela, então uma contagem feita dela viria menor **sem
/// erro nenhum**, com o dashboard afirmando que a escola encolheu.
///
/// ⚠️ **Erro aqui não vira zero**, como na lotação Modular e nas pendências: uma
/// região do dashboard é um número reportado, e "0 ativos" por falha de leitura
/// faz a direção ler o que ninguém mediu. O erro e o carregamento moram
/// **dentro** do slot da região, e a região nunca some (design-system §7.2).
class CartoesAlunos extends ConsumerWidget {
  const CartoesAlunos({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cores = Theme.of(context).colorScheme;
    final alunos = ref.watch(alunosPorMetodoProvider);
    final tipos = ref.watch(tiposPorBlocoProvider);
    final paineis = ref.watch(paineisMetodoProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tituloAlunosPorMetodo, style: Tipografia.subtitulo),
        const SizedBox(height: Dim.e4),
        // ⚠️ `hasError` antes de `hasValue` (design-system §5.6): casar pela
        // classe faz a mensagem piscar e a região terminar em "Carregando…".
        if (alunos.hasError)
          EstadoErro(
            mensagem: erroAlunosPorMetodo,
            aoRepetir: () => ref.invalidate(alunosPorMetodoProvider),
          )
        else if (!alunos.hasValue)
          const EstadoCarregando(linhas: 3)
        else if (paineis.isEmpty)
          // A região **diz** por que não há número, em vez de sumir: espaço em
          // branco no dashboard parece defeito.
          Text(
            vazioAlunosPorMetodo,
            style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
          )
        else ...[
          // A legenda vale para a linha REM/PRE/REP/NOVO de todos os cartões, e
          // por isso aparece uma vez na região — repeti-la em cada cartão
          // gastaria três linhas para dizer a mesma coisa. Sem ela, a soma
          // parece contagem de gente e não bate com os ativos logo acima
          // (docs/views-leitura.md §8.3).
          if (tipos.hasValue && paineis.any((p) => p.tipos != null))
            Text(
              legendaAlocacoes,
              style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
            ),
          const SizedBox(height: Dim.e12),
          _Cartoes(paineis: paineis),
        ],
      ],
    );
  }
}

const tituloAlunosPorMetodo = 'Alunos por método';

/// Substitui os números quando a leitura falha — nunca um zero.
const erroAlunosPorMetodo =
    'Não foi possível ler os alunos por método agora. Abra Alunos para '
    'conferir.';

/// Sem nenhum aluno cadastrado. A tela de Alunos é onde se matricula o
/// primeiro, e é para lá que o cartão levaria — por isso a frase aponta o
/// caminho em vez de repetir um botão.
const vazioAlunosPorMetodo =
    'Nenhum aluno cadastrado — matricule o primeiro em Alunos.';

/// A legenda obrigatória da linha de tipos (wireframes §5).
const legendaAlocacoes =
    'REM, PRE, REP e NOVO contam alocações em turma, não alunos: quem está em '
    'aceleração ocupa dois horários e conta duas vezes.';

class _Cartoes extends StatelessWidget {
  const _Cartoes({required this.paineis});

  final List<PainelMetodo> paineis;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, restricoes) {
      // No mobile os cartões **empilham** e ocupam a linha (design-system §3 e
      // wireframes §5): a largura fixa do desktop punha dois lado a lado numa
      // tela de 430 px, com o número colado na borda.
      final mobile = faixaDe(restricoes.maxWidth) == Faixa.mobile;
      final cartoes = [
        for (final painel in paineis)
          _CartaoAlunos(
            painel: painel,
            largura: mobile ? null : larguraCardDashboard,
          ),
      ];

      return mobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final cartao in cartoes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Dim.e12),
                    child: cartao,
                  ),
              ],
            )
          : Wrap(spacing: Dim.e12, runSpacing: Dim.e12, children: cartoes);
    },
  );
}

class _CartaoAlunos extends ConsumerWidget {
  const _CartaoAlunos({required this.painel, this.largura});

  final PainelMetodo painel;
  final double? largura;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cores = Theme.of(context).colorScheme;
    final a = painel.alunos;
    final tipos = painel.tipos;
    final permissoes = ref.watch(permissoesProvider);
    final podeVerCertificados = podeAbrir(_rotaCertificados, permissoes);

    void abrirAlunos({String? status}) {
      ref
          .read(filtroAlunosProvider.notifier)
          .definir(
            FiltroAlunos(
              metodoId: a.metodoId,
              status: status,
              // Sem ocultar os encerrados quando o próprio número é de um
              // status terminal: o atalho tem de mostrar exatamente os alunos
              // que ele acabou de contar, e a lista abre com "ocultar formados
              // e cancelados" ligada por padrão (card 4.4).
              ocultarEncerrados: status == null,
            ),
          );
      context.go(_rotaAlunos.caminho);
    }

    return CardDashboard(
      largura: largura,
      // ⚠️ O cartão inteiro NÃO é o alvo aqui, ao contrário dos de vaga e de
      // lotação: cada número tem destino próprio (wireframes §3.3 — "o 9
      // standby abre Alunos filtrado"), e um alvo por cima de outro deixaria a
      // pessoa sem saber qual dos dois pegou o toque. Quem quer a lista inteira
      // do método toca no nome dele, na primeira linha.
      alvosInternos: true,
      semantica: descricaoAlunosMetodo(painel),
      filho: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Alvo(
            rotulo: '${a.metodoCodigo}, ver todos os alunos do método',
            aoTocar: abrirAlunos,
            filho: Text(
              a.metodoCodigo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Tipografia.badge.copyWith(color: cores.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: Dim.e4),
          _Alvo(
            rotulo:
                '${a.ativos} ${a.ativos == 1 ? 'ativo' : 'ativos'}, '
                'abrir a lista',
            aoTocar: () => abrirAlunos(status: 'ATIVO'),
            filho: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${a.ativos}',
                  style: Tipografia.numero(Tipografia.titulo),
                ),
                Text(
                  a.ativos == 1 ? 'ativo' : 'ativos',
                  style: Tipografia.apoio.copyWith(
                    color: cores.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Dim.e8),
          // ⚠️ Zero real continua na tela, nunca some (design-system §7.2):
          // "0 em standby" é informação, e uma linha que desaparece tira a
          // referência de comparação entre um dia e o outro.
          _LinhaNumero(
            texto: '${a.acelerar} em aceleração',
            aoTocar: () => abrirAlunos(status: 'ACELERAR'),
          ),
          _LinhaNumero(
            texto: '${a.standby} em standby',
            aoTocar: () => abrirAlunos(status: 'STANDBY'),
          ),
          _LinhaNumero(
            texto:
                '${a.trancados} ${a.trancados == 1 ? 'trancado' : 'trancados'}',
            aoTocar: () => abrirAlunos(status: 'TRANCADO'),
          ),
          // ⚠️ `em_ultimo_livro` (UM item pendente), e **não** `em_fim`: são
          // leituras diferentes que o plano chama pelo mesmo nome, e é esta
          // que dá tempo de pedir o certificado (docs/views-leitura.md §8.1).
          _LinhaNumero(
            texto: '${a.emUltimoLivro} no último livro',
            // A fila de quem está chegando ao fim é a tela de Certificados —
            // mas a rota dela pede uma permissão que a desta não pede, e botão
            // que leva a "Sem acesso" ensina a não clicar nos outros (card 5.8).
            aoTocar: podeVerCertificados
                ? () => context.go(_rotaCertificados.caminho)
                : null,
          ),
          // Sem atalho: não há filtro de "sem previsão" na lista de alunos, e
          // inventar um aqui seria uma tela prometendo o que a outra não faz. O
          // número existe para a conta das conclusões fechar — a explicação
          // está na região logo abaixo.
          _LinhaNumero(texto: '${a.semPrevisao} sem previsão de conclusão'),
          if (tipos != null) ...[
            const SizedBox(height: Dim.e8),
            Text(tipos.resumo, style: Tipografia.numero(Tipografia.apoio)),
          ],
        ],
      ),
    );
  }
}

/// Uma linha de número secundário, com ou sem destino.
class _LinhaNumero extends StatelessWidget {
  const _LinhaNumero({required this.texto, this.aoTocar});

  final String texto;
  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final destino = aoTocar;
    final conteudo = Text(
      texto,
      style: Tipografia.numero(Tipografia.apoio)
          .copyWith(color: destino == null ? cores.onSurfaceVariant : null),
    );
    return destino == null
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: Dim.e4),
            child: conteudo,
          )
        : _Alvo(
            rotulo: '$texto, abrir a lista',
            aoTocar: destino,
            filho: conteudo,
          );
  }
}

/// Um alvo de toque dentro do cartão, com o rótulo que a leitura de tela
/// anuncia. O `Semantics` é próprio porque o cartão está em `alvosInternos`:
/// sem ele o número seria lido sem dizer que dá para abrir a lista dali.
class _Alvo extends StatelessWidget {
  const _Alvo({
    required this.rotulo,
    required this.aoTocar,
    required this.filho,
  });

  final String rotulo;
  final VoidCallback aoTocar;
  final Widget filho;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: rotulo,
    excludeSemantics: true,
    child: InkWell(
      onTap: aoTocar,
      borderRadius: BorderRadius.circular(Dim.raioBadge),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Dim.e4),
        child: filho,
      ),
    ),
  );
}

Rota get _rotaAlunos =>
    rotasAplicacao.firstWhere((rota) => rota.id == 'alunos');

Rota get _rotaCertificados =>
    rotasAplicacao.firstWhere((rota) => rota.id == 'certificados');
