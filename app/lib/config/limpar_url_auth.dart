/// Tira da barra de endereço os parâmetros que o Auth pôs no link (card
/// 9.2,80). Só existe no web; a importação condicional deixa o Android e o iOS
/// compilarem com uma função vazia — o mesmo desenho de `estrategia_url.dart`.
library;

export 'limpar_url_auth_nativo.dart'
    if (dart.library.js_interop) 'limpar_url_auth_web.dart';
