import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../alunos/alunos.dart';
import '../../alunos/alunos_provider.dart';
import '../../erros/erro_app.dart';
import '../../pendencias/pendencias.dart';
import '../../pendencias/pendencias_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../turmas/turmas.dart';
import '../../turmas/turmas_provider.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';
import '../turmas/formularios.dart' show recarregarTurmas;

/// Os formulários da central (card 5.8): fechar uma pendência (resolver ou
/// ignorar) e **executar** as duas metades da virada REP.
///
/// Os três orquestram funções do banco e não reescrevem regra nenhuma
/// (card 2.6 decisão 2): `fn_pendencia_resolver_id` cobra
/// `pendencias.resolver`, `fn_rep_virar_continuo` delega vaga e método a
/// `fn_bloco_admitir` com o advisory lock, e `fn_rep_voltar_pontual` cobra o
/// motivo. O que existe aqui de decisão é o que **avisar** antes do clique.

/// Fecha a pendência: `RESOLVIDA` ou `IGNORADA`.
///
/// ⚠️ A justificativa **não** é pré-validada, nem no caso de ignorar, em que ela
/// é obrigatória: quem a exige é a função (`PT422 / MOTIVO_OBRIGATORIO`), e a
/// tela realça o campo pelo código — mesmo desenho da mudança de status do card
/// 4.6. Uma validação local aqui seria a segunda implementação de uma regra que
/// já está no banco, livre para divergir dele.
class FormularioFecharPendencia extends ConsumerStatefulWidget {
  const FormularioFecharPendencia({
    super.key,
    required this.pendencia,
    required this.resolucao,
  });

  final Pendencia pendencia;

  /// [resolucaoResolvida] ou [resolucaoIgnorada].
  final String resolucao;

  @override
  ConsumerState<FormularioFecharPendencia> createState() =>
      _FormularioFecharPendenciaState();
}

class _FormularioFecharPendenciaState
    extends ConsumerState<FormularioFecharPendencia> {
  final _chave = GlobalKey<FormState>();
  final _justificativa = TextEditingController();
  String? _erroJustificativa;

  @override
  void dispose() {
    _justificativa.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pendencia = widget.pendencia;
    final ignorar = widget.resolucao == resolucaoIgnorada;
    final automatico = fechamentoAutomatico(pendencia.tipo);

    return FormularioIm360(
      titulo: ignorar ? 'Ignorar pendência' : 'Resolver pendência',
      chave: _chave,
      rotuloSalvar: ignorar ? 'Ignorar' : 'Resolver',
      // Ignorar carrega o aviso que o card 5.5 (c) manda dar; resolver carrega o
      // "fecha automaticamente quando …" do wireframe §14.2, que existe para
      // ninguém encerrar à mão o que o sistema encerra sozinho.
      aviso: ignorar ? avisoIgnorar : automatico,
      aoErro: (erro) {
        if (erro.codigo == 'MOTIVO_OBRIGATORIO') {
          setState(() => _erroJustificativa = erro.mensagem);
        }
      },
      campos: [
        Text(
          '${rotuloTipoPendencia(pendencia.tipo)} — ${pendencia.descricao}',
          style: Tipografia.corpo,
        ),
        TextFormField(
          controller: _justificativa,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: ignorar ? 'Justificativa *' : 'Justificativa',
            helperText: ignorar
                ? 'Por que esta pendência não precisa de ação agora. Fica '
                      'registrada na linha, com quem ignorou e quando.'
                : 'Opcional — o que foi feito. Fica registrada na linha.',
            helperMaxLines: 3,
            errorText: _erroJustificativa,
          ),
          onChanged: (_) {
            if (_erroJustificativa != null) {
              setState(() => _erroJustificativa = null);
            }
          },
        ),
      ],
      aoSalvar: () async {
        final texto = _justificativa.text.trim();
        await ref
            .read(pendenciasRepositorioProvider)
            .resolver(
              pendencia.id,
              resolucao: widget.resolucao,
              justificativa: texto.isEmpty ? null : texto,
            );
        recarregarPendencias(ref);
        return widget.resolucao;
      },
    );
  }
}

