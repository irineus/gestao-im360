/// Datas em `dd/mm/aaaa` — sem `intl`: o app não tem localização configurada,
/// e esse é o único formato que a escola usa. Nasceu em
/// `infraestrutura/infraestrutura.dart` (card 4.5) e veio para cá no card 4.6,
/// quando a ficha do aluno precisou das mesmas funções; aquele arquivo continua
/// exportando-as, e nada que já as importava mudou.
library;

String _dois(int n) => n.toString().padLeft(2, '0');

DateTime soData(DateTime d) => DateTime(d.year, d.month, d.day);

String formatarData(DateTime d) =>
    '${_dois(d.day)}/${_dois(d.month)}/${d.year}';

String formatarDataCurta(DateTime d) => '${_dois(d.day)}/${_dois(d.month)}';

/// `dd/mm/aaaa hh:mm`, para carimbos de histórico.
String formatarDataHora(DateTime d) =>
    '${formatarData(d)} ${_dois(d.hour)}:${_dois(d.minute)}';

/// `yyyy-mm-dd`, o formato da coluna `date` no PostgREST.
String dataIso(DateTime d) => '${d.year}-${_dois(d.month)}-${_dois(d.day)}';

final _formatoData = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$');

/// Lê `dd/mm/aaaa`; nulo quando o texto não é uma data real (31/02 inclusive).
DateTime? lerData(String texto) {
  final casa = _formatoData.firstMatch(texto.trim());
  if (casa == null) return null;
  final dia = int.parse(casa[1]!);
  final mes = int.parse(casa[2]!);
  final ano = int.parse(casa[3]!);
  final data = DateTime(ano, mes, dia);
  if (data.day != dia || data.month != mes || data.year != ano) return null;
  return data;
}

/// Validação local só de formato (design-system §5.4): a ordem entre datas e
/// qualquer outra regra quem confere é o banco.
String? validarData(String? valor, {bool obrigatorio = true}) {
  final texto = valor?.trim() ?? '';
  if (texto.isEmpty) return obrigatorio ? 'Campo obrigatório.' : null;
  return lerData(texto) == null ? 'Informe uma data como dd/mm/aaaa.' : null;
}

/// **Hoje em São Paulo** — a mesma data que `fn_hoje()` responde no banco.
///
/// ⚠️ Não é `DateTime.now()`. O relógio do aparelho pode estar em outro fuso
/// (o app é web e roda em qualquer máquina) ou simplesmente errado, e o banco
/// decide por São Paulo: se uma reposição é retroativa, qual é a semana
/// corrente, quando fecha o prazo do débito. Perguntar ao aparelho produziria
/// uma tela que discorda do banco por um dia — sem erro nenhum, que é a família
/// de falha calada que este projeto cataloga.
///
/// O deslocamento é fixo em −3: o Brasil não tem horário de verão desde 2019, e
/// `America/Sao_Paulo` é UTC−3 o ano inteiro. Se voltar a ter, é esta função —
/// uma só — que muda.
DateTime hojeSaoPaulo() {
  final agora = DateTime.now().toUtc().subtract(const Duration(hours: 3));
  return DateTime(agora.year, agora.month, agora.day);
}
