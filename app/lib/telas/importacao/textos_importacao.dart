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

/// O lote não pôde ser lido depois de validar (item A4 da revisão das telas
/// 08/09). É erro, e não "valide de novo": a pessoa acabou de validar.
const textoImportacaoLoteNaoLido =
    'Não foi possível ler o resultado da validação. Tente de novo; se '
    'continuar, o lote está registrado e aparece nas importações anteriores.';

/// O motivo do "Baixar relatório" enquanto as ocorrências carregam (item B4):
/// "não há ocorrências" seria afirmar o que ainda não se sabe.
const textoImportacaoRelatorioCarregando = 'O relatório ainda está carregando.';

/// O rótulo de cada código de ocorrência, para o resumo por código do passo 3
/// (item E2: o §16 desenha "265 alunos lidos · 20 sem turma · 2 códigos
/// divergentes", e um resumo por código é o que o 9.3 quer ver primeiro). A
/// lista é a das dezesseis verificações de `docs/importacao.md` §5; código que
/// a tela não conhece aparece como está, porque esconder seria pior.
String rotuloCodigoOcorrencia(String codigo) => switch (codigo) {
  'ENTIDADE_INVALIDA' => 'Entidade em formato inválido',
  'ENTIDADE_DESCONHECIDA' => 'Entidade desconhecida',
  'CAMPO_OBRIGATORIO' => 'Campo obrigatório vazio',
  'VALOR_INVALIDO' => 'Valor inválido',
  'DATA_INVALIDA' => 'Data inválida',
  'CHAVE_DUPLICADA' => 'Chave duplicada no arquivo',
  'REFERENCIA_AUSENTE' => 'Referência inexistente',
  'METODO_INCOMPATIVEL' => 'Método incompatível',
  'ALUNO_INATIVO' => 'Aluno inativo em turma',
  'SALDO_NEGATIVO' => 'Saldo negativo',
  'ALUNO_SEM_TURMA' => 'Aluno sem turma',
  'PREVISAO_ATIPICA' => 'Previsão atípica',
  'ENTREGA_SEM_SAIDA' => 'Entrega sem saída de estoque',
  'SAIDA_SEM_ENTREGA' => 'Saída de estoque sem entrega',
  'PC_SEM_MANUTENCAO' => 'PC em manutenção sem registro',
  'SAIDA_SEM_ALUNO' => 'Saída de estoque sem aluno',
  'STATUS_DIVERGENTE' => 'Status divergente do sistema',
  _ => codigo,
};

/// "20 × Aluno sem turma" — as contagens por código, ERRO primeiro e depois
/// por quantidade, derivadas da lista já carregada. É contagem de tela, não
/// regra: a severidade e o código vieram do banco.
List<({String codigo, bool bloqueia, int total})> resumoPorCodigo(
  List<OcorrenciaImportacao> ocorrencias,
) {
  final contagens = <String, ({bool bloqueia, int total})>{};
  for (final o in ocorrencias) {
    final atual = contagens[o.codigo];
    contagens[o.codigo] = (
      bloqueia: (atual?.bloqueia ?? false) || o.bloqueia,
      total: (atual?.total ?? 0) + 1,
    );
  }
  final resumo = [
    for (final e in contagens.entries)
      (codigo: e.key, bloqueia: e.value.bloqueia, total: e.value.total),
  ];
  resumo.sort((a, b) {
    if (a.bloqueia != b.bloqueia) return a.bloqueia ? -1 : 1;
    if (a.total != b.total) return b.total.compareTo(a.total);
    return a.codigo.compareTo(b.codigo);
  });
  return resumo;
}

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

/// O que o toque numa linha do histórico faz (item A5).
const textoImportacaoHistoricoAbre =
    'Toque numa importação para abrir o relatório e os totais dela. Um lote '
    'validado e ainda não aplicado pode ser simulado e aplicado daqui.';

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