/// `REP_VIRADA:CONTINUO` — o **seletor de bloco** do card 2.6 decisão (d).
///
/// É por causa deste formulário que a virada é sugerida e não automática
/// (card 2.5 (a)): escolher em qual bloco o aluno passa a vir toda semana é
/// justamente o que o `pg_cron` não tinha como fazer — sozinho ele esbarraria em
/// `BLOCO_LOTADO` dentro da rotina, falhando em silêncio.
///
/// ⚠️ **O bloco em que o aluno JÁ está é oferecido mesmo lotado**, e essa é a
/// decisão do formulário. `fn_bloco_admitir` só disputa vaga quando a linha
/// **entra** na conta (card 5.3, decisão 2): virar o tipo de uma alocação que já
/// existe não muda a ocupação do bloco. Oferecer só blocos com vaga esconderia
/// exatamente a resposta mais provável — o horário que o aluno já frequenta — e
/// mandaria a secretaria mudá-lo de turma sem necessidade.
class FormularioVirarContinuo extends ConsumerStatefulWidget {
  const FormularioVirarContinuo({super.key, required this.pendencia});

  final Pendencia pendencia;

  @override
  ConsumerState<FormularioVirarContinuo> createState() =>
      _FormularioVirarContinuoState();
}

class _FormularioVirarContinuoState
    extends ConsumerState<FormularioVirarContinuo> {
  final _chave = GlobalKey<FormState>();
  final _observacao = TextEditingController();
  String? _blocoId;

  @override
  void dispose() {
    _observacao.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pendencia = widget.pendencia;
    final alunoId = pendencia.alunoId!;
    final grade = ref.watch(gradeProvider);

    // Esperar a grade em vez de ler com `?? const []`: sem ela a lista de blocos
    // sai vazia e a pessoa conclui que não há horário nenhum (a lição do
    // formulário de admissão do card 5.7).
    if (!grade.hasValue) {
      return FormularioIm360(
        titulo: 'Virar reposição contínua',
        chave: _chave,
        somenteLeitura: true,
        legendaObrigatorio: false,
        campos: const [EstadoCarregando(linhas: 4)],
      );
    }

    final jaAlocado = <String>{
      for (final t
          in ref.watch(turmasPorAlunoProvider)[alunoId] ??
              const <TurmaDoAluno>[])
        if (t.blocoAtivo) t.blocoId,
    };

    // ⚠️ O método filtra **quando se sabe qual é**. A rota da central exige só
    // `pendencias.ler` (card 2.4 §6), então um perfil sem `alunos.ler` chega
    // aqui e a lista de alunos vem vazia pela RLS: filtrar por um método
    // desconhecido esvaziaria o seletor, e "nenhum horário" é a mentira que
    // este projeto cataloga. Sem o método, oferece-se tudo o que tem vaga e
    // quem recusa é `tg_bloco_aluno_admissao`, com `METODO_INCOMPATIVEL`
    // traduzido — erro honesto vale mais que lista vazia.
    String? metodoDoAluno;
    for (final aluno in ref.watch(alunosProvider).value ?? const <Aluno>[]) {
      if (aluno.id == alunoId) metodoDoAluno = aluno.metodoId;
    }

    // Um bloco por horário, não um por dia da semana: a grade traz a mesma
    // turma uma vez por data, e repetir "Seg 08:00" cinco vezes na lista faria
    // a escolha parecer maior do que é.
    final candidatos = <String, CelulaGrade>{};
    for (final c in grade.requireValue) {
      if (metodoDoAluno != null && c.metodoId != metodoDoAluno) continue;
      if (c.vagasLivres > 0 || jaAlocado.contains(c.blocoId)) {
        candidatos.putIfAbsent(c.blocoId, () => c);
      }
    }
    final blocos = candidatos.values.toList()
      ..sort((a, b) {
        final dia = a.diaSemana.compareTo(b.diaSemana);
        if (dia != 0) return dia;
        final hora = a.horaInicio.compareTo(b.horaInicio);
        return hora != 0 ? hora : a.salaNome.compareTo(b.salaNome);
      });

    return FormularioIm360(
      titulo: 'Virar reposição contínua',
      chave: _chave,
      rotuloSalvar: 'Virar contínuo',
      aviso: avisoVirarContinuo,
      campos: [
        Text(pendencia.descricao, style: Tipografia.corpo),
        _ListaBlocos(
          blocos: blocos,
          jaAlocado: jaAlocado,
          selecionado: _blocoId,
          aoSelecionar: (id) => setState(() => _blocoId = id),
        ),
        TextFormField(
          controller: _observacao,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Observação',
            helperText:
                'Fica registrada nas reposições pontuais que a virada cancela.',
            helperMaxLines: 3,
          ),
        ),
      ],
      aoSalvar: () async {
        final bloco = _blocoId;
        if (bloco == null) {
          throw const ErroApp(mensagem: escolhaBloco, traduzido: true);
        }
        final texto = _observacao.text.trim();
        await ref
            .read(turmasRepositorioProvider)
            .virarContinuo(
              alunoId: alunoId,
              blocoId: bloco,
              observacao: texto.isEmpty ? null : texto,
            );
        recarregarTurmas(ref);
        recarregarPendencias(ref);
        return 'virada';
      },
    );
  }
}

