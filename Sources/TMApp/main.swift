import AppKit

/// Application entry point.
///
/// Bootstraps `NSApplication` with our `AppDelegate`. This is functionally
/// equivalent to the traditional `NSApplicationMain` call.
///
/// `setActivationPolicy(.regular)` is required for SPM-built executables
/// so that the app appears in the Dock, owns a menu bar, and receives
/// focus like a normal macOS GUI application.
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.activate()
app.run()
