import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../alunos/alunos.dart';
import '../../alunos/alunos_provider.dart';
import '../../catalogo/catalogo.dart';
import '../../catalogo/catalogo_provider.dart';
import '../../sessao/sessao_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../util/datas.dart';
import '../../widgets/badge_status.dart';
import '../../widgets/formulario.dart';

/// Os formulários da tela de Alunos (card 4.6): matrícula/dados, alterar
/// status e reverter status. Todos devolvem `'salvo'` ao fechar, para a tela
/// mostrar a confirmação efêmera certa (design-system §5.8).
///
/// Nenhum deles verifica regra: submete e traduz o erro pelo código
/// (card 2.6 decisão 2). O que se valida aqui é formato — obrigatório e data.

void _recarregar(WidgetRef ref) =>
    ref.read(versaoAlunosProvider.notifier).incrementar();

/// Texto final do apontamento 6 do card 2.6 (design-system §7.3).
const avisoTrocaCombo =
    'Trocar o combo não refaz a trilha do aluno — será aberta uma pendência '
    'para revisar a trilha.';

/// Design-system §7.3, "Sair de ATIVO/ACELERAR".
const avisoSaiDasTurmas = 'O aluno será removido das turmas ao confirmar.';

// ---------------------------------------------------------------------------
// Matrícula e dados cadastrais
// ---------------------------------------------------------------------------

class FormularioAluno extends ConsumerStatefulWidget {
  const FormularioAluno({super.key, this.aluno});

  /// Nulo = matrícula.
  final Aluno? aluno;

  @override
  ConsumerState<FormularioAluno> createState() => _FormularioAlunoState();
}

class _FormularioAlunoState extends ConsumerState<FormularioAluno> {
  final _chave = GlobalKey<FormState>();
  late final _nome = TextEditingController(text: widget.aluno?.nome ?? '');
  late final _codigo = TextEditingController(
    text: widget.aluno?.codigoSgf ?? '',
  );
  late final _inicio = TextEditingController(
    text: formatarData(widget.aluno?.dataInicio ?? DateTime.now()),
  );
  late final _previsao = TextEditingController(
    text: widget.aluno?.prevConclusaoCurso == null
        ? ''
        : formatarData(widget.aluno!.prevConclusaoCurso!),
  );
  late final _observacoes = TextEditingController(
    text: widget.aluno?.observacoes ?? '',
  );
  late String? _metodoId = widget.aluno?.metodoId;
  late String? _comboId = widget.aluno?.comboId;

