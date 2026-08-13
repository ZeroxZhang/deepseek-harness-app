/**
 * DeepSeek Harness — macOS app entry.
 *
 * `main.swift` is the only file allowed top-level code under swiftc; it builds
 * the NSApplication, wires the delegate, and runs the main loop.
 */

import Cocoa

// A Finder-launched app must join the regular foreground activation policy.
_ = NSApplication.shared.setActivationPolicy(.regular)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
