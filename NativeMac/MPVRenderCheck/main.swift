//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import AppKit
import ImageIO
import Metal
import QuartzCore
import UniformTypeIdentifiers

// Standalone native rendering gate. Production server navigation lives in a later target.
final class MetalVideoView: NSView {

    let videoLayer = CAMetalLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        videoLayer.device = MTLCreateSystemDefaultDevice()
        videoLayer.pixelFormat = .bgra8Unorm
        videoLayer.framebufferOnly = false
        layer = videoLayer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func layout() {
        super.layout()
        updateDrawableSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        let scale = window?.backingScaleFactor ?? 1
        videoLayer.contentsScale = scale
        videoLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }
}

final class RenderCheck: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private let queue = DispatchQueue(label: "Swiftfin.NativeRenderCheck.mpv")
    private var handle: OpaquePointer?
    private var timer: DispatchSourceTimer?
    private var window: NSWindow!
    private let video = MetalVideoView(frame: NSRect(x: 0, y: 0, width: 960, height: 540))
    private var closing = false
    private let smokeDirectory: String? = {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--smoke-output"), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        menu.addItem(applicationItem)
        let applicationMenu = NSMenu()
        applicationMenu.addItem(withTitle: "Quit Render Check", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        let fileItem = NSMenuItem()
        menu.addItem(fileItem)
        fileItem.submenu = NSMenu(title: "File")
        fileItem.submenu?.addItem(withTitle: "Open…", action: #selector(openFile), keyEquivalent: "o").target = self
        NSApp.mainMenu = menu

        window = NSWindow(
            contentRect: video.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Swiftfin — Native MPV Render Check"
        window.contentView = video
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.collectionBehavior = .fullScreenPrimary
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // The view owns this layer until mpv_terminate_destroy has finished.
        let layerAddress = Int64(Int(bitPattern: Unmanaged.passUnretained(video.videoLayer).toOpaque()))
        queue.async { [self] in
            guard let context = mpv_create() else { fatalError("mpv_create failed") }
            handle = context
            for (name, value) in [
                ("vo", "gpu-next"), ("gpu-api", "vulkan"), ("gpu-context", "moltenvk"),
                ("config", "no"), ("load-scripts", "no"), ("osc", "no"), ("idle", "yes"),
                ("terminal", "yes"), ("hwdec", "videotoolbox"),
            ] {
                check(mpv_set_option_string(context, name, value), operation: name)
            }
            var wid = layerAddress
            check(mpv_set_option(context, "wid", MPV_FORMAT_INT64, &wid), operation: "wid")
            check(mpv_initialize(context), operation: "initialize")
            let events = DispatchSource.makeTimerSource(queue: queue)
            events.schedule(deadline: .now(), repeating: .milliseconds(20))
            events.setEventHandler { [weak self] in self?.drainEvents() }
            events.resume()
            timer = events
            if smokeDirectory != nil {
                let args = CommandLine.arguments
                guard let index = args.firstIndex(of: "--smoke-media"), args.indices.contains(index + 1) else {
                    fatalError("--smoke-output requires --smoke-media with a local video path")
                }
                command(["loadfile", args[index + 1]])
            }
        }
        if let smokeDirectory {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [self] in
                queue.async { [self] in captureFrame(at: "\(smokeDirectory)/initial.png") }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [self] in
                window.setContentSize(NSSize(width: 720, height: 720))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [self] in
                queue.async { [self] in captureFrame(at: "\(smokeDirectory)/resized.png") }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { NSApp.terminate(nil) }
        }
    }

    @objc
    private func openFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let owner = self else { return }
            owner.queue.async { owner.command(["loadfile", url.path]) }
        }
    }

    private func check(_ status: Int32, operation: String) {
        guard status >= 0 else { fatalError("MPV \(operation): \(String(cString: mpv_error_string(status)))") }
    }

    private func command(_ arguments: [String]) {
        guard let handle else { return }
        let strings = arguments.map { strdup($0) }
        defer { strings.forEach { free($0) } }
        var pointers: [UnsafePointer<CChar>?] = strings.map { pointer in
            pointer.map { UnsafePointer<CChar>($0) }
        } + [nil]
        check(mpv_command(handle, &pointers), operation: arguments[0])
    }

    private func drainEvents() {
        guard let handle else { return }
        while let event = mpv_wait_event(handle, 0), event.pointee.event_id != MPV_EVENT_NONE {
            if event.pointee.event_id == MPV_EVENT_FILE_LOADED {
                print("NATIVE_RENDER_CHECK: file loaded")
            } else if event.pointee.event_id == MPV_EVENT_PLAYBACK_RESTART {
                print("NATIVE_RENDER_CHECK: playback started")
            }
        }
    }

    /// FFmpeg's playback build omits PNG encoders; encode the renderer's raw pixels with ImageIO.
    private func captureFrame(at path: String) {
        guard let handle else { return }
        let arguments: [String] = ["screenshot-raw", "window", "rgba"]
        let strings = arguments.map { strdup($0) }
        defer { strings.forEach { free($0) } }
        var pointers: [UnsafePointer<CChar>?] = strings.map { pointer in
            pointer.map { UnsafePointer<CChar>($0) }
        } + [nil]
        var result = mpv_node()
        check(mpv_command_ret(handle, &pointers, &result), operation: "screenshot-raw")
        defer { mpv_free_node_contents(&result) }
        guard result.format == MPV_FORMAT_NODE_MAP, let map = result.u.list else {
            fatalError("Screenshot did not return a map")
        }
        var fields: [String: mpv_node] = [:]
        for index in 0 ..< Int(map.pointee.num) {
            fields[String(cString: map.pointee.keys[index]!)] = map.pointee.values[index]
        }
        guard let width = fields["w"], let height = fields["h"], let stride = fields["stride"],
              width.format == MPV_FORMAT_INT64, height.format == MPV_FORMAT_INT64, stride.format == MPV_FORMAT_INT64,
              let pixels = fields["data"], pixels.format == MPV_FORMAT_BYTE_ARRAY, let bytes = pixels.u.ba,
              let start = bytes.pointee.data else { fatalError("Screenshot is missing pixel data") }
        let w = Int(width.u.int64), h = Int(height.u.int64), rowStride = Int(stride.u.int64)
        guard w > 0, h > 0, abs(rowStride) >= w * 4 else { fatalError("Invalid screenshot dimensions") }
        var data = Data(capacity: w * h * 4)
        for row in 0 ..< h {
            data.append(start.advanced(by: row * rowStride).assumingMemoryBound(to: UInt8.self), count: w * 4)
        }
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                  width: w,
                  height: h,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: w * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ),
              let destination = CGImageDestinationCreateWithURL(
                  URL(fileURLWithPath: path) as CFURL,
                  UTType.png.identifier as CFString,
                  1,
                  nil
              )
        else { fatalError("Cannot encode screenshot") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("Cannot save screenshot") }
        print("NATIVE_RENDER_CHECK: saved \(w)x\(h) frame to \(path)")
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !closing else { return .terminateLater }
        closing = true
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            if let handle {
                mpv_terminate_destroy(handle)
            }
            handle = nil
            // terminateLater can nest AppKit's run loop inside a main-queue callback.
            // A second main-queue block would wait forever for that callback to return.
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
                print("NATIVE_RENDER_CHECK: shutdown complete")
                sender.reply(toApplicationShouldTerminate: true)
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
        return .terminateLater
    }
}

let application = NSApplication.shared
let delegate = RenderCheck()
application.setActivationPolicy(.regular)
application.delegate = delegate
application.run()
