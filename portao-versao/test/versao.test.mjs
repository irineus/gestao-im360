import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import { lerVersao, veredito, VERSAO_DE_FABRICA } from '../versao.mjs';

const pub = (v) => `name: gestao_im360\nversion: ${v}\n\nenvironment:\n  sdk: ^3.13.2\n`;
const caso = (base, cabeca, arquivos) =>
  veredito({ arquivos, pubspecBase: pub(base), pubspecCabeca: pub(cabeca) });

test('lê MAJOR.MINOR.REVISION+BUILD e recusa o resto', () => {
  assert.deepEqual(lerVersao(pub('0.1.0+1')).partes, [0, 1, 0]);
  assert.equal(lerVersao(pub('0.12.3+40')).build, 40);
  assert.throws(() => lerVersao(pub('0.1+1')), /MAJOR\.MINOR\.REVISION\+BUILD/);
  assert.throws(() => lerVersao(pub('0.1.0')), /MAJOR\.MINOR\.REVISION\+BUILD/);
  assert.throws(() => lerVersao('name: x\n'), /sem a linha/);
});

test('código novo SEM subir a versão reprova — o caso que o portão existe para pegar', () => {
  const r = caso('0.1.0+1', '0.1.0+1', ['app/lib/telas/login.dart']);
  assert.equal(r.ok, false);
  assert.match(r.mensagens.join('\n'), /0\.1\.1\+2/);
});

test('cada caminho de código conta: migração, Edge Function, web, worker', () => {
  for (const f of [
    'supabase/migrations/20261001120000_x.sql',
    'supabase/functions/convidar-usuario/index.ts',
    'app/web/_headers',
    'worker-vigia/src/vigia.js',
  ]) {
    assert.equal(caso('0.1.0+1', '0.1.0+1', [f]).ok, false, f);
  }
});

test('subir a REVISION com o BUILD passa', () => {
  assert.equal(caso('0.1.0+1', '0.1.1+2', ['app/lib/main.dart']).ok, true);
});

test('subir a MINOR zerando a REVISION passa', () => {
  assert.equal(caso('0.1.7+8', '0.2.0+9', ['app/lib/main.dart']).ok, true);
});

test('subir o nome sem o BUILD reprova', () => {
  assert.equal(caso('0.1.0+1', '0.1.1+1', ['app/lib/main.dart']).ok, false);
});

test('a versão nunca desce, nem sem código', () => {
  assert.equal(caso('0.1.3+4', '0.1.2+5', ['docs/x.md']).ok, false);
  assert.equal(caso('0.1.3+4', '0.1.4+3', ['docs/x.md']).ok, false);
});

test('sem código novo (testes, docs, workflow) a versão pode ficar', () => {
  const arquivos = [
    'app/test/login_test.dart',
    'docs/deploy-web.md',
    '.github/workflows/testes.yml',
    'supabase/tests/098_projecao_acuracia.sql',
  ];
  assert.equal(caso('0.1.0+1', '0.1.0+1', arquivos).ok, true);
});

test('MAJOR mudou: passa, mas AVISA — só Irineu decide', () => {
  const r = caso('0.9.0+10', '1.0.0+11', ['app/lib/main.dart']);
  assert.equal(r.ok, true);
  assert.match(r.mensagens.join('\n'), /MAJOR mudou/);
});

test('a única descida aceita é sair da versão de fábrica do flutter create', () => {
  assert.equal(VERSAO_DE_FABRICA, '1.0.0+1');
  assert.equal(caso('1.0.0+1', '0.1.0+1', ['app/lib/main.dart']).ok, true);
  // Contraprova de 01/10/2026: ficar na de fábrica com código novo passava.
  assert.equal(caso('1.0.0+1', '1.0.0+1', ['app/lib/main.dart']).ok, false);
  assert.equal(caso('1.0.0+1', '1.0.0+1', ['docs/x.md']).ok, true);
});

test('o pubspec do repositório está no formato', () => {
  const raiz = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
  const texto = readFileSync(join(raiz, 'app', 'pubspec.yaml'), 'utf8');
  assert.doesNotThrow(() => lerVersao(texto));
});
