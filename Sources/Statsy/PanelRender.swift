import AppKit
import StatsyKit
import SwiftUI

/// Writes one frame of the panel to a PNG.
///
/// The panel's whole design premise is a 1280x480 display at backing scale 1.0
/// that is usually not attached to the machine doing the work. Rendering a
/// frame to a file is the only way to check a layout change without plugging
/// that display in, and it is the only way to see the remote layout at all
/// without a host to point at.
@MainActor
enum PanelRender {
    static func write(snapshot: Snapshot, to path: String) throws {
        let renderer = ImageRenderer(content: PanelView(snapshot: snapshot))
        // 1.0, not the current display's scale: the panel is drawn for a
        // 195 PPI screen at one point per pixel, and rendering it at 2x would
        // hide exactly the crowding this is meant to catch.
        renderer.scale = 1

        guard let image = renderer.nsImage,
              let data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw RenderError.failed
        }
        try png.write(to: URL(fileURLWithPath: path))
    }

    enum RenderError: Error, LocalizedError {
        case failed
        var errorDescription: String? { "Could not render the panel" }
    }
}
