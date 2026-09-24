import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/ambiente.dart';
import '../../erros/erro_app.dart';
import '../../importacao/importacao.dart';
import '../../importacao/importacao_provider.dart';
import '../../rotina/rotina.dart';
import '../../sessao/sessao_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../util/datas.dart';
import '../../util/seletor_arquivo.dart';
import '../../util/texto.dart';
import '../../widgets/botoes.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';
import '../../widgets/recalcular_agora.dart';
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

  /// O passo 3, para rolar até ele quando um lote é retomado pelo histórico.
  final _chaveRelatorio = GlobalKey();

  /// A altura das três tabelas da tela (relatório, totais e histórico) — uma
  /// constante, e não `360` três vezes (item F4). A altura FIXA dentro da
  /// página rolável é aceita de propósito: a tela 13 é de desktop (wireframes
  /// §16, e o §17 registra que no celular não há seletor de arquivo), e uma
  /// lista de ocorrências que crescesse com o conteúdo empurraria os passos 4
  /// e o histórico para fora de vista num arquivo de mil linhas. Divergência
  /// registrada em `docs/design-system.md` §11 (item D5).
  static const _alturaTabela = 360.0;

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

  /// Retoma um lote pelo histórico (item A5): o estado do assistente morre com
  /// a página, e sem isto um lote VALIDADA ficava órfão depois de um F5 — nem
  /// relatório, nem totais, nem Simular/Aplicar. Os providers já são por id;
  /// o que faltava era ligar. O passo 3 lê o relatório daquele lote; o 4
  /// mostra os totais de um APLICADA e Simular/Aplicar de um VALIDADA.
  void _retomar(LoteImportacao lote) {
    setState(() {
      _loteId = lote.id;
      _resultado = null;
      _erro = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final contexto = _chaveRelatorio.currentContext;
      if (contexto != null && mounted) Scrollable.ensureVisible(contexto);
    });
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ O `AsyncValue` INTEIRO, e não `.value` (item A4): `loading` e `error`
    // viravam `null`, e `null` era tratado como "ainda não há lote" — depois de
    // Validar, com a leitura do lote falhando, o passo 4 mandava "valide no
    // passo 2" a quem acabou de validar; e o mesmo texto piscava em toda
    // validação normal, entre o `registrar` voltar e o lote chegar. É o B1 do
    // 5.11 e o A3 do 8.1,5 outra vez: `AsyncValue` que decide texto precisa
    // dos três estados.
    final loteId = _loteId;
    final loteAsync = loteId == null
        ? null
        : ref.watch(loteImportacaoProvider(loteId));
    final lote = loteAsync?.value;

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
                key: _chaveRelatorio,
                numero: 3,
                titulo: 'Relatório',
                ativo: _loteId != null,
                filho: _passoRelatorio(loteAsync),
              ),
              _Passo(
                numero: 4,
                titulo: 'Aplicar',
                ativo: lote?.podeAplicar ?? false,
                filho: _passoAplicar(context, loteAsync),
                ultimo: true,
              ),
              const SizedBox(height: Dim.e24),
              _Historico(aoAbrir: _retomar),
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
          '${plural(lido.totalLinhas, 'linha', 'linhas')} em '
          '${plural(lido.contagens.length, 'entidade', 'entidades')}.',
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
  Widget _passoRelatorio(AsyncValue<LoteImportacao?>? loteAsync) {
    final id = _loteId;
    if (id == null || loteAsync == null) {
      return const Text(
        textoImportacaoAguardandoValidacao,
        style: Tipografia.apoio,
      );
    }
    // `hasError` antes de tudo (design-system §5.6), e o carregamento sem
    // valor com esqueleto — nunca o texto de "valide no passo 2".
    if (loteAsync.hasError) return _erroDoLote(id);
    final lote = loteAsync.value;
    if (lote == null) return const EstadoCarregando(linhas: 1);

    final ocorrencias = ref.watch(ocorrenciasImportacaoProvider(id));
    final resumo = resumoPorCodigo(ocorrencias.value ?? const []);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${plural(lote.erros, 'erro', 'erros')} · '
          '${plural(lote.avisos, 'aviso', 'avisos')} — '
          '${rotuloStatusLote(lote.status)}.',
          style: Tipografia.corpo,
        ),
        const SizedBox(height: Dim.e4),
        const Text(textoImportacaoSeveridade, style: Tipografia.apoio),
        // O resumo POR CÓDIGO (item E2): é a leitura do §16 ("20 sem turma ·
        // 2 códigos divergentes") sem view nova — contagem em Dart sobre a
        // lista já carregada, e é o que a revisão das exceções (card 9.3)
        // quer ver primeiro. Chips no molde do passo 2.
        if (resumo.isNotEmpty) ...[
          const SizedBox(height: Dim.e8),
          Wrap(
            spacing: Dim.e8,
            runSpacing: Dim.e8,
            children: [
              for (final item in resumo)
                Chip(
                  avatar: Icon(
                    item.bloqueia
                        ? Icons.error_outline
                        : Icons.warning_amber_outlined,
                    size: 16,
                  ),
                  label: Text(
                    '${item.total} × ${rotuloCodigoOcorrencia(item.codigo)}',
                  ),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
        const SizedBox(height: Dim.e12),
        SizedBox(
          height: _alturaTabela,
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
        // O motivo do botão acompanha o ESTADO da leitura (item B4): "não há
        // ocorrências" enquanto carrega afirmaria o que ainda não se sabe, e
        // em erro o botão fica ausente — a tabela já mostra o `EstadoErro`.
        if (!ocorrencias.hasError)
          Align(
            alignment: Alignment.centerLeft,
            child: BotaoAcao(
              rotulo: 'Baixar relatório',
              icone: Icons.download_outlined,
              nivel: NivelBotao.terciario,
              aoTocar: _motivoParaBaixar(ocorrencias) != null
                  ? null
                  : () => baixarTexto(
                      'relatorio-importacao.csv',
                      relatorioEmCsv(ocorrencias.value ?? const []),
                    ),
              desabilitado: _motivoParaBaixar(ocorrencias),
            ),
          ),
      ],
    );
  }

  DesabilitadoCom? _motivoParaBaixar(
    AsyncValue<List<OcorrenciaImportacao>> ocorrencias,
  ) {
    final lista = ocorrencias.value;
    if (lista == null) {
      return const DesabilitadoCom(textoImportacaoRelatorioCarregando);
    }
    if (lista.isEmpty) {
      return const DesabilitadoCom(textoImportacaoNadaParaBaixar);
    }
    if (!baixarDisponivel) {
      return const DesabilitadoCom(textoImportacaoSemDownload);
    }
    return null;
  }

  /// O lote não pôde ser lido: erro compacto com "Tentar de novo", nos passos
  /// 3 e 4 (item A4).
  Widget _erroDoLote(String id) => EstadoErro(
    mensagem: textoImportacaoLoteNaoLido,
    aoRepetir: () => ref.invalidate(loteImportacaoProvider(id)),
  );

  // -------------------------------------------------------------------------
  // ④ Aplicar — simulação primeiro, e o ambiente no rótulo do botão
  // -------------------------------------------------------------------------
  Widget _passoAplicar(
    BuildContext context,
    AsyncValue<LoteImportacao?>? loteAsync,
  ) {
    final id = _loteId;
    if (id == null || loteAsync == null) {
      return const Text(
        textoImportacaoAguardandoValidacao,
        style: Tipografia.apoio,
      );
    }
    if (loteAsync.hasError) return _erroDoLote(id);
    final lote = loteAsync.value;
    if (lote == null) return const EstadoCarregando(linhas: 1);
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
        // Card 9.2,65: aplicada a importação, projeção, pedido sugerido e
        // pendências só existiam depois da rotina da madrugada. Sem
        // `parametros.gerir` a faixa inteira some — o texto sem o botão seria
        // uma promessa que a pessoa não pode cumprir.
        if (aplicado &&
            ref.watch(permissoesProvider).contains(permissaoRecalcular)) ...[
          const SizedBox(height: Dim.e12),
          const Text(textoRecalcularDepoisDeAplicar, style: Tipografia.apoio),
          const SizedBox(height: Dim.e8),
          const Align(
            alignment: Alignment.centerLeft,
            child: BotaoRecalcularAgora(nivel: NivelBotao.secundario),
          ),
        ],
        const SizedBox(height: Dim.e8),
        SizedBox(
          height: _alturaTabela,
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
///
/// ⚠️ O passo inativo esmaece **a moldura e o número**, nunca o texto (item D2
/// da revisão das telas 08/09). Antes era `Opacity(0.6)` no passo inteiro, e
/// isso derrubava o `onSurfaceVariant` (5,06:1 sobre branco) para **2,36:1** —
/// abaixo do 4,5:1 do design-system §8.1 — justamente nos textos "Valide o
/// arquivo no passo 2…" e "Escolha um arquivo no passo 1…", que são os que a
/// pessoa precisa ler para saber o que falta.
class _Passo extends StatelessWidget {
  const _Passo({
    super.key,
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
    // Passo ainda inalcançável fica esmaecido, e não escondido: sumir muda a
    // numeração e a pessoa perde a referência do que vem depois.
    return Container(
      margin: EdgeInsets.only(bottom: ultimo ? 0 : Dim.e16),
      padding: const EdgeInsets.all(Dim.e16),
      decoration: BoxDecoration(
        border: Border.all(
          color: ativo
              ? cores.outlineVariant
              : cores.outlineVariant.withValues(alpha: 0.5),
        ),
        borderRadius: BorderRadius.circular(Dim.raio),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: ativo
                    ? cores.secondaryContainer
                    : cores.surfaceContainerHighest,
                child: Text(
                  '$numero',
                  style: Tipografia.badge.copyWith(
                    color: ativo
                        ? cores.onSecondaryContainer
                        : cores.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: Dim.e8),
              // `Expanded`, e não `Text` solto: em 390 px o título do passo
              // 4 ("Aplicar") vem acompanhado do círculo do número, e o
              // conjunto estourava a `Row` pela mesma via do item 19 do §11
              // do design-system — a barra de ações da TabelaIm360, medida no
              // card 8.1,5.
              Expanded(
                child: Text(
                  titulo,
                  style: Tipografia.subtitulo.copyWith(
                    color: ativo ? null : cores.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Dim.e12),
          // O texto do passo inativo em `onSurfaceVariant` PLENO — é o par
          // verificado, e ele continua legível.
          ativo
              ? filho
              : DefaultTextStyle.merge(
                  style: TextStyle(color: cores.onSurfaceVariant),
                  child: filho,
                ),
        ],
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
///
/// A linha **abre** o lote no assistente (item A5): é daqui que se retoma um
/// VALIDADA depois de um F5, e que se comparam os totais de dois dry-runs.
class _Historico extends ConsumerWidget {
  const _Historico({required this.aoAbrir});

  final void Function(LoteImportacao lote) aoAbrir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lotes = ref.watch(lotesImportacaoProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Importações anteriores', style: Tipografia.subtitulo),
        const SizedBox(height: Dim.e4),
        const Text(textoImportacaoHistoricoAbre, style: Tipografia.apoio),
        const SizedBox(height: Dim.e8),
        SizedBox(
          height: _TelaImportacaoState._alturaTabela,
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
            aoTocarLinha: aoAbrir,
            cartao: (l) => CartaoIm360(
              titulo: l.arquivo,
              subtitulo:
                  '${rotuloStatusLote(l.status)} · '
                  '${plural(l.erros, 'erro', 'erros')} · '
                  '${plural(l.avisos, 'aviso', 'avisos')}',
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
