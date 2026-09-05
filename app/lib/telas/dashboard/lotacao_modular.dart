import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../dashboard/dashboard.dart';
import '../../dashboard/dashboard_provider.dart';
import '../../rotas/rotas.dart';
import '../../theme/cores.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../turmas/modular.dart';
import '../../turmas/modular_provider.dart';
import '../../widgets/card_dashboard.dart';
import '../../widgets/estados.dart';

/// A região "Lotação Modular" do wireframe §5 — card 7.4.
///
/// **Consumidor, não criador:** este card não cria objeto de banco nenhum. A
/// fonte é `v_turma_modular_lotacao`, que nasceu no card 7.3 junto com a tela 5
/// (docs/views-leitura.md §7.2 e §12), e aqui as turmas ativas são **somadas
/// por curso** — que é a leitura equivalente às vagas fixas do Dashboard da
/// planilha.
///
/// ⚠️ **Erro aqui não vira zero**, pela mesma razão das pendências abertas: uma
/// região do dashboard é um número reportado, e "0 ocupados" por falha de
/// leitura faz a direção ler *"as turmas estão vazias"* quando ninguém sabe. A
/// região mostra a frase de erro no lugar dos números, e nunca some — a regra do
/// design-system §7.2 para o dashboard é *região mostra zero real, nunca some*,
/// e o erro e o carregamento moram **dentro** do slot.
class LotacaoModular extends ConsumerWidget {
  const LotacaoModular({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cores = Theme.of(context).colorScheme;
    final turmas = ref.watch(turmasModularProvider);
    final cursos = ref.watch(lotacaoModularProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                tituloLotacaoModular,
                overflow: TextOverflow.ellipsis,
                style: Tipografia.subtitulo,
              ),
            ),
            // A rota da tela 5 exige `turmas.ler` + `salas.ler` +
            // `materiais.ler`, que é subconjunto do que a rota do dashboard já
            // exige: este atalho, ao contrário do de Turmas, nunca leva a
            // "Sem acesso".
            TextButton(
              onPressed: () => context.go(_rotaModular.caminho),
              child: const Text('Ver turmas'),
            ),
          ],
        ),
        const SizedBox(height: Dim.e4),
        // ⚠️ A pergunta é `hasError` antes de `hasValue`, e não um
        // `case AsyncError()`: é o contrato que o design-system §5.6 fixou
        // depois de a repetição automática do Riverpod 3 fazer a mensagem
        // piscar e a região terminar em "Carregando…" para sempre.
        // ⚠️ Era texto: "Carregando…" no lugar do esqueleto que o §5.6 pede,
        // e a mensagem de erro **sem "Tentar de novo"** — a região de vagas da
        // mesma tela já fazia os dois. Sem a saída, a única forma de repetir a
        // leitura era recarregar a página (item D1).
        if (turmas.hasError)
          EstadoErro(
            mensagem: erroLotacaoModular,
            aoRepetir: ref.read(versaoModularProvider.notifier).incrementar,
          )
        else if (!turmas.hasValue)
          const EstadoCarregando(linhas: 2)
        else if (cursos.isEmpty)
          // A região **diz** por que não há número, em vez de sumir: espaço em
          // branco no dashboard parece defeito.
          Text(
            vazioLotacaoModular,
            style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
          )
        else
          _Cartoes(cursos: cursos),
      ],
    );
  }
}

const tituloLotacaoModular = 'Lotação Modular';

/// O texto que substitui os números quando a leitura falha — nunca um zero.
const erroLotacaoModular =
    'Não foi possível ler a lotação das turmas Modular agora. Abra Turmas '
    'Modular para conferir.';

/// Sem turma ativa nenhuma. A tela 5 é onde se cria uma, e é para lá que o
/// cabeçalho da região já aponta — por isso a frase não repete o botão.
const vazioLotacaoModular =
    'Nenhuma turma Modular ativa — não há lotação a mostrar.';

class _Cartoes extends ConsumerWidget {
  const _Cartoes({required this.cursos});

  final List<LotacaoCurso> cursos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, restricoes) {
        // No mobile os cartões **empilham** e ocupam a linha (design-system
        // §3): dois cartões de 200 px lado a lado numa tela de 430 px é o
        // oposto da regra.
        final mobile = faixaDe(restricoes.maxWidth) == Faixa.mobile;
        final cartoes = [
          for (final curso in cursos)
            _CartaoCurso(
              curso: curso,
              largura: mobile ? null : larguraCardDashboard,
              // Toda célula/número do dashboard é atalho (wireframes §3.3). O
              // cartão é de um CURSO, então o destino é a tela 5 **filtrada
              // por ele** — divergência registrada com o §5, que escreve "a
              // linha Modular abre a turma": com as turmas somadas por curso
              // não existe uma turma a abrir, e um curso com três turmas teria
              // de eleger uma delas em silêncio.
              aoTocar: () {
                ref
                    .read(filtroTurmasModularProvider.notifier)
                    .definir(FiltroTurmasModular(cursoId: curso.cursoId));
                context.go(_rotaModular.caminho);
              },
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
}

class _CartaoCurso extends StatelessWidget {
  const _CartaoCurso({required this.curso, this.largura, this.aoTocar});

  final LotacaoCurso curso;
  final double? largura;
  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final atencao = tema.brightness == Brightness.dark
        ? Cores.atencaoEscuro
        : Cores.atencao;

    return CardDashboard(
      largura: largura,
      aoTocar: aoTocar,
      semantica: descricaoLotacaoCurso(curso),
      filho: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            curso.cursoNome,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Tipografia.badge.copyWith(color: cores.onSurfaceVariant),
          ),
          const SizedBox(height: Dim.e4),
          Text(
            '${curso.vagasLivres}',
            style: Tipografia.numero(Tipografia.titulo),
          ),
          Text(
            curso.vagasLivres == 1 ? 'vaga livre' : 'vagas livres',
            style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
          ),
          const SizedBox(height: Dim.e8),
          Text(
            // "1 de 45 ocupados", e não "1/45": a grade de vagas desta mesma
            // tela diz `n/m` com `n` sendo VAGA — a leitura oposta.
            '${curso.ocupacaoPorExtenso} · ${curso.turmasTexto}',
            style: Tipografia.numero(Tipografia.apoio),
          ),
          if (curso.temAlerta)
            _LinhaAlerta(
              texto: curso.acimaTexto,
              cor: cores.error,
              icone: Icons.warning_amber_rounded,
            ),
          if (curso.temAtraso)
            _LinhaAlerta(
              // Atraso é **âmbar**, não vermelho: a turma continua funcionando
              // e o que venceu foi a previsão do módulo. O vermelho fica para a
              // turma acima da capacidade, que é dado inconsistente.
              texto: curso.atrasoTexto,
              cor: atencao,
              icone: Icons.schedule_outlined,
            ),
        ],
      ),
    );
  }
}

/// Cor nunca é portador único (design-system §8.2): o alerta é ícone + texto.
class _LinhaAlerta extends StatelessWidget {
  const _LinhaAlerta({
    required this.texto,
    required this.cor,
    required this.icone,
  });

  final String texto;
  final Color cor;
  final IconData icone;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icone, size: 14, color: cor),
      const SizedBox(width: Dim.e4),
      Flexible(
        child: Text(texto, style: Tipografia.apoio.copyWith(color: cor)),
      ),
    ],
  );
}

Rota get _rotaModular =>
    rotasAplicacao.firstWhere((rota) => rota.id == 'turmas_modular');