  @override
  void dispose() {
    _nome.dispose();
    _codigo.dispose();
    _inicio.dispose();
    _previsao.dispose();
    _observacoes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final permissoes = ref.watch(permissoesProvider);
    final metodos = ref.watch(metodosProvider).value ?? const <Metodo>[];
    final combos = ref.watch(combosProvider).value ?? const <Combo>[];
    final aluno = widget.aluno;
    final editando = aluno != null;
    final somenteLeitura = editando
        ? !permissoes.contains('alunos.editar')
        : !permissoes.contains('alunos.criar');
    // Combo é do método: só os do método escolhido, ativos — mais o atual,
    // se ficou inativo depois da matrícula.
    final combosDoMetodo = [
      for (final c in combos)
        if (c.metodoId == _metodoId && (c.ativo || c.id == _comboId)) c,
    ];
    final trocouCombo = editando && _comboId != aluno.comboId;

    return FormularioIm360(
      titulo: editando ? 'Dados do aluno' : 'Matricular aluno',
      rotuloSalvar: editando ? 'Salvar' : 'Matricular',
      chave: _chave,
      somenteLeitura: somenteLeitura,
      aviso: trocouCombo ? avisoTrocaCombo : null,
      campos: [
        TextFormField(
          controller: _nome,
          readOnly: somenteLeitura,
          style: Tipografia.corpo,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Nome *'),
          validator: validarObrigatorio,
        ),
        TextFormField(
          controller: _codigo,
          readOnly: somenteLeitura,
          style: Tipografia.numero(Tipografia.corpo),
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Código SGF',
            helperText:
                'Opcional — o número do aluno no SGF. Único na unidade.',
            helperMaxLines: 3,
          ),
        ),
        DropdownButtonFormField<String>(
          initialValue: _metodoId,
          decoration: InputDecoration(
            labelText: 'Método *',
            helperText: editando
                ? 'O método não muda depois da matrícula.'
                : 'Combo, trilha e turmas são do método.',
            helperMaxLines: 3,
          ),
          items: [
            for (final m in metodos)
              if (m.ativo || m.id == _metodoId)
                DropdownMenuItem(value: m.id, child: Text(m.nome)),
          ],
          onChanged: somenteLeitura || editando
              ? null
              : (valor) => setState(() {
                  _metodoId = valor;
                  _comboId = null;
                }),
          validator: (valor) => valor == null ? 'Escolha o método.' : null,
        ),
        DropdownButtonFormField<String>(
          // A chave acompanha o método: trocar o método zera o combo.
          key: ValueKey('combo-$_metodoId'),
          initialValue: _comboId ?? '',
          decoration: const InputDecoration(
            labelText: 'Combo',
            helperText:
                'A trilha do aluno nasce do combo na matrícula (Fase 6).',
            helperMaxLines: 3,
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('Nenhum')),
            for (final c in combosDoMetodo)
              DropdownMenuItem(value: c.id, child: Text(c.nome)),
          ],
          onChanged: somenteLeitura
              ? null
              : (valor) => setState(
                  () => _comboId = (valor == null || valor.isEmpty)
                      ? null
                      : valor,
                ),
        ),
        TextFormField(
          controller: _inicio,
          readOnly: somenteLeitura,
          style: Tipografia.numero(Tipografia.corpo),
          keyboardType: TextInputType.datetime,
          decoration: const InputDecoration(
            labelText: 'Data de início *',
            hintText: 'dd/mm/aaaa',
          ),
          validator: validarData,
        ),
        TextFormField(
          controller: _previsao,
          readOnly: somenteLeitura,
          style: Tipografia.numero(Tipografia.corpo),
          keyboardType: TextInputType.datetime,
          decoration: const InputDecoration(
            labelText: 'Previsão de conclusão',
            hintText: 'dd/mm/aaaa',
            helperText:
                'Opcional, informada manualmente. Alimenta a projeção de '
                'demanda de apostilas.',
            helperMaxLines: 3,
          ),
          validator: (valor) => validarData(valor, obrigatorio: false),
        ),
        TextFormField(
          controller: _observacoes,
          readOnly: somenteLeitura,
          style: Tipografia.corpo,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Observações'),
        ),
      ],
      aoSalvar: () async {
        await ref
            .read(alunosRepositorioProvider)
            .salvarAluno(
              Aluno(
                id: aluno?.id,
                nome: _nome.text,
                metodoId: _metodoId!,
                codigoSgf: _codigo.text,
                comboId: _comboId,
                status: aluno?.status ?? 'ATIVO',
                dataInicio: lerData(_inicio.text),
                prevConclusaoCurso: _previsao.text.trim().isEmpty
                    ? null
                    : lerData(_previsao.text),
                observacoes: _observacoes.text,
              ),
            );
        _recarregar(ref);
        return 'salvo';
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Alterar status — só as transições válidas a partir do atual (§6.2)
// ---------------------------------------------------------------------------

class FormularioAlterarStatus extends ConsumerStatefulWidget {
  const FormularioAlterarStatus({super.key, required this.aluno});

  final Aluno aluno;

  @override
  ConsumerState<FormularioAlterarStatus> createState() =>
      _FormularioAlterarStatusState();
}

class _FormularioAlterarStatusState
    extends ConsumerState<FormularioAlterarStatus> {
  final _chave = GlobalKey<FormState>();
  final _motivo = TextEditingController();
  String? _destino;

  /// Realce do campo quando o banco responde `MOTIVO_OBRIGATORIO`
  /// (design-system §5.4). A tela não pré-valida: o motivo é obrigatório por
  /// **destino**, e quem sabe a regra é `fn_aluno_alterar_status`.
  String? _erroMotivo;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aluno = widget.aluno;
    final destino = _destino;
    final avisa =
        destino != null && saiDasTurmas(de: aluno.status, para: destino);

    return FormularioIm360(
      titulo: 'Alterar status — ${aluno.nome}',
      rotuloSalvar: 'Alterar status',
      chave: _chave,
      somenteLeitura: !ref
          .watch(permissoesProvider)
          .contains('alunos.alterar_status'),
      aviso: avisa ? avisoSaiDasTurmas : null,
      aoErro: (erro) {
        if (erro.codigo == 'MOTIVO_OBRIGATORIO') {
          setState(() => _erroMotivo = erro.mensagem);
        }
      },
      campos: [
        Row(
          children: [
            const Text('Status atual', style: Tipografia.corpo),
            const SizedBox(width: Dim.e8),
            BadgeStatus(aluno.status),
          ],
        ),
        DropdownButtonFormField<String>(
          initialValue: _destino,
          decoration: const InputDecoration(
            labelText: 'Novo status *',
            helperText:
                'Só as mudanças permitidas a partir do status atual. FORMADO '
                'exige certificado entregue ou confirmação da direção.',
            helperMaxLines: 4,
          ),
          items: [
            for (final s in transicoesDe(aluno.status))
              DropdownMenuItem(value: s, child: Text(s)),
          ],
          onChanged: (valor) => setState(() => _destino = valor),
          validator: (valor) => valor == null ? 'Escolha o novo status.' : null,
        ),
        TextFormField(
          controller: _motivo,
          style: Tipografia.corpo,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'Motivo',
            helperText: 'Obrigatório para STANDBY, TRANCADO e CANCELADO.',
            helperMaxLines: 3,
            errorText: _erroMotivo,
          ),
          onChanged: (_) {
            if (_erroMotivo != null) setState(() => _erroMotivo = null);
          },
        ),
      ],
      aoSalvar: () async {
        final motivo = _motivo.text.trim();
        await ref
            .read(alunosRepositorioProvider)
            .alterarStatus(
              aluno.id!,
              status: _destino!,
              motivo: motivo.isEmpty ? null : motivo,
            );
        _recarregar(ref);
        return 'salvo';
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Reverter status terminal — só a direção, motivo sempre obrigatório (§6.5)
// ---------------------------------------------------------------------------

class FormularioReverterStatus extends ConsumerStatefulWidget {
  const FormularioReverterStatus({super.key, required this.aluno});

  final Aluno aluno;

  @override
  ConsumerState<FormularioReverterStatus> createState() =>
      _FormularioReverterStatusState();
}

class _FormularioReverterStatusState
    extends ConsumerState<FormularioReverterStatus> {
  final _chave = GlobalKey<FormState>();
  final _motivo = TextEditingController();
  String? _destino;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aluno = widget.aluno;
    return FormularioIm360(
      titulo: 'Reverter status — ${aluno.nome}',
      rotuloSalvar: 'Reverter',
      chave: _chave,
      somenteLeitura: !ref
          .watch(permissoesProvider)
          .contains('alunos.reverter_status'),
      aviso:
          'Reverter um status terminal é exceção: o motivo fica registrado no '
          'histórico com quem reverteu e quando.',
      campos: [
        Row(
          children: [
            const Text('Status atual', style: Tipografia.corpo),
            const SizedBox(width: Dim.e8),
            BadgeStatus(aluno.status),
          ],
        ),
        DropdownButtonFormField<String>(
          initialValue: _destino,
          decoration: const InputDecoration(labelText: 'Voltar para *'),
          items: [
            for (final s in destinosReversao(aluno.status))
              DropdownMenuItem(value: s, child: Text(s)),
          ],
          onChanged: (valor) => setState(() => _destino = valor),
          validator: (valor) => valor == null ? 'Escolha o status.' : null,
        ),
        // Aqui o motivo é sempre obrigatório (card 4.2 (b)), então a
        // obrigatoriedade é formato e se valida localmente.
        TextFormField(
          controller: _motivo,
          style: Tipografia.corpo,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Motivo *'),
          validator: validarObrigatorio,
        ),
      ],
      aoSalvar: () async {
        await ref
            .read(alunosRepositorioProvider)
            .reverterStatus(
              aluno.id!,
              destino: _destino!,
              motivo: _motivo.text.trim(),
            );
        _recarregar(ref);
        return 'salvo';
      },
    );
  }
}
