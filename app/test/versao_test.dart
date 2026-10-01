import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_im360/config/ambiente.dart';
import 'package:gestao_im360/widgets/versao.dart';

/// Card 9.2,83: a versão é a do `pubspec.yaml`, semântica, e chega ao app pelo
/// `FLUTTER_BUILD_NAME` que o próprio Flutter define em todo build. Sem define
/// manual — e por isso sem um segundo lugar onde o número possa divergir.
void main() {
  final linha = File('pubspec.yaml')
      .readAsLinesSync()
      .firstWhere((l) => l.startsWith('version:'));
  final nome = RegExp(r'^version:\s*(\d+\.\d+\.\d+)\+\d+\s*$')
      .firstMatch(linha)
      ?.group(1);

  test('o pubspec tem MAJOR.MINOR.REVISION+BUILD', () {
    expect(nome, isNotNull, reason: linha);
  });

  test('a tela mostra o nome da versão do pubspec, sem o +BUILD', () {
    // O `flutter test` também define FLUTTER_BUILD_NAME a partir do pubspec;
    // `local` só aparece num build feito sem o Flutter (não existe no CI).
    expect(Ambiente.versao, nome);
    expect(textoVersao, 'Versão $nome');
  });
}