/// Falta de escolha na lista **não** é erro do banco: é o formulário dizendo o
/// que falta, como qualquer validação de formato (design-system §5.4).
const escolhaBloco = 'Escolha o bloco na lista acima.';

const avisoVirarContinuo =
    'A reposição contínua ocupa uma vaga fixa no bloco, toda semana, e as '
    'reposições pontuais ainda previstas deste aluno são canceladas. O relógio '
    'do débito recomeça hoje: o aluno só volta a ser pontual depois de zerar as '
    'aulas em aberto e cumprir a carência.';

const semBlocoComVaga =
    'Nenhum bloco com vaga livre nesta semana, e o aluno não está alocado em '
    'nenhum. Libere uma vaga, aumente a capacidade manual de um bloco ou '
    'cadastre outro horário antes de virar contínuo.';

/// A lista de blocos do seletor.
///
/// Não é `DropdownButtonFormField` pela mesma razão do card 5.7: a lista muda
/// com a semana carregada, e um valor selecionado fora dos itens é um `assert`
/// do framework que derruba a tela (medido no card 5.6).
class _ListaBlocos extends StatelessWidget {
  const _ListaBlocos({
    required this.blocos,
    required this.jaAlocado,
    required this.selecionado,
    required this.aoSelecionar,
  });

  final List<CelulaGrade> blocos;
  final Set<String> jaAlocado;
  final String? selecionado;
  final void Function(String blocoId) aoSelecionar;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    if (blocos.isEmpty) {
      return Text(
        semBlocoComVaga,
        style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Bloco da reposição contínua *',
          style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
        ),
        for (final bloco in blocos)
          InkWell(
            onTap: () => aoSelecionar(bloco.blocoId),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Dim.e4),
              child: Row(
                children: [
                  Icon(
                    bloco.blocoId == selecionado
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: bloco.blocoId == selecionado
                        ? cores.primary
                        : cores.onSurfaceVariant,
                  ),
                  const SizedBox(width: Dim.e8),
                  Expanded(
                    child: Text(
                      [
                        rotuloBloco(bloco.diaSemana, bloco.horaInicio),
                        bloco.salaNome,
                        bloco.metodoCodigo,
                        jaAlocado.contains(bloco.blocoId)
                            ? 'já é a turma dele'
                            : '${bloco.vagasLivres} vaga(s)',
                      ].join(' · '),
                      style: Tipografia.corpoTabela,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// `REP_VIRADA:VOLTA` — devolver o aluno a reposição pontual, liberando a vaga
/// fixa. Motivo obrigatório, cobrado por `fn_rep_voltar_pontual`.
class FormularioVoltarPontual extends ConsumerStatefulWidget {
  const FormularioVoltarPontual({super.key, required this.pendencia});

  final Pendencia pendencia;

  @override
  ConsumerState<FormularioVoltarPontual> createState() =>
      _FormularioVoltarPontualState();
}

class _FormularioVoltarPontualState
    extends ConsumerState<FormularioVoltarPontual> {
  final _chave = GlobalKey<FormState>();
  final _motivo = TextEditingController();
  String? _erroMotivo;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pendencia = widget.pendencia;

    return FormularioIm360(
      titulo: 'Voltar a reposição pontual',
      chave: _chave,
      rotuloSalvar: 'Voltar a pontual',
      aviso: avisoVoltarPontual,
      aoErro: (erro) {
        if (erro.codigo == 'MOTIVO_OBRIGATORIO') {
          setState(() => _erroMotivo = erro.mensagem);
        }
      },
      campos: [
        Text(pendencia.descricao, style: Tipografia.corpo),
        TextFormField(
          controller: _motivo,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: 'Motivo *',
            helperText:
                'Fica registrado na alocação encerrada — é o que explica a '
                'saída para quem olhar a turma depois.',
            helperMaxLines: 3,
            errorText: _erroMotivo,
          ),
          onChanged: (_) {
            if (_erroMotivo != null) setState(() => _erroMotivo = null);
          },
        ),
      ],
      aoSalvar: () async {
        await ref
            .read(turmasRepositorioProvider)
            .voltarPontual(
              alunoId: pendencia.alunoId!,
              motivo: _motivo.text.trim(),
            );
        recarregarTurmas(ref);
        recarregarPendencias(ref);
        return 'virada';
      },
    );
  }
}

const avisoVoltarPontual =
    'A vaga fixa é liberada. Se este for o único bloco do aluno, ele fica sem '
    'turma — e a rotina diária (03:10) abre a pendência "aluno sem turma" '
    'enquanto isso valer.';
