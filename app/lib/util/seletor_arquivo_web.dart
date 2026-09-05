import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../importacao/importacao.dart';

const seletorDeArquivoDisponivel = true;

/// Abre o seletor do navegador e devolve nome + conteúdo em texto.
///
/// `null` quando a pessoa fecha o seletor sem escolher — que não é erro e não
/// pode virar mensagem de erro.
///
/// ⚠️ O `input` **não é anexado ao documento**. Anexá-lo exigiria removê-lo
/// depois, e o `change` do Chrome não dispara para um elemento já removido —
/// o caso real é a pessoa escolher o arquivo e a tela não reagir. Um `input`
/// solto na memória funciona nos navegadores que o app suporta (card 3.8) e
/// morre com o escopo.
Future<ArquivoEscolhido?> escolherArquivo() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    // O arquivo é o JSON do extrator (card 9.2). O filtro é conveniência, não
    // guarda: quem valida o conteúdo é `ArquivoImportacao.deTexto` e, depois
    // dela, o banco.
    ..accept = '.json,application/json';

  final concluido = Completer<ArquivoEscolhido?>();

  // `cancel` existe desde 2023 e não está em todo navegador que o app suporta;
  // sem ele, fechar o seletor sem escolher deixa o Future pendente para sempre e
  // o botão "Escolher arquivo…" fica girando. Por isso o `cancel` é OPCIONAL e o
  // caminho normal é o `change`.
  input.onchange = (web.Event _) {
    final arquivos = input.files;
    if (arquivos == null || arquivos.length == 0) {
      if (!concluido.isCompleted) concluido.complete(null);
      return;
    }
    final arquivo = arquivos.item(0)!;
    final leitor = web.FileReader();
    leitor.onload = (web.Event _) {
      if (concluido.isCompleted) return;
      concluido.complete(
        ArquivoEscolhido(
          nome: arquivo.name,
          conteudo: (leitor.result as JSString?)?.toDart ?? '',
        ),
      );
    }.toJS;
    leitor.onerror = (web.Event _) {
      if (!concluido.isCompleted) concluido.complete(null);
    }.toJS;
    // UTF-8 explícito: o extrator escreve nomes com acento, e o padrão do
    // FileReader depende da configuração do navegador.
    leitor.readAsText(arquivo, 'utf-8');
  }.toJS;

  input.oncancel = (web.Event _) {
    if (!concluido.isCompleted) concluido.complete(null);
  }.toJS;

  input.click();
  return concluido.future;
}

const baixarDisponivel = true;

/// Baixa um texto como arquivo — o `[baixar relatório completo]` do §16.
///
/// `Blob` + âncora com `download`, e a URL é revogada logo depois: sem isso o
/// blob fica na memória da aba até ela fechar, e quem baixa o relatório de uma
/// carga grande baixa várias vezes seguidas.
void baixarTexto(String nome, String conteudo) {
  final blob = web.Blob(
    [conteudo.toJS].toJS,
    web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  web.HTMLAnchorElement()
    ..href = url
    ..download = nome
    ..click();
  web.URL.revokeObjectURL(url);
}
