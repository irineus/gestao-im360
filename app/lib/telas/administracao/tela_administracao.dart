import 'package:flutter/material.dart';

import 'aba_historico.dart';
import 'aba_matriz.dart';
import 'aba_parametros.dart';
import 'aba_usuarios.dart';

/// Tela 12 — Administração (docs/wireframes.md §15), card 4.7: usuários
/// (convite, perfis, desativação), perfis e a matriz perfil × permissão,
/// parâmetros da unidade e — quarta aba, reservada pelo wireframe para o card
/// 4.7.5 e entregue junto — o histórico da matriz.
///
/// Cursos, combos, módulos e professores, que o plano §7 citava para esta
/// tela, moram nas telas de Materiais (4.4) e de Salas (4.5), junto do uso
/// (card 2.6, apontamento 1). Aqui ficam só acesso e configuração.
///
/// A rota é guardada por `admin.ler`; cada ação pela sua permissão
/// (`admin.gerir_usuarios`, `admin.gerir_perfis`, `parametros.gerir`) — botão
/// sem permissão não é renderizado (card 2.6 decisão 1). Quem decide é o
/// banco: a tela submete e traduz o erro pelo código.
class TelaAdministracao extends StatelessWidget {
  const TelaAdministracao({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    child: Column(
      children: [
        const TabBar(
          tabs: [
            Tab(text: 'Usuários'),
            Tab(text: 'Perfis e matriz'),
            Tab(text: 'Parâmetros'),
            Tab(text: 'Histórico'),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              const AbaUsuarios(),
              const AbaMatriz(),
              const AbaParametros(),
              const AbaHistorico(),
            ],
          ),
        ),
      ],
    ),
  );
}
