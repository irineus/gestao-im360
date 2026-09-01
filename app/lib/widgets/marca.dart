import 'package:flutter/material.dart';

import '../theme/cores.dart';
import '../theme/dimensoes.dart';

/// A marca desenhada em Flutter, e não carregada de `assets/marca/*.svg`.
///
/// Motivo: os três SVGs do card 1.9 desenham "IM" e "GESTÃO IM360" com
/// elementos `<text>`, e o `flutter_svg` **não renderiza texto** — o símbolo
/// apareceria como um anel laranja vazio, e o erro seria silencioso. Já havia
/// pendência de converter o wordmark em contornos (`text-to-path`) para uso
/// externo (Decisões vigentes, card 1.9); este card mostra que ela alcança
/// também o **uso interno**, e o ícone do app dos cards 3.8/10.1 vai esbarrar
/// nela. Enquanto isso, desenhar é mais fiel do que renderizar errado: a
/// geometria abaixo é a mesma do SVG (viewBox 128, raio 44, traço 9, arco
/// aberto 214/62) e o texto usa a Inter que este card empacotou.
class SimboloIm360 extends StatelessWidget {
  const SimboloIm360({super.key, this.lado = 64});

  final double lado;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Gestão IM360',
      image: true,
      child: SizedBox(
        width: lado,
        height: lado,
        child: CustomPaint(painter: _PintorSimbolo(lado)),
      ),
    );
  }
}

class _PintorSimbolo extends CustomPainter {
  const _PintorSimbolo(this.lado);

  final double lado;

  @override
  void paint(Canvas canvas, Size size) {
    final k = lado / 128; // as medidas abaixo são as do SVG (viewBox 128)

    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(28 * k)),
      Paint()..color = Cores.grafite900,
    );

    // Anel aberto: o giro incompleto é o ciclo do aluno em curso (card 1.9).
    // dasharray 214/62 sobre um perímetro de 2π·44 ≈ 276.
    const perimetro = 2 * 3.14159265 * 44;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(64 * k, 64 * k), radius: 44 * k),
      -3.14159265 / 2,
      2 * 3.14159265 * (214 / perimetro),
      false,
      Paint()
        ..color = Cores.marca
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9 * k
        ..strokeCap = StrokeCap.round,
    );

    final texto = TextPainter(
      text: TextSpan(
        text: 'IM',
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 42 * k,
          fontWeight: FontWeight.w700,
          letterSpacing: -1 * k,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    texto.paint(
      canvas,
      Offset(64 * k - texto.width / 2, 64 * k - texto.height / 2),
    );
  }

  @override
  bool shouldRepaint(_PintorSimbolo anterior) => anterior.lado != lado;
}

/// Assinatura horizontal: símbolo + wordmark. A cor de marca `#E2620F` vive
/// **só** aqui — reprova AA como texto de corpo e como fundo de botão
/// (card 1.9 §3.1), e no tema fica restrita ao logotipo.
class AssinaturaIm360 extends StatelessWidget {
  const AssinaturaIm360({super.key, this.lado = 40, this.comNome = true});

  final double lado;
  final bool comNome;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SimboloIm360(lado: lado),
        if (comNome) ...[
          SizedBox(width: Dim.e12),
          // Flexível de propósito: a assinatura vive no menu de 240 px e no
          // login, e o texto precisa sobreviver ao fator de escala de 1,3× que
          // o contrato de acessibilidade exige (design-system §8.6).
          Flexible(
            child: Text(
              'GESTÃO IM360',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: lado * 0.42,
                height: 1.2,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: Cores.marca,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
