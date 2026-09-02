// =============================================================================
// Asserção do próprio portão — card 4.0,5.
//
// Portão sem teste é decoração, doença que o card 2.8 catalogou: ele passaria a
// dizer "verde" no dia em que parasse de ler o que devia. Os casos vivem em
// `casos/`, como SQL de verdade, porque é SQL de verdade que o varredor lê.
// =============================================================================

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

import {
  varrerSql,
  varrerConjunto,
  listarMigracoes,
  TABELAS_PERMITIDAS,
} from '../varredor.mjs';

const CASOS = fileURLToPath(new URL('./casos/', import.meta.url));
const RAIZ = fileURLToPath(new URL('../../', import.meta.url));

const caso = (nome) => varrerSql(nome, readFileSync(join(CASOS, nome), 'utf8'));
const barradas = (rel) => rel.arquivos.flatMap((a) => a.barradas);
const permitidas = (rel) => rel.arquivos.flatMap((a) => a.permitidas);

// --- os três casos que a nota do card exige -------------------------------

test('(a) insert em aluno no topo da migração reprova', () => {
  const rel = caso('reprova-insert-no-topo.sql');
  assert.equal(rel.aprovado, false);
  assert.equal(barradas(rel).length, 1);
  assert.match(barradas(rel)[0].motivo, /insert into aluno/);
  assert.equal(barradas(rel)[0].local, 'reprova-insert-no-topo.sql:2');
});

test('(b) insert em pendencia dentro de corpo de função passa', () => {
  const rel = caso('passa-corpo-de-funcao.sql');
  assert.equal(rel.aprovado, true);
  assert.deepEqual(barradas(rel), []);
  assert.deepEqual(permitidas(rel), []);
});

test('(c) insert em material dentro de bloco do $$ reprova', () => {
  const rel = caso('reprova-bloco-do.sql');
  assert.equal(rel.aprovado, false);
  assert.match(barradas(rel)[0].motivo, /insert into material/);
});

// --- o disfarce que o precedente do card 3.6 torna natural ----------------

test('função de seed chamada pela migração conta como escrita da migração', () => {
  const rel = caso('reprova-funcao-de-seed-chamada.sql');
  assert.equal(rel.aprovado, false);
  const b = barradas(rel);
  assert.equal(b.length, 1);
  assert.match(b[0].motivo, /insert into curso/);
  // o caminho é o que torna o vermelho acionável: quem chamou quem
  assert.deepEqual(b[0].caminho, ['fn_seed_catalogo()', 'fn_seed_cursos()']);
});

// --- o que NÃO pode virar falso positivo ----------------------------------

test('comentário e literal que citam insert into aluno passam', () => {
  assert.equal(caso('passa-comentario-e-literal.sql').aprovado, true);
});

test('create trigger … execute function não é chamada da função', () => {
  const rel = caso('passa-trigger-nao-chama.sql');
  assert.equal(rel.aprovado, true, JSON.stringify(barradas(rel)));
});

test('on update cascade, for update e grant insert não são escrita', () => {
  const rel = caso('passa-ddl-parecido.sql');
  assert.equal(rel.aprovado, true, JSON.stringify(barradas(rel)));
});

// --- as outras formas de gravar -------------------------------------------

test('update, delete, truncate e copy contam como escrita', () => {
  const rel = caso('reprova-outras-escritas.sql');
  assert.equal(rel.aprovado, false);
  const ops = barradas(rel).map((b) => b.op).sort();
  assert.deepEqual(ops, ['copy', 'delete from', 'truncate', 'update']);
});

test('SQL montado em tempo de execução reprova por não ser legível', () => {
  const rel = caso('reprova-execute-dinamico.sql');
  assert.equal(rel.aprovado, false);
  assert.match(barradas(rel)[0].motivo, /din[âa]mico/i);
});

test('execute com o comando inteiro num literal reprova nomeando a tabela', () => {
  const rel = caso('reprova-execute-literal.sql');
  assert.equal(rel.aprovado, false);
  assert.match(barradas(rel)[0].motivo, /insert into material/);
});

test('escrita em auth.users reprova: o esquema não é o público permitido', () => {
  const rel = caso('reprova-auth-users.sql');
  assert.equal(rel.aprovado, false);
  assert.match(barradas(rel)[0].motivo, /auth\.users/);
});

test('SQL que o portão não consegue ler reprova (fail-closed)', () => {
  const rel = caso('reprova-nao-legivel.sql');
  assert.equal(rel.aprovado, false);
  assert.equal(rel.erros.length, 1);
  assert.match(rel.erros[0].motivo, /não fechado/);
});

// --- todos os casos, pelo nome do arquivo ---------------------------------

test('cada caso de casos/ tem o veredito que o nome promete', () => {
  const nomes = readdirSync(CASOS).filter((n) => n.endsWith('.sql')).sort();
  assert.ok(nomes.length >= 13, 'os casos sumiram');
  for (const nome of nomes) {
    const esperado = nome.startsWith('passa-');
    assert.equal(caso(nome).aprovado, esperado, `${nome}: veredito inesperado`);
  }
});

test('a migração do card 4.1 passa: estrutura mais as três linhas de metodo', () => {
  const rel = caso('passa-metodo-do-card-4-1.sql');
  assert.equal(rel.aprovado, true, JSON.stringify(barradas(rel)));
  assert.deepEqual([...new Set(permitidas(rel).map((p) => p.tabela))], ['metodo']);
});

// --- as migrações que já existem ------------------------------------------

test('as migrações do repositório passam, o seed do card 3.6 incluído', () => {
  const arquivos = listarMigracoes([join(RAIZ, 'supabase/migrations')]);
  assert.ok(arquivos.length >= 4, 'nenhuma migração encontrada');
  const rel = varrerConjunto(arquivos);
  assert.equal(rel.aprovado, true, JSON.stringify(barradas(rel), null, 2));

  // O seed é o caso limite: grava dado, e dado permitido. Se ele parar de
  // aparecer aqui, o portão deixou de enxergar a chamada `perform fn_seed_*`.
  const seed = rel.arquivos.find((a) => a.arquivo.includes('seed_inicial_acesso'));
  const tabelas = [...new Set(seed.permitidas.map((p) => p.tabela))].sort();
  assert.deepEqual(tabelas,
    ['parametro', 'perfil', 'perfil_permissao', 'permissao', 'unidade', 'usuario_perfil']);
});

test('a lista permitida é a decidida em 02/09/2026', () => {
  assert.deepEqual([...TABELAS_PERMITIDAS].sort(), [
    'metodo', 'parametro', 'perfil', 'perfil_permissao',
    'permissao', 'unidade', 'usuario', 'usuario_perfil',
  ]);
});
