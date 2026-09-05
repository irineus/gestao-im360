import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/ambiente.dart';
import '../../erros/erro_app.dart';
import '../../importacao/importacao.dart';
import '../../importacao/importacao_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../util/datas.dart';
import '../../util/seletor_arquivo.dart';
import '../../widgets/botoes.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';
import '../../widgets/tabela_im360.dart';
import 'textos_importacao.dart';

/// Tela 13 — Importação (docs/wireframes.md §16).
///
/// O assistente de quatro passos que carrega a planilha no sistema: escolher o
/// arquivo, validar, ler o relatório e aplicar. É a única porta pela qual dado
/// da planilha entra (decisão de 02/09/2026), e ela é de tempo de execução:
/// quem aperta é uma pessoa, contra o ambiente em que essa pessoa está logada.
///
/// Rota: o conjunto de `fn_importacao_conjunto()` — `admin.ler` mais os quatorze
/// códigos de escrita dos domínios que o arquivo traz (docs/permissoes-matriz.md
/// §6, linha 13). O `admin.ler` é o que a mantém da **direção**: os quatorze de
/// escrita a secretaria também tem.
///
/// ⚠️ **A faixa do ambiente é parte do contrato desta tela**, e é a primeira
/// coisa que ela desenha. As duas instalações são idênticas na aparência, e a
/// lição do `SUPABASE_ANON_KEY` no card 3.9 é que só se descobre em qual se
/// está quando já é tarde. Aqui "tarde" é a escola inteira gravada no banco
/// errado.
class TelaImportacao extends ConsumerStatefulWidget {
  const TelaImportacao({super.key});

  @override
  ConsumerState<TelaImportacao> createState() => _TelaImportacaoState();
}

class _TelaImportacaoState extends ConsumerState<TelaImportacao> {
  ArquivoEscolhido? _escolhido;
  ArquivoImportacao? _lido;
  String? _loteId;
  Map<String, dynamic>? _resultado;
  String? _erro;
  bool _ocupado = false;

  final _snapshot = TextEditingController();

  @override
  void dispose() {
    _snapshot.dispose();
    super.dispose();
  }

  Future<void> _escolher() async {
    final arquivo = await ref.read(seletorArquivoProvider)();
    if (arquivo == null || !mounted) return;
    final lido = ArquivoImportacao.deTexto(arquivo.conteudo);
    setState(() {
      _escolhido = arquivo;
      _lido = lido;
      // Trocar de arquivo zera o que veio do anterior. Sem isto, o relatório do
      // arquivo velho fica na tela ao lado do nome do arquivo novo — e é o
      // relatório que decide se alguém aplica.
      _loteId = null;
      _resultado = null;
      _erro = null;
      final sugerido = lido.snapshotEm;
      if (sugerido != null) _snapshot.text = formatarData(sugerido);
    });
  }

