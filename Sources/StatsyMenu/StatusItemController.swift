import AppKit
import StatsyControl
import StatsyKit

/// The menu bar item: a toggle for the panel, a choice of machine, and a way
/// out of both apps.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let panel = PanelProcess()
    private let selection = TargetSelection()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let toggleItem = NSMenuItem(
        title: "", action: #selector(togglePanel), keyEquivalent: ""
    )
    private let targetItem = NSMenuItem(title: "Target", action: nil, keyEquivalent: "")
    private let targetMenu = NSMenu()
    /// What the target submenu currently shows, so an unchanged selection does
    /// not rebuild it on every menu open.
    private var shownTargets: TargetMenuPresentation?
    /// What the menu bar item currently shows. An unchanged state then costs
    /// nothing, which matters because rebuilding the icon is by far the most
    /// expensive part of a refresh and the menu refreshes on every open.
    private var shownState: PanelRunState?
    /// Guards against a second click while a start or stop is in flight.
    private var isBusy = false

    func install() {
        toggleItem.target = self

        let quitItem = NSMenuItem(title: "Quit Statsy Menu", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self

        targetMenu.autoenablesItems = false
        targetItem.submenu = targetMenu

        let menu = NSMenu()
        menu.delegate = self
        // Enablement is ours: left to AppKit, any item with a valid target and
        // action is enabled, including the toggle when there is no panel to run.
        menu.autoenablesItems = false
        menu.addItem(toggleItem)
        menu.addItem(targetItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        statusItem.menu = menu

        panel.onStateChange = { [weak self] in self?.refresh() }
        panel.observeWorkspace()
        refresh()
        refreshTargets()
    }

    /// Re-reads the panel state just before the menu drops down, in case it
    /// changed without a workspace notification.
    func menuNeedsUpdate(_ menu: NSMenu) {
        refresh()
        // The selection can also be changed by another copy of this app, or by
        // hand: the file is the shared truth, not this object's memory of it.
        refreshTargets()
    }

    private func refresh() {
        let state = panel.state
        guard state != shownState else { return }
        shownState = state

        let presentation = PanelMenuPresentation(state: state)
        toggleItem.title = presentation.toggleTitle
        toggleItem.isEnabled = presentation.isToggleEnabled
        statusItem.button?.image = NSImage(
            systemSymbolName: presentation.symbolName,
            accessibilityDescription: presentation.accessibilityDescription
        )
    }

    @objc private func togglePanel() {
        guard !isBusy else { return }
        let state = panel.state
        isBusy = true

        Task {
            defer {
                isBusy = false
                refresh()
            }
            if state == .running {
                await panel.stop()
            } else {
                do {
                    try await panel.start()
                } catch {
                    report(error)
                }
            }
        }
    }

    /// Rebuilds the target submenu from the recorded selection.
    private func refreshTargets() {
        let presentation = TargetMenuPresentation(selected: selection.read())
        guard presentation != shownTargets else { return }
        shownTargets = presentation

        targetItem.title = presentation.title
        targetItem.isHidden = !presentation.isMeaningful

        targetMenu.removeAllItems()
        for target in presentation.items {
            let item = NSMenuItem(
                title: target.title, action: #selector(selectTarget(_:)), keyEquivalent: ""
            )
            item.target = self
            item.isEnabled = true
            item.state = target.isSelected ? .on : .off
            item.representedObject = target.id
            targetMenu.addItem(item)
        }
    }

    /// Records the chosen target. A running panel is watching the file and
    /// repoints itself, so there is nothing to restart here.
    @objc private func selectTarget(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let target = TargetRegistry.target(id: id)
        else { return }
        do {
            try selection.write(target)
            refreshTargets()
        } catch {
            report(error)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    /// Launch failures are silent otherwise: there is no window to show them in.
    private func report(_ error: any Error) {
        let alert = NSAlert()
        alert.messageText = "Statsy could not be started"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        NSApp.activate()
        alert.runModal()
    }
}
