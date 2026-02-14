import AppKit

/// Application entry point.
///
/// Bootstraps `NSApplication` with our `AppDelegate`. This is functionally
/// equivalent to the traditional `NSApplicationMain` call.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
