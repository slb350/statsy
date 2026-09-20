import Foundation
import StatsyKit

/// The target submenu, derived from what is available and what is chosen.
///
/// Separated from AppKit for the same reason `PanelMenuPresentation` is: the
/// decisions about what the menu says are testable, and the menu item objects
/// are not.
public struct TargetMenuPresentation: Sendable, Equatable {
    public struct Item: Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let isSelected: Bool
    }

    /// The submenu's own title, naming the current target so it reads without
    /// opening: "Target: homelab-ai-1".
    public let title: String
    public let items: [Item]

    public init(targets: [Target] = TargetRegistry.all, selected: Target) {
        title = "Target: \(selected.name)"
        items = targets.map {
            Item(id: $0.id, title: $0.name, isSelected: $0.id == selected.id)
        }
    }

    /// Whether the submenu is worth showing at all.
    ///
    /// One target is not a choice, and a menu item that cannot change anything
    /// is worse than no menu item.
    public var isMeaningful: Bool { items.count > 1 }
}
