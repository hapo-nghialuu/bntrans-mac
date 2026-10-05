import ScreenCaptureKit
import AppKit

/// Captures the display containing `rect` and crops to it.
/// `rect` is global Cocoa coords (y-up, from RegionSelector).
enum CaptureError: LocalizedError {
    case noDisplay
    var errorDescription: String? { "No display found for the selected region." }
}

func captureRegion(_ rect: CGRect) async throws -> CGImage {
    let content = try await SCShareableContent.excludingDesktopWindows(
        false,
        onScreenWindowsOnly: true
    )
    // SCDisplay.frame lives in Quartz coords (y-down); convert once.
    let primaryH = NSScreen.screens[0].frame.maxY
    let cgRect = CGRect(
        x: rect.minX,
        y: primaryH - rect.maxY,
        width: rect.width,
        height: rect.height
    )
    guard let display = content.displays.first(where: {
        $0.frame.intersects(cgRect)
    }) else { throw CaptureError.noDisplay }

    let filter = SCContentFilter(display: display, excludingWindows: [])
    let cfg = SCStreamConfiguration()
    cfg.showsCursor = false
    let image = try await SCScreenshotManager.captureImage(
        contentFilter: filter,
        configuration: cfg
    )

    // bitmap is physical pixels; scale against display points
    let scaleX = CGFloat(image.width) / display.frame.width
    let scaleY = CGFloat(image.height) / display.frame.height
    let local = cgRect.intersection(display.frame).offsetBy(
        dx: -display.frame.minX,
        dy: -display.frame.minY
    )
    let crop = CGRect(
        x: local.minX * scaleX,
        y: local.minY * scaleY,
        width: local.width * scaleX,
        height: local.height * scaleY
    ).integral
    return image.cropping(to: crop) ?? image
}
