import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

class MindNestLogo extends StatelessWidget {
  const MindNestLogo({
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.topLeft,
  });

  final double? width;
  final double? height;
  final BoxFit fit;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: SizedBox(
        width: width,
        height: height,
        child: SvgPicture.asset(
          'assets/MindNest-Logo.svg',
          fit: fit,
          alignment: alignment,
        ),
      ),
    );
  }
}
