import AppKit
import Testing
@testable import StatsyControl

@Suite("Panel menu presentation")
struct PanelPresentationTests {
    @Test("offers to stop a running panel")
    func running() {
        let presentation = PanelMenuPresentation(state: .running)
        #expect(presentation.toggleTitle == "Stop Statsy")
        #expect(presentation.isToggleEnabled)
    }

    @Test("offers to start a stopped panel")
    func stopped() {
        let presentation = PanelMenuPresentation(state: .stopped)
        #expect(presentation.toggleTitle == "Start Statsy")
        #expect(presentation.isToggleEnabled)
    }

    @Test("says so, and offers nothing, when the panel is not installed")
    func missing() {
        let presentation = PanelMenuPresentation(state: .missing)
        #expect(presentation.toggleTitle == "Statsy Not Found")
        #expect(!presentation.isToggleEnabled)
    }

    @Test("distinguishes a running panel by its icon")
    func iconTracksState() {
        #expect(
            PanelMenuPresentation(state: .running).symbolName
                != PanelMenuPresentation(state: .stopped).symbolName
        )
    }

    @Test("every menu bar symbol resolves on this system")
    func symbolsResolve() {
        // A typo in a symbol name yields a blank menu bar item rather than any
        // kind of failure, so each one is checked against the running OS.
        for state in PanelRunState.allCases {
            let name = PanelMenuPresentation(state: state).symbolName
            #expect(
                NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil,
                "\(name) is not an SF Symbol on this system"
            )
        }
    }

    @Test("describes each state for VoiceOver")
    func accessibilityDescriptions() {
        let descriptions = PanelRunState.allCases.map {
            PanelMenuPresentation(state: $0).accessibilityDescription
        }
        #expect(descriptions.allSatisfy { !$0.isEmpty })
        #expect(Set(descriptions).count == PanelRunState.allCases.count)
    }
}
