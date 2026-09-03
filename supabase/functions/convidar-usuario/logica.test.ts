// Suíte da lógica pura da Edge Function (card 4.7). Roda com
// `node --test "supabase/functions/**/*.test.ts"` — sem Deno, sem rede, sem
// dependência: Node 24 lê TypeScript com anotações de tipo sem transpilar.
import assert from "node:assert/strict";
import { test } from "node:test";

import {
  extrairCodigo,
  lerPedido,
  resposta,
  respostaDeErroAuth,
} from "./logica.ts";

test("pedido válido: e-mail normalizado em minúsculas, nome sem espaços nas pontas", () => {
  const r = lerPedido({ email: " Debora@Escola.TEST ", nome: "  Débora Lima " });
  assert.equal(r.ok, true);
  if (r.ok) {
    assert.equal(r.pedido.email, "debora@escola.test");
    assert.equal(r.pedido.nome, "Débora Lima");
    assert.equal(r.pedido.redirecionarPara, undefined);
  }
});

test("destino do link: aceito em http(s), recusado fora disso", () => {
  const ok = lerPedido({ email: "a@b.co", nome: "A", redirecionar_para: "https://app.gestaoim360.com/redefinir-senha" });
  assert.equal(ok.ok, true);
  if (ok.ok) assert.equal(ok.pedido.redirecionarPara, "https://app.gestaoim360.com/redefinir-senha");

  const ruim = lerPedido({ email: "a@b.co", nome: "A", redirecionar_para: "javascript:alert(1)" });
  assert.equal(ruim.ok, false);
  if (!ruim.ok) {
    assert.equal(ruim.status, 400);
    assert.equal(ruim.corpo.codigo, "DESTINO_INVALIDO");
  }
});

test("corpo que não é objeto, e-mail sem formato e nome vazio são 400 com código", () => {
  for (const [corpo, codigo] of [
    [null, "CORPO_INVALIDO"],
    ["texto", "CORPO_INVALIDO"],
    [{ email: "sem-arroba", nome: "X" }, "EMAIL_INVALIDO"],
    [{ email: "a@b.co", nome: "   " }, "NOME_OBRIGATORIO"],
    [{ nome: "X" }, "EMAIL_INVALIDO"],
  ] as const) {
    const r = lerPedido(corpo);
    assert.equal(r.ok, false, `${JSON.stringify(corpo)} deveria ser recusado`);
    if (!r.ok) {
      assert.equal(r.status, 400);
      assert.equal(r.corpo.codigo, codigo);
    }
  }
});

test("extrairCodigo acha o codigo do DETAIL onde quer que o GoTrue o tenha posto", () => {
  // Na mensagem, como o card 3.5 mediu na Admin API…
  assert.equal(
    extrairCodigo({ message: 'Database error: {"codigo":"USUARIO_SEM_UNIDADE","unidades_ativas":2}' }),
    "USUARIO_SEM_UNIDADE",
  );
  // …ou num campo qualquer do objeto de erro.
  assert.equal(
    extrairCodigo({ message: "x", details: { codigo: "USUARIO_SEM_EMAIL" } }),
    "USUARIO_SEM_EMAIL",
  );
  // Sem código nenhum: undefined, nunca uma string vazia ou inventada.
  assert.equal(extrairCodigo({ message: "User already registered" }), undefined);
  assert.equal(extrairCodigo("texto solto"), undefined);
});

test("respostaDeErroAuth: status do GoTrue quando é HTTP, 500 quando não é; codigo e code passam", () => {
  const recusaDoBanco = respostaDeErroAuth({
    status: 422,
    code: "unexpected_failure",
    message: '{"codigo":"USUARIO_SEM_UNIDADE"}',
  });
  assert.equal(recusaDoBanco.status, 422);
  assert.equal(recusaDoBanco.corpo.codigo, "USUARIO_SEM_UNIDADE");
  assert.equal(recusaDoBanco.corpo.code, "unexpected_failure");

  const jaExiste = respostaDeErroAuth({ status: 422, code: "email_exists", message: "already" });
  assert.equal(jaExiste.status, 422);
  assert.equal(jaExiste.corpo.codigo, undefined);
  assert.equal(jaExiste.corpo.code, "email_exists");

  const semStatus = respostaDeErroAuth({ message: "rede caiu" });
  assert.equal(semStatus.status, 500);
  assert.equal(semStatus.corpo.mensagem, "rede caiu");

  const statusEstranho = respostaDeErroAuth({ status: 0, message: "?" });
  assert.equal(statusEstranho.status, 500);
});

test("resposta: JSON com CORS e content-type", async () => {
  const r = resposta(403, { codigo: "SEM_PERMISSAO", mensagem: "não" });
  assert.equal(r.status, 403);
  assert.equal(r.headers.get("Access-Control-Allow-Origin"), "*");
  assert.match(r.headers.get("Content-Type") ?? "", /application\/json/);
  assert.deepEqual(await r.json(), { codigo: "SEM_PERMISSAO", mensagem: "não" });
});
