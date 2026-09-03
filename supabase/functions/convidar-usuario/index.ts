// Edge Function `convidar-usuario` — card 4.7.
//
// O único caso de Edge Function da v1, e o CLAUDE.md diz por quê: criar usuário
// no Auth exige a Admin API, e a service key NUNCA pode chegar ao Flutter
// (`service_role` tem BYPASSRLS — card 3.3). Ela existe só aqui, na variável de
// ambiente que o Supabase injeta no runtime.
//
// Contrato fixado em docs/acesso-autenticacao.md §3.2, na ordem:
//   1. tem_permissao('admin.gerir_usuarios') no banco, com o TOKEN DE QUEM
//      CHAMA — nunca confiando no que o cliente mandou;
//   2. inviteUserByEmail(email, { data: { nome, unidade_id } }) com a service
//      key;
//   3. o erro do banco volta COMO VEIO: o `codigo` do DETAIL é o que a tela
//      traduz (card 2.7 §7.1).
//
// A unidade do metadado é a do chamador (fn_unidade_atual), e não um campo do
// pedido: convidar é sempre para a própria unidade. Na v1 o espelho do card 3.5
// aceitaria o convite sem metadado (única unidade ativa); mandar a unidade já
// deixa a função pronta para a Fase 11, quando o fallback se fecha sozinho.
//
// Versão fixa do supabase-js pelo mesmo motivo do CLI e do Flutter (card 3.9):
// com `@2`, uma versão nova muda o comportamento sem que nada mude aqui.
import { createClient } from "npm:@supabase/supabase-js@2.114.0";

import {
  cabecalhosCors,
  lerPedido,
  resposta,
  respostaDeErroAuth,
} from "./logica.ts";

const PERMISSAO = "admin.gerir_usuarios";

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cabecalhosCors });
  }
  if (req.method !== "POST") {
    return resposta(405, { codigo: "METODO_INVALIDO", mensagem: "Use POST." });
  }

  const url = Deno.env.get("SUPABASE_URL");
  const chaveAnonima = Deno.env.get("SUPABASE_ANON_KEY");
  const chaveServico = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !chaveAnonima || !chaveServico) {
    // Injetadas pela plataforma; faltar é defeito de ambiente, não do pedido.
    return resposta(500, {
      codigo: "FUNCAO_SEM_AMBIENTE",
      mensagem: "A função não recebeu SUPABASE_URL, SUPABASE_ANON_KEY ou SUPABASE_SERVICE_ROLE_KEY.",
    });
  }

  const autorizacao = req.headers.get("Authorization") ?? "";
  if (!autorizacao.startsWith("Bearer ")) {
    return resposta(401, { codigo: "NAO_AUTENTICADO", mensagem: "Entre no sistema para convidar." });
  }

  let corpo: unknown = null;
  try {
    corpo = await req.json();
  } catch {
    corpo = null;
  }
  const lido = lerPedido(corpo);
  if (!lido.ok) return resposta(lido.status, lido.corpo);
  const pedido = lido.pedido;

  // 1. Quem chama, com o token de quem chama. A chave anônima + o JWT da pessoa
  //    reproduzem exatamente o contexto que o PostgREST daria ao app: RLS
  //    forçada, tem_permissao() lendo a matriz de verdade.
  const chamador = createClient(url, chaveAnonima, {
    global: { headers: { Authorization: autorizacao } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const permissao = await chamador.rpc("tem_permissao", { p_codigo: PERMISSAO });
  if (permissao.error) {
    // Token inválido ou expirado: o PostgREST responde 401 antes de a função
    // rodar. Devolvido como veio, com o código dele.
    return resposta(401, {
      codigo: "NAO_AUTENTICADO",
      code: permissao.error.code,
      mensagem: permissao.error.message,
    });
  }
  if (permissao.data !== true) {
    return resposta(403, {
      codigo: "SEM_PERMISSAO",
      permissao: PERMISSAO,
      mensagem: "Você não tem permissão para convidar usuários.",
    });
  }

  const unidade = await chamador.rpc("fn_unidade_atual");
  if (unidade.error || !unidade.data) {
    return resposta(422, {
      codigo: "USUARIO_SEM_UNIDADE",
      mensagem: "Não deu para saber a unidade de quem está convidando.",
    });
  }

  // 2. O convite, com a service key — que não sai daqui.
  const admin = createClient(url, chaveServico, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const convite = await admin.auth.admin.inviteUserByEmail(pedido.email, {
    data: { nome: pedido.nome, unidade_id: unidade.data },
    redirectTo: pedido.redirecionarPara,
  });

  // 3. O erro do banco (espelho do card 3.5: USUARIO_SEM_UNIDADE,
  //    USUARIO_SEM_EMAIL) ou do GoTrue (email_exists, rate limit) volta como
  //    veio, com o status dele.
  if (convite.error) {
    const { status, corpo } = respostaDeErroAuth(convite.error);
    return resposta(status, corpo);
  }

  return resposta(200, {
    usuario_id: convite.data.user?.id,
    email: convite.data.user?.email,
  });
});
