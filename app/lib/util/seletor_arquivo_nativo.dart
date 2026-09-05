import '../importacao/importacao.dart';

/// Fora do navegador não há seletor, e isso é **decisão**, não pendência.
///
/// A tela 13 é da direção, em desktop, e a carga acontece contra um ambiente
/// escolhido na hora — o celular não é onde isso se faz. Devolver `null` deixa a
/// tela dizer a frase certa (`textoImportacaoSemSeletor`, em
/// `docs/design-system.md` §7.2) em vez de abrir um seletor que não abriria
/// arquivo nenhum.
const seletorDeArquivoDisponivel = false;

Future<ArquivoEscolhido?> escolherArquivo() async => null;

/// Baixar o relatório é a outra metade da mesma decisão: fora do navegador não
/// há "pasta de downloads" para onde mandá-lo sem pedir permissão de sistema, e
/// esta tela não roda no celular.
const baixarDisponivel = false;

void baixarTexto(String nome, String conteudo) {}
