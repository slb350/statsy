import StatsyKit
import Testing
@testable import StatsyControl

@Suite("Target menu presentation")
struct TargetPresentationTests {
    @Test("names the current target in the submenu title")
    func title() {
        let presentation = TargetMenuPresentation(selected: TargetRegistry.homelabAI1)
        #expect(presentation.title == "Target: homelab-ai-1")
    }

    @Test("ticks exactly one target")
    func selection() {
        let presentation = TargetMenuPresentation(selected: TargetRegistry.local)
        #expect(presentation.items.filter(\.isSelected).map(\.id) == ["local"])
    }

    @Test("offers every registered target")
    func coverage() {
        let presentation = TargetMenuPresentation(selected: TargetRegistry.local)
        #expect(presentation.items.map(\.id) == TargetRegistry.all.map(\.id))
    }

    @Test("hides the submenu when there is nothing to choose between")
    func singleTarget() {
        let only = TargetMenuPresentation(
            targets: [TargetRegistry.local], selected: TargetRegistry.local
        )
        #expect(!only.isMeaningful)
        #expect(TargetMenuPresentation(selected: TargetRegistry.local).isMeaningful)
    }

    /// The menu rebuilds only when this value changes, so two presentations of
    /// the same state have to compare equal or every menu open rebuilds it.
    @Test("compares equal for an unchanged selection")
    func stability() {
        #expect(
            TargetMenuPresentation(selected: TargetRegistry.local)
                == TargetMenuPresentation(selected: TargetRegistry.local)
        )
        #expect(
            TargetMenuPresentation(selected: TargetRegistry.local)
                != TargetMenuPresentation(selected: TargetRegistry.homelabAI1)
        )
    }
}
