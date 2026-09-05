/// Texto de tela que depende de número.
///
/// Nasceu na revisão das telas 06/07 (item C3): quatro pontos da tela 5
/// escreviam `N módulo(s)` e `N aluno(s)`, a forma que o design-system §7 não
/// usa em lugar nenhum — a aba Trilha já pluralizava direito (`trilha.dart`), e
/// duas formas para a mesma frase é o que esta função encerra.
library;

/// `1 módulo` / `2 módulos` — o número junto, que é como as telas usam.
String plural(int n, String singular, String plural) =>
    '$n ${n == 1 ? singular : plural}';
