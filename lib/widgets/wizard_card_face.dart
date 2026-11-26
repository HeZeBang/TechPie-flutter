import 'package:flutter/material.dart';

class WizardCardFace extends StatelessWidget {
  const WizardCardFace({super.key});
  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            width: 329,
            height: 188,
            child: ColoredBox(
              color: const Color(0xffaa1322),
              child: Stack(
                children: [
                  Positioned(
                    left: 168,
                    top: -184,
                    width: 410,
                    height: 390,
                    child: Image.asset('assets/campus_card/images/wizard-arc.png'),
                  ),
                  Positioned(
                    left: 29,
                    top: 90,
                    width: 269,
                    height: 96,
                    child: Image.asset('assets/campus_card/images/wizard-skyline.png'),
                  ),
                  for (final (label, left, top, size) in [
                    ('ShanghaiTech', 20.0, 17.0, 17.0),
                    ('eCard', 20.0, 49.0, 32.0),
                    ('上海科技大学', 228.0, 19.0, 13.0),
                  ])
                    Positioned(
                      left: left,
                      top: top,
                      child: Text(
                        label,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: size,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}
