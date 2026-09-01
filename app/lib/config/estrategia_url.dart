/// Escolha da estratégia de URL do Flutter web (card 3.8).
///
/// `flutter_web_plugins` só existe no web; a importação condicional deixa o
/// Android e o iOS compilarem com uma função vazia.
library;

export 'estrategia_url_nativo.dart'
    if (dart.library.js_interop) 'estrategia_url_web.dart';