  /// As duas escritas e a leitura da tela passam por aqui: uma tradução só, um
  /// lugar só para o estado de "em execução" que trava o reenvio
  /// (design-system §5.4).
  Future<void> _executar(Future<void> Function() acao) async {
    setState(() {
      _ocupado = true;
      _erro = null;
    });
    try {
      await acao();
    } on ErroApp catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _validar() => _executar(() async {
    final data = lerData(_snapshot.text);
    final id = await ref
        .read(acoesImportacaoProvider)
        .registrar(
          arquivo: _escolhido!.nome,
          snapshotEm: data ?? hojeSaoPaulo(),
          dados: _lido!.dados!,
        );
    if (mounted) setState(() => _loteId = id);
  });

  Future<void> _aplicar({required bool simular}) => _executar(() async {
    final resultado = await ref
        .read(acoesImportacaoProvider)
        .aplicar(_loteId!, simular: simular);
    if (mounted) setState(() => _resultado = resultado);
  });

  @override
  Widget build(BuildContext context) {
    final lote = _loteId == null
        ? null
        : ref.watch(loteImportacaoProvider(_loteId!)).value;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(Dim.e16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FaixaAmbiente(),
              const SizedBox(height: Dim.e16),
              if (_erro != null) ...[
                AvisoTonal(mensagem: _erro!, erro: true),
                const SizedBox(height: Dim.e16),
              ],
              _Passo(
                numero: 1,
                titulo: 'Escolher o arquivo',
                filho: _passoUpload(context),
              ),
              _Passo(
                numero: 2,
                titulo: 'Validação',
                ativo: _lido?.valido ?? false,
                filho: _passoValidacao(),
              ),
              _Passo(
                numero: 3,
                titulo: 'Relatório',
                ativo: _loteId != null,
                filho: _passoRelatorio(lote),
              ),
              _Passo(
                numero: 4,
                titulo: 'Aplicar',
                ativo: lote?.podeAplicar ?? false,
                filho: _passoAplicar(context, lote),
                ultimo: true,
              ),
              const SizedBox(height: Dim.e24),
              const _Historico(),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // ① Upload
  // -------------------------------------------------------------------------
  Widget _passoUpload(BuildContext context) {
    if (!ref.watch(seletorDisponivelProvider)) {
      return const Text(textoImportacaoSemSeletor, style: Tipografia.corpo);
    }
    final lido = _lido;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(textoImportacaoArquivo, style: Tipografia.apoio),
        const SizedBox(height: Dim.e12),
        Wrap(
          spacing: Dim.e12,
          runSpacing: Dim.e8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            BotaoAcao(
              rotulo: 'Escolher arquivo…',
              icone: Icons.upload_file_outlined,
              nivel: NivelBotao.secundario,
              aoTocar: _ocupado ? null : _escolher,
              desabilitado: _ocupado
                  ? const DesabilitadoCom('Aguarde a operação em andamento.')
                  : null,
            ),
            if (_escolhido != null)
              Text(_escolhido!.nome, style: Tipografia.corpoTabela),
          ],
        ),
        if (lido != null && !lido.valido) ...[
          const SizedBox(height: Dim.e12),
          AvisoTonal(mensagem: lido.erro!, erro: true),
        ],
        if (lido?.valido ?? false) ...[
          const SizedBox(height: Dim.e16),
          SizedBox(
            width: Dim.larguraFormularioMax,
            child: TextField(
              controller: _snapshot,
              decoration: const InputDecoration(
                labelText: 'Data do snapshot da planilha *',
                helperText: textoImportacaoSnapshot,
                hintText: 'dd/mm/aaaa',
              ),
            ),
          ),
        ],
      ],
    );
  }

