import SwiftUI

enum NoticeSurfaceStyle {
    case standard
    case terminal(backgroundColor: Color)
}

struct NoticeMetrics {
    static let cornerRadius: CGFloat = 16
    static let bannerMaxWidth: CGFloat = 620
    static let operationMaxWidth: CGFloat = 560
    static let blockingMaxWidth: CGFloat = 340
}

extension Color {
    /*
     CDXC:iOSStatusIndicators 2026-06-12-02:32:
     Done, attention, and completion status surfaces use #95d7f6 instead of the prior bright green so iOS matches macOS and Android.
     */
    static let ghostexDoneAttentionStatus = Color(red: 0x95 / 255, green: 0xD7 / 255, blue: 0xF6 / 255)
}

extension NoticeLevel {
    var tintColor: Color {
        switch self {
        case .info:
            return .accentColor
        case .success:
            return .ghostexDoneAttentionStatus
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    var defaultIconSystemName: String {
        switch self {
        case .info:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }
}
