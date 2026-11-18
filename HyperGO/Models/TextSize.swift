import SwiftUI

/// 界面字体大小（设置里选择，作用于整个 App）
enum TextSize: String, CaseIterable, Identifiable {
    case system, small, standard, large, xLarge, xxLarge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .small: "小"
        case .standard: "标准"
        case .large: "大"
        case .xLarge: "特大"
        case .xxLarge: "超大"
        }
    }

    /// nil 表示不覆盖，使用 iPhone 系统设置里的字体大小
    var dynamicTypeSize: DynamicTypeSize? {
        switch self {
        case .system: nil
        case .small: .small
        case .standard: .large
        case .large: .xLarge
        case .xLarge: .xxLarge
        case .xxLarge: .xxxLarge
        }
    }
}

extension View {
    /// 按用户选择的字体大小显示；「跟随系统」时不做任何改动
    @ViewBuilder
    func appTextSize(_ size: TextSize) -> some View {
        if let type = size.dynamicTypeSize {
            dynamicTypeSize(type)
        } else {
            self
        }
    }
}
