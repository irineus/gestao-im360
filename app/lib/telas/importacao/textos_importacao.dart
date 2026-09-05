/// Textos finais da tela 13 (docs/design-system.md §7.2 e §7.3, card 9.1).
///
/// Ficam num arquivo só, e não espalhados na tela, pelo mesmo motivo das outras
/// doze: o `texto_de_tela_test` varre este arquivo atrás de glifo que a Inter e
/// a Roboto não têm — o `✖`/`⚠` do wireframe §16 é exatamente desse tipo, e no
/// bundle ele viraria uma caixa vazia (divergência 13 do §11, card 6.6).
library;

import '../../importacao/importacao.dart';

/// Rótulo do ambiente para quem lê, não para quem faz deploy. `Ambiente.
/// ambiente` vale `local`, `homologacao` ou `producao` (card 3.8).
String rotuloAmbiente(String codigo) => switch (codigo) {
  'producao' => 'PRODUÇÃO',
  'homologacao' => 'homologação',
  'local' => 'ambiente local',
  _ => codigo,
};

String textoFaixaAmbiente(String ambiente) =>
    'Você está em $ambiente. A importação grava direto neste ambiente, e as '
    'telas são iguais nos dois — confira antes de aplicar.';

const textoImportacaoArquivo =
    'O arquivo é o JSON gerado pelo script de extração da planilha. '
    'Escolher um arquivo novo descarta a validação anterior.';

const textoImportacaoSnapshot =
    'A data do snapshot da PLANILHA, não a de hoje: comparar totais tirados de '
    'dias diferentes é divergir por nada.';

const textoImportacaoSnapshotFalta =
    'Informe a data do snapshot da planilha (dd/mm/aaaa).';

const textoImportacaoSemSeletor =
    'A importação é feita no navegador, em um computador. Abra '
    'gestaoim360.com nesta mesma conta para carregar a planilha.';

const textoImportacaoAguardandoArquivo =
    'Escolha um arquivo no passo 1 para ver o que ele traz.';

const textoImportacaoAguardandoValidacao =
    'Valide o arquivo no passo 2 para ver o relatório.';

String textoEntidadesDesconhecidas(List<String> chaves) =>
    'O arquivo traz ${chaves.join(', ')}, que a importação não conhece. '
    'Essas listas serão ignoradas — confira se o script de extração é o desta '
    'versão.';

/// A legenda do §16 ("✖ bloqueia aplicar · ⚠ aplica com pendência") em palavras.
/// Os dois glifos ficaram de fora de propósito: nem Inter nem Roboto os têm.
const textoImportacaoSeveridade =
    'Erro bloqueia a aplicação e precisa ser corrigido no arquivo. Aviso não '
    'bloqueia: a linha entra e fica registrada para revisão.';

const textoImportacaoSemOcorrencias =
    'Nenhum erro e nenhum aviso — o arquivo pode ser aplicado.';

const textoImportacaoSemHistorico =
    'Nenhuma importação ainda. A primeira será a carga da planilha.';

const textoImportacaoNadaParaBaixar =
    'Não há ocorrências para baixar neste relatório.';

const textoImportacaoSemDownload =
    'O download do relatório funciona no navegador.';

const textoImportacaoSimulacao =
    'A simulação escreve tudo e desfaz no fim, para mostrar os totais que a '
    'aplicação produziria. Ela é obrigatória antes de aplicar.';

const textoImportacaoSimuleAntes =
    'Simule primeiro: é a simulação que mostra o que a aplicação vai gravar.';

const textoImportacaoReprovada =
    'Este arquivo tem erros e não pode ser aplicado. Corrija o arquivo e valide '
    'de novo.';

const textoImportacaoFalhou =
    'A aplicação foi desfeita por inteiro e nada foi gravado. O motivo está no '
    'relatório acima; corrija o arquivo e valide de novo.';

const textoImportacaoSemTotais =
    'Sem totais para mostrar — simule ou aplique para vê-los.';

const textoTotaisSimulados =
    'Totais da simulação: o que a aplicação gravaria. Nada foi escrito.';

const textoTotaisAplicados =
    'Totais aplicados. A coluna "No sistema" é a que se compara com o '
    'Dashboard da planilha.';

String textoConfirmarAplicacao(String ambiente) =>
    'A carga será gravada em $ambiente, numa transação só: ou entra tudo, ou '
    'não entra nada. Aplicar de novo o mesmo arquivo não duplica o que já '
    'entrou.';

String textoFalhaAplicacao(String motivo) =>
    'O banco recusou uma linha e a importação inteira foi desfeita. $motivo';

/// O relatório completo do passo 3, em CSV — é o que o `[baixar relatório
/// completo]` do §16 entrega.
///
/// Separador `;` e não `,`: quem abre isto abre no Excel em português, onde a
/// vírgula é decimal e o arquivo com `,` cai todo numa coluna só. As aspas são
/// dobradas, que é o escape do próprio formato.
String relatorioEmCsv(List<OcorrenciaImportacao> ocorrencias) {
  final linhas = <String>['severidade;entidade;linha;codigo;mensagem;valor'];
  for (final o in ocorrencias) {
    linhas.add(
      [
        o.severidade,
        o.entidade,
        o.linha?.toString() ?? '',
        o.codigo,
        o.mensagem,
        o.valor ?? '',
      ].map(_csv).join(';'),
    );
  }
  return linhas.join('\r\n');
}

String _csv(String valor) => valor.contains(RegExp('[;"\n\r]'))
    ? '"${valor.replaceAll('"', '""')}"'
    : valor;