  // -------------------------------------------------------------------------
  // ② Validação — o que o arquivo traz, contado antes de subir
  // -------------------------------------------------------------------------
  Widget _passoValidacao() {
    final lido = _lido;
    if (lido == null || !lido.valido) {
      return const Text(
        textoImportacaoAguardandoArquivo,
        style: Tipografia.apoio,
      );
    }
    final dataOk = lerData(_snapshot.text) != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${lido.totalLinhas} linhas em ${lido.contagens.length} entidades.',
          style: Tipografia.corpo,
        ),
        const SizedBox(height: Dim.e8),
        Wrap(
          spacing: Dim.e8,
          runSpacing: Dim.e8,
          children: [
            for (final contagem in lido.contagens)
              Chip(
                label: Text(
                  '${rotuloEntidade(contagem.key)}: ${contagem.value}',
                ),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        if (lido.entidadesDesconhecidas.isNotEmpty) ...[
          const SizedBox(height: Dim.e12),
          AvisoTonal(
            mensagem: textoEntidadesDesconhecidas(lido.entidadesDesconhecidas),
          ),
        ],
        const SizedBox(height: Dim.e16),
        Align(
          alignment: Alignment.centerLeft,
          child: BotaoAcao(
            rotulo: _loteId == null ? 'Validar' : 'Validar de novo',
            icone: Icons.fact_check_outlined,
            aoTocar: _ocupado || !dataOk ? null : _validar,
            desabilitado: _ocupado
                ? const DesabilitadoCom('Aguarde a operação em andamento.')
                : (dataOk
                      ? null
                      : const DesabilitadoCom(textoImportacaoSnapshotFalta)),
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // ③ Relatório
  // -------------------------------------------------------------------------
  Widget _passoRelatorio(LoteImportacao? lote) {
    final id = _loteId;
    if (id == null) {
      return const Text(
        textoImportacaoAguardandoValidacao,
        style: Tipografia.apoio,
      );
    }
    final ocorrencias = ref.watch(ocorrenciasImportacaoProvider(id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (lote != null)
          Text(
            '${lote.erros} erro(s) · ${lote.avisos} aviso(s) — '
            '${rotuloStatusLote(lote.status)}.',
            style: Tipografia.corpo,
          ),
        const SizedBox(height: Dim.e4),
        const Text(textoImportacaoSeveridade, style: Tipografia.apoio),
        const SizedBox(height: Dim.e12),
        SizedBox(
          height: 360,
          child: TabelaIm360<OcorrenciaImportacao>(
            colunas: [
              ColunaIm360(
                titulo: 'Onde',
                texto: (o) => rotuloEntidade(o.entidade),
                flex: 2,
              ),
              ColunaIm360(
                titulo: 'Linha',
                texto: (o) => o.linha?.toString() ?? '—',
                numerica: true,
                prioridade: 3,
                flex: 1,
                larguraMin: 80,
              ),
              ColunaIm360(
                titulo: 'O que aconteceu',
                texto: (o) => o.mensagem,
                flex: 6,
                larguraMin: 240,
              ),
            ],
            linhas: ocorrencias,
            tomDaLinha: (o) => o.bloqueia ? TomLinha.erro : TomLinha.atencao,
            cartao: (o) => CartaoIm360(
              titulo: o.mensagem,
              subtitulo: rotuloEntidade(o.entidade),
              iconeApoio: o.bloqueia
                  ? Icons.error_outline
                  : Icons.warning_amber_outlined,
              apoio: o.bloqueia ? 'Bloqueia' : 'Aviso',
            ),
            estadoVazio: const EstadoVazio(
              mensagem: textoImportacaoSemOcorrencias,
              icone: Icons.check_circle_outline,
            ),
            aoRepetir: () => ref.invalidate(ocorrenciasImportacaoProvider(id)),
          ),
        ),
        const SizedBox(height: Dim.e12),
        Align(
          alignment: Alignment.centerLeft,
          child: BotaoAcao(
            rotulo: 'Baixar relatório',
            icone: Icons.download_outlined,
            nivel: NivelBotao.terciario,
            aoTocar: (ocorrencias.value?.isEmpty ?? true)
                ? null
                : () => baixarTexto(
                    'relatorio-importacao.csv',
                    relatorioEmCsv(ocorrencias.value ?? const []),
                  ),
            desabilitado: (ocorrencias.value?.isEmpty ?? true)
                ? const DesabilitadoCom(textoImportacaoNadaParaBaixar)
                : (baixarDisponivel
                      ? null
                      : const DesabilitadoCom(textoImportacaoSemDownload)),
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // ④ Aplicar — simulação primeiro, e o ambiente no rótulo do botão
  // -------------------------------------------------------------------------
  Widget _passoAplicar(BuildContext context, LoteImportacao? lote) {
    if (lote == null) {
      return const Text(
        textoImportacaoAguardandoValidacao,
        style: Tipografia.apoio,
      );
    }
    if (lote.aplicado) {
      return _totais(lote.totais, aplicado: true);
    }
    if (!lote.podeAplicar) {
      // ⚠️ O MOTIVO precisa vir junto, e não só o "foi desfeita". Quando o
      // trigger recusa uma linha, o lote vira FALHOU e a tela sai deste ramo —
      // se a mensagem do banco ficasse no ramo de cima, a pessoa leria "foi
      // desfeita por inteiro" sem saber por quê, e o que ela tem em mãos é um
      // arquivo de milhares de linhas. Medido no widget test em 06/09/2026.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            lote.status == 'FALHOU'
                ? textoImportacaoFalhou
                : textoImportacaoReprovada,
            style: Tipografia.corpo,
          ),
          if (_resultado?['status'] == 'FALHOU') ...[
            const SizedBox(height: Dim.e12),
            AvisoTonal(
              mensagem: textoFalhaAplicacao('${_resultado?['mensagem'] ?? ''}'),
              erro: true,
            ),
          ],
        ],
      );
    }

    final simulado = _resultado?['status'] == 'SIMULADA';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(textoImportacaoSimulacao, style: Tipografia.apoio),
        const SizedBox(height: Dim.e12),
        Wrap(
          spacing: Dim.e12,
          runSpacing: Dim.e8,
          children: [
            BotaoAcao(
              rotulo: 'Simular',
              icone: Icons.science_outlined,
              nivel: NivelBotao.secundario,
              aoTocar: _ocupado ? null : () => _aplicar(simular: true),
              desabilitado: _ocupado
                  ? const DesabilitadoCom('Aguarde a operação em andamento.')
                  : null,
            ),
            BotaoAcao(
              rotulo: 'Aplicar em ${rotuloAmbiente(Ambiente.ambiente)}',
              icone: Icons.play_arrow_outlined,
              aoTocar: _ocupado || !simulado
                  ? null
                  : () async {
                      // Diálogo, e não snackbar: é o "resultado que muda o que
                      // o usuário fará em seguida" do design-system §5.8, e a
                      // consequência (o ambiente) vai no título.
                      final confirmou = await showDialog<bool>(
                        context: context,
                        builder: (contexto) => AlertDialog(
                          title: Text(
                            'Aplicar em ${rotuloAmbiente(Ambiente.ambiente)}?',
                          ),
                          content: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: Text(
                              textoConfirmarAplicacao(
                                rotuloAmbiente(Ambiente.ambiente),
                              ),
                              style: Tipografia.corpo,
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(contexto).pop(false),
                              child: const Text('Cancelar'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(contexto).pop(true),
                              child: const Text('Aplicar agora'),
                            ),
                          ],
                        ),
                      );
                      if (confirmou == true) await _aplicar(simular: false);
                    },
              desabilitado: _ocupado
                  ? const DesabilitadoCom('Aguarde a operação em andamento.')
                  : (simulado
                        ? null
                        : const DesabilitadoCom(textoImportacaoSimuleAntes)),
            ),
          ],
        ),
        if (_resultado?['status'] == 'FALHOU') ...[
          const SizedBox(height: Dim.e12),
          AvisoTonal(
            mensagem: textoFalhaAplicacao('${_resultado?['mensagem'] ?? ''}'),
            erro: true,
          ),
        ],
        if (_resultado?['totais'] is Map<String, dynamic>) ...[
          const SizedBox(height: Dim.e16),
          _totais(
            _resultado!['totais'] as Map<String, dynamic>,
            aplicado: _resultado?['status'] == 'APLICADA',
          ),
        ],
      ],
    );
  }

  Widget _totais(Map<String, dynamic>? totais, {required bool aplicado}) {
    final linhas = lerTotais(totais);
    if (linhas.isEmpty) {
      return const Text(textoImportacaoSemTotais, style: Tipografia.apoio);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          aplicado ? textoTotaisAplicados : textoTotaisSimulados,
          style: Tipografia.apoio,
        ),
        const SizedBox(height: Dim.e8),
        SizedBox(
          height: 360,
          child: TabelaIm360<TotalImportacao>(
            colunas: [
              ColunaIm360(
                titulo: 'Entidade',
                texto: (t) => rotuloEntidade(t.entidade),
                flex: 3,
              ),
              ColunaIm360(
                titulo: 'No arquivo',
                texto: (t) => '${t.arquivo}',
                numerica: true,
                prioridade: 2,
                flex: 1,
                larguraMin: 96,
              ),
              ColunaIm360(
                titulo: 'Aplicadas',
                texto: (t) => '${t.aplicadas}',
                numerica: true,
                prioridade: 2,
                flex: 1,
                larguraMin: 96,
              ),
              ColunaIm360(
                titulo: 'Ignoradas',
                texto: (t) => '${t.ignoradas}',
                numerica: true,
                prioridade: 3,
                flex: 1,
                larguraMin: 96,
              ),
              ColunaIm360(
                titulo: 'No sistema',
                texto: (t) => '${t.noSistema}',
                numerica: true,
                flex: 1,
                larguraMin: 110,
              ),
            ],
            linhas: AsyncValue.data(linhas),
            cartao: (t) => CartaoIm360(
              titulo: rotuloEntidade(t.entidade),
              subtitulo:
                  'arquivo ${t.arquivo} · aplicadas ${t.aplicadas} · '
                  'ignoradas ${t.ignoradas}',
              destaque: '${t.noSistema}',
            ),
            estadoVazio: const EstadoVazio(mensagem: textoImportacaoSemTotais),
          ),
        ),
      ],
    );
  }
}

/// A faixa que diz onde a pessoa está. Produção tem o par tonal de ERRO — não é
/// exagero: é a única tela do app cuja ação vale a escola inteira, e ela é
/// idêntica nos dois ambientes.
class FaixaAmbiente extends StatelessWidget {
  const FaixaAmbiente({super.key});

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final producao = Ambiente.ambiente == 'producao';
    return Container(
      padding: const EdgeInsets.all(Dim.e12),
      decoration: BoxDecoration(
        color: producao ? cores.errorContainer : cores.tertiaryContainer,
        borderRadius: BorderRadius.circular(Dim.raio),
      ),
      child: Row(
        children: [
          Icon(
            producao ? Icons.warning_amber_outlined : Icons.info_outline,
            color: producao
                ? cores.onErrorContainer
                : cores.onTertiaryContainer,
          ),
          const SizedBox(width: Dim.e12),
          Flexible(
            child: Text(
              textoFaixaAmbiente(rotuloAmbiente(Ambiente.ambiente)),
              style: Tipografia.corpo.copyWith(
                color: producao
                    ? cores.onErrorContainer
                    : cores.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Um passo do assistente. Numerado porque o §16 é numerado: quem acompanha a
/// carga por telefone precisa dizer "parei no 3".
class _Passo extends StatelessWidget {
  const _Passo({
    required this.numero,
    required this.titulo,
    required this.filho,
    this.ativo = true,
    this.ultimo = false,
  });

  final int numero;
  final String titulo;
  final Widget filho;
  final bool ativo;
  final bool ultimo;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Opacity(
      // Passo ainda inalcançável fica esmaecido, e não escondido: sumir muda a
      // numeração e a pessoa perde a referência do que vem depois.
      opacity: ativo ? 1 : 0.6,
      child: Container(
        margin: EdgeInsets.only(bottom: ultimo ? 0 : Dim.e16),
        padding: const EdgeInsets.all(Dim.e16),
        decoration: BoxDecoration(
          border: Border.all(color: cores.outlineVariant),
          borderRadius: BorderRadius.circular(Dim.raio),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: cores.secondaryContainer,
                  child: Text(
                    '$numero',
                    style: Tipografia.badge.copyWith(
                      color: cores.onSecondaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: Dim.e8),
                // `Expanded`, e não `Text` solto: em 390 px o título do passo
                // 4 ("Aplicar") vem acompanhado do círculo do número, e o
                // conjunto estourava a `Row` pela mesma via do item 19 do §11
                // do design-system — a barra de ações da TabelaIm360, medida no
                // card 8.1,5.
                Expanded(child: Text(titulo, style: Tipografia.subtitulo)),
              ],
            ),
            const SizedBox(height: Dim.e12),
            filho,
          ],
        ),
      ),
    );
  }
}

/// Importações anteriores.
///
/// ⚠️ **Não está no §16 do wireframe**, e entra assim mesmo: o plano §8 exige
/// que a migração seja AUDITÁVEL, a tabela `importacao` guarda cada lote com o
/// relatório dele, e sem esta lista o histórico existiria e não teria tela.
/// Divergência registrada em `docs/wireframes.md` §17.
class _Historico extends ConsumerWidget {
  const _Historico();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lotes = ref.watch(lotesImportacaoProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Importações anteriores', style: Tipografia.subtitulo),
        const SizedBox(height: Dim.e8),
        SizedBox(
          height: 360,
          child: TabelaIm360<LoteImportacao>(
            colunas: [
              ColunaIm360(titulo: 'Arquivo', texto: (l) => l.arquivo, flex: 3),
              ColunaIm360(
                titulo: 'Snapshot',
                texto: (l) =>
                    l.snapshotEm == null ? '—' : formatarData(l.snapshotEm!),
                prioridade: 2,
                flex: 1,
                larguraMin: 110,
              ),
              ColunaIm360(
                titulo: 'Situação',
                texto: (l) => rotuloStatusLote(l.status),
                flex: 1,
                larguraMin: 110,
              ),
              ColunaIm360(
                titulo: 'Erros',
                texto: (l) => '${l.erros}',
                numerica: true,
                prioridade: 3,
                flex: 1,
                larguraMin: 80,
              ),
              ColunaIm360(
                titulo: 'Avisos',
                texto: (l) => '${l.avisos}',
                numerica: true,
                prioridade: 3,
                flex: 1,
                larguraMin: 80,
              ),
              ColunaIm360(
                titulo: 'Aplicada por',
                texto: (l) => l.aplicadoPorNome ?? '—',
                prioridade: 2,
                flex: 2,
              ),
            ],
            linhas: lotes,
            cartao: (l) => CartaoIm360(
              titulo: l.arquivo,
              subtitulo:
                  '${rotuloStatusLote(l.status)} · '
                  '${l.erros} erro(s) · ${l.avisos} aviso(s)',
            ),
            estadoVazio: const EstadoVazio(
              mensagem: textoImportacaoSemHistorico,
              icone: Icons.history_outlined,
            ),
            aoRepetir: () => ref.invalidate(lotesImportacaoProvider),
          ),
        ),
      ],
    );
  }
}
