import UIKit

enum NativeGlassColors {
  static var selectedBlue: UIColor {
    UIColor { trait in
      if trait.userInterfaceStyle == .dark {
        return UIColor(
          red: 0x0A / 255.0,
          green: 0x84 / 255.0,
          blue: 0xFF / 255.0,
          alpha: 1.0
        )
      }

      return UIColor(
        red: 0x00 / 255.0,
        green: 0x7A / 255.0,
        blue: 0xFF / 255.0,
        alpha: 1.0
      )
    }
  }

  static var normalItem: UIColor {
    UIColor { trait in
      trait.userInterfaceStyle == .dark
        ? UIColor.white.withAlphaComponent(0.58)
        : UIColor.black.withAlphaComponent(0.46)
    }
  }

  static var barBackground: UIColor {
    UIColor { trait in
      trait.userInterfaceStyle == .dark
        ? UIColor.systemBackground.withAlphaComponent(0.84)
        : UIColor.systemBackground.withAlphaComponent(0.88)
    }
  }

  static var floatingButtonForeground: UIColor {
    UIColor { trait in
      trait.userInterfaceStyle == .dark
        ? UIColor.white.withAlphaComponent(0.96)
        : UIColor.black.withAlphaComponent(0.82)
    }
  }

  static var controlBorder: UIColor {
    UIColor { trait in
      trait.userInterfaceStyle == .dark
        ? UIColor.white.withAlphaComponent(0.12)
        : UIColor.black.withAlphaComponent(0.08)
    }
  }

  static var controlSeparator: UIColor {
    UIColor { trait in
      trait.userInterfaceStyle == .dark
        ? UIColor.white.withAlphaComponent(0.14)
        : UIColor.black.withAlphaComponent(0.10)
    }
  }

  static var destructiveRed: UIColor {
    UIColor { trait in
      trait.userInterfaceStyle == .dark
        ? UIColor.systemRed.withAlphaComponent(0.92)
        : UIColor.systemRed
    }
  }
}
