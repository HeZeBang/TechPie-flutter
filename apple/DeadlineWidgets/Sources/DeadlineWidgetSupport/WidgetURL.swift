import Foundation

public enum TechPieWidgetURL {
  public static func scheme(in bundle: Bundle = .main) -> String {
    guard let raw = bundle.object(forInfoDictionaryKey: "TechPieWidgetURLScheme") as? String else {
      return "techpie"
    }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "techpie" : trimmed
  }

  public static func ecardPay(in bundle: Bundle = .main) -> URL {
    URL(string: "\(scheme(in: bundle))://ecard/pay")!
  }

  public static func schedule(in bundle: Bundle = .main) -> URL {
    URL(string: "\(scheme(in: bundle))://schedule")!
  }

  public static func deadlines(in bundle: Bundle = .main) -> URL {
    URL(string: "\(scheme(in: bundle))://deadlines")!
  }
}
