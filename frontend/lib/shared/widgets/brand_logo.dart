import 'package:flutter/material.dart';

/// The supplied wordmark, displayed intact on its original white background.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.width = 240, this.height});

  final double width;
  final double? height;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/branding/karaok-wordmark.jpg',
    width: width,
    height: height,
    fit: BoxFit.contain,
    semanticLabel: 'KaraOK',
  );
}
