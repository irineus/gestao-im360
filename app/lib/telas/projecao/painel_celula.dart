import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../erros/erro_app.dart';
import '../../projecao/projecao.dart';
import '../../projecao/projecao_provider.dart';
import '../../rotas/rotas.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../util/datas.dart';
import '../../widgets/estados.dart';
import '../../widgets/painel_detalhe.dart';

/// O drill-down do wireframe §11: **quais alunos** somam naquela célula e **por
/// qual degrau da cascata**.
///
/// ⚠️ Lê `v_projecao_aluno_detalhe` AO VIVO, e o total da grade é da rotina da
/// madrugada. Os dois podem divergir ao longo do dia — uma entrega registrada
/// hoje de manhã tira um aluno daqui sem mexer no total —, e o aviso no topo diz
/// isso antes de a diferença virar defeito reportado. O que **não** pode
/// divergir é a definição: o `mes` desta view é a mesma expressão do `group by`
/// da rotina, e a regra é a mesma coluna.
class PainelCelula extends ConsumerWidget {
  const PainelCelula({super.key, required this.celula});

  final CelulaPedida celula;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detalhe = ref.watch(detalheProjecaoProvider(celula));

    // Título e subtítulo saem do que foi lido, nunca de um palpite: enquanto a
    // leitura não voltou, o painel não afirma o nome do material.
    final linhas = detalhe.value ?? const <DetalheProjecao>[];
    final primeira = linhas.isEmpty ? null : linhas.first;
    final mes = celula.mes;

    final titulo = primeira == null
        ? 'Projeção do material'
        : '${primeira.codigo} — ${primeira.materialNome}';
    final subtitulo = [
      mes == null
          ? 'todos os meses do horizonte'
          : rotuloMes(mes, comAno: true),
      if (detalhe.hasValue)
        linhas.length == 1 ? '1 aluno' : '${linhas.length} alunos',
    ].join(' · ');

    return PainelDetalhe(
      titulo: titulo,
      subtitulo: subtitulo,
      acoes: const [],
      filho: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _AvisoAoVivo(),
          const SizedBox(height: Dim.e16),
          detalhe.when(
            loading: () => const EstadoCarregando(linhas: 4),
            error: (erro, _) {
              final traduzido = erro is ErroApp ? erro : traduzirErro(erro);
              return EstadoErro(
                mensagem: traduzido.mensagem,
                codigoTecnico: traduzido.traduzido ? null : traduzido.codigo,
                aoRepetir: ref
                    .read(versaoProjecaoProvider.notifier)
                    .incrementar,
              );
            },
            data: (alunos) => alunos.isEmpty
                ? const EstadoVazio(
                    mensagem: vazioDetalheProjecao,
                    icone: Icons.person_search_outlined,
                  )
                : _ListaAlunos(alunos: alunos),
          ),
        ],
      ),
    );
  }
}

/// A defasagem dita antes de ser notada (design-system §7.3).
class _AvisoAoVivo extends StatelessWidget {
  const _AvisoAoVivo();

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(Dim.e12),
      decoration: BoxDecoration(
        color: cores.tertiaryContainer,
        borderRadius: BorderRadius.circular(Dim.raio),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.schedule, size: 16, color: cores.onTertiaryContainer),
          const SizedBox(width: Dim.e8),
          Flexible(
            child: Text(
              avisoDetalheAoVivo,
              style: Tipografia.apoio.copyWith(
                color: cores.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Aluno · regra · prevista · ritmo — as quatro colunas do wireframe §11.
///
/// Não é `TabelaIm360`: mora dentro de um painel já rolável, e a tabela traz o
/// próprio `Expanded` e os próprios filtros. É a mesma escolha do painel de
/// movimentações (card 6.7) e do de pedido (6.8).
class _ListaAlunos extends StatelessWidget {
  const _ListaAlunos({required this.alunos});

  final List<DetalheProjecao> alunos;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final aluno in alunos) ...[
          _LinhaAluno(aluno: aluno),
          Divider(height: 1, color: cores.outlineVariant),
        ],
      ],
    );
  }
}

/// Cada linha leva à ficha do aluno (wireframe §11): é lá que a previsão vencida
/// — a que derruba o aluno para média do método — se corrige.
class _LinhaAluno extends StatelessWidget {
  const _LinhaAluno({required this.aluno});

  final DetalheProjecao aluno;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => context.go(caminhoFichaAluno(aluno.alunoId)),
      child: ConstrainedBox(
        // Alvo de 44 px nas jornadas do celular (design-system §8.4).
        constraints: const BoxConstraints(minHeight: Dim.alvoMobile),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Dim.e8),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      aluno.rotuloAluno,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Tipografia.corpoTabela,
                    ),
                    Text(
                      '${rotuloRegra(aluno.regra)} · ${rotuloPosicao(aluno)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Tipografia.apoio.copyWith(
                        color: cores.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Dim.e8),
              Expanded(
                child: Text(
                  formatarData(aluno.dataPrevista),
                  textAlign: TextAlign.end,
                  style: Tipografia.numero(Tipografia.corpoTabela),
                ),
              ),
              const SizedBox(width: Dim.e8),
              SizedBox(
                width: 56,
                child: Text(
                  // O traço diz que aquele degrau não usa ritmo. Mostrar o do
                  // método aqui seria exibir um número que não gerou esta data.
                  rotuloRitmo(aluno.ritmoDias),
                  textAlign: TextAlign.end,
                  style: Tipografia.numero(Tipografia.corpoTabela)
                      .copyWith(color: cores.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
