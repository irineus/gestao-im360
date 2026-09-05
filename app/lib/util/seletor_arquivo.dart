/// Escolha de um arquivo da máquina de quem está usando o app (card 9.1).
///
/// A importação é operação de **navegador**, feita pela direção, uma vez na vida
/// do sistema (e algumas no dry-run do card 9.4): o `<input type="file">` do
/// próprio HTML é o seletor, e o Android/iOS ficam com a implementação que diz
/// isso em voz alta em vez de abrir um seletor que não leva a lugar nenhum.
///
/// A importação condicional é a mesma de `lib/config/estrategia_url.dart`
/// (card 3.8): o web tem `dart.library.js_interop`, o nativo não.
library;

export 'seletor_arquivo_nativo.dart'
    if (dart.library.js_interop) 'seletor_arquivo_web.dart';
