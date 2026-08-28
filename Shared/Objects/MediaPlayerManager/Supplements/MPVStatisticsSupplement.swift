//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if os(iOS)
import Metal
import SwiftUI

// swiftlint:disable hard_coded_display_string

enum MPVStatisticsStrings {
    static let title = String(enhancedLocalized: "mpv.stats.title", defaultValue: "MPV statistics")
    static let decoding = String(enhancedLocalized: "mpv.stats.decoding", defaultValue: "Decoding")
    static let presentation = String(enhancedLocalized: "mpv.stats.presentation", defaultValue: "Presentation")
    static let color = String(enhancedLocalized: "mpv.stats.color", defaultValue: "Color")
    static let tracks = String(enhancedLocalized: "mpv.stats.tracks", defaultValue: "Tracks")
    static let log = String(enhancedLocalized: "mpv.stats.log", defaultValue: "Log")
    static let copyLog = String(enhancedLocalized: "mpv.stats.copy-log", defaultValue: "Copy log")
    static let clearLog = String(enhancedLocalized: "mpv.stats.clear-log", defaultValue: "Clear log")
    static let unavailable = String(enhancedLocalized: "mpv.stats.unavailable", defaultValue: "MPV is not the active player.")
    static let hardwareDecoder = String(enhancedLocalized: "mpv.stats.hwdec", defaultValue: "Hardware decoder")
    static let videoCodec = String(enhancedLocalized: "mpv.stats.video-codec", defaultValue: "Video codec")
    static let pixelFormat = String(enhancedLocalized: "mpv.stats.pixel-format", defaultValue: "Pixel format")
    static let audioCodec = String(enhancedLocalized: "mpv.stats.audio-codec", defaultValue: "Audio codec")
    static let resolution = String(enhancedLocalized: "mpv.stats.resolution", defaultValue: "Resolution")
    static let containerFPS = String(enhancedLocalized: "mpv.stats.container-fps", defaultValue: "Container FPS")
    static let estimatedFPS = String(enhancedLocalized: "mpv.stats.estimated-fps", defaultValue: "Estimated FPS")
    static let displayFPS = String(enhancedLocalized: "mpv.stats.display-fps", defaultValue: "Display FPS")
    static let decoderDrops = String(enhancedLocalized: "mpv.stats.decoder-drops", defaultValue: "Decoder drops")
    static let outputDrops = String(enhancedLocalized: "mpv.stats.output-drops", defaultValue: "Output drops")
    static let cache = String(enhancedLocalized: "mpv.stats.cache", defaultValue: "Demuxer cache")
    static let primaries = String(enhancedLocalized: "mpv.stats.primaries", defaultValue: "Primaries")
    static let transfer = String(enhancedLocalized: "mpv.stats.transfer", defaultValue: "Transfer")
    static let signalPeak = String(enhancedLocalized: "mpv.stats.sig-peak", defaultValue: "Signal peak")
    static let dynamicRange = String(enhancedLocalized: "mpv.stats.dynamic-range", defaultValue: "Dynamic range")
    static let upscaler = String(enhancedLocalized: "mpv.stats.upscaler", defaultValue: "Upscaler")
    static let gpu = String(enhancedLocalized: "mpv.stats.gpu", defaultValue: "GPU")
    static let none = String(enhancedLocalized: "mpv.stats.none", defaultValue: "None")
}

/// A native replacement for MPV's `stats.lua` overlay.
///
/// MPVKit builds libmpv with `lua=disabled`, so the built-in stats script does
/// not exist. Everything here comes from properties `MPVClientCore` observes.
class MPVStatisticsSupplement: ObservableObject, MediaPlayerSupplement {

    let displayTitle: String = MPVStatisticsStrings.title

    var id: String {
        "MPVStatistics"
    }

    var videoPlayerBody: some PlatformView {
        OverlayView()
    }
}

extension MPVStatisticsSupplement {

    private struct OverlayView: PlatformView {

        @Environment(\.safeAreaInsets)
        private var safeAreaInsets: EdgeInsets

        @EnvironmentObject
        private var manager: MediaPlayerManager

        private var proxy: MPVMediaPlayerProxy? {
            manager.proxy as? MPVMediaPlayerProxy
        }

        var iOSView: some View {
            Group {
                if let proxy {
                    ContentView(proxy: proxy, diagnostics: proxy.diagnostics, upscaler: proxy.upscaler)
                } else {
                    Text(MPVStatisticsStrings.unavailable)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .labeledContentStyle(.playbackInfo)
            .padding(.leading, safeAreaInsets.leading)
            .padding(.trailing, safeAreaInsets.trailing)
        }

        var tvOSView: some View {
            EmptyView()
        }
    }

    private struct ContentView: View {

        @ObservedObject
        var proxy: MPVMediaPlayerProxy
        @ObservedObject
        var diagnostics: MPVPlaybackDiagnostics
        @ObservedObject
        var upscaler: MPVUpscalerController

        private func string(_ name: String) -> String? {
            guard case let .string(value) = diagnostics.properties[name], value.isNotEmpty else { return nil }
            return value
        }

        private func integer(_ name: String) -> Int? {
            guard case let .integer(value) = diagnostics.properties[name] else { return nil }
            return Int(value)
        }

        private func double(_ name: String) -> Double? {
            guard case let .double(value) = diagnostics.properties[name], value.isFinite else { return nil }
            return value
        }

        private func header(_ title: String) -> some View {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.vertical, 4)
        }

        @ViewBuilder
        private var decodingSection: some View {
            header(MPVStatisticsStrings.decoding)

            LabeledContent(
                MPVStatisticsStrings.hardwareDecoder,
                value: string("hwdec-current").map { $0 == "no" ? MPVStatisticsStrings.none : $0 }
                    ?? MPVStatisticsStrings.none
            )

            if let codec = string("video-codec") {
                LabeledContent(MPVStatisticsStrings.videoCodec, value: codec)
            }

            if let format = string("video-format") {
                LabeledContent(MPVStatisticsStrings.pixelFormat, value: format)
            }

            if let codec = string("audio-codec-name") {
                LabeledContent(MPVStatisticsStrings.audioCodec, value: codec.uppercased())
            }

            let size = proxy.videoSize.value
            if size != .zero {
                LabeledContent(
                    MPVStatisticsStrings.resolution,
                    value: "\(Int(size.width))×\(Int(size.height))"
                )
            }
        }

        @ViewBuilder
        private var presentationSection: some View {
            header(MPVStatisticsStrings.presentation)

            if let fps = double("container-fps") {
                LabeledContent(MPVStatisticsStrings.containerFPS, value: fps.formatted(.number.precision(.fractionLength(3))))
            }

            if let fps = double("estimated-vf-fps") {
                LabeledContent(MPVStatisticsStrings.estimatedFPS, value: fps.formatted(.number.precision(.fractionLength(2))))
            }

            if let fps = double("display-fps") {
                LabeledContent(MPVStatisticsStrings.displayFPS, value: fps.formatted(.number.precision(.fractionLength(0))))
            }

            if let drops = integer("decoder-frame-drop-count") {
                LabeledContent(MPVStatisticsStrings.decoderDrops, value: drops.description)
            }

            if let drops = integer("frame-drop-count") {
                LabeledContent(MPVStatisticsStrings.outputDrops, value: drops.description)
            }

            if let cache = double("demuxer-cache-duration") {
                /// Seconds of demuxed media buffered ahead; a bare number reads
                /// better here than a clock format.
                LabeledContent(
                    MPVStatisticsStrings.cache,
                    value: "\(cache.formatted(.number.precision(.fractionLength(1)))) s"
                )
            }

            LabeledContent(MPVStatisticsStrings.upscaler, value: upscaler.activeDescription)
            LabeledContent(MPVStatisticsStrings.gpu, value: PlaybackCapabilities.gpuName)
        }

        @ViewBuilder
        private var colorSection: some View {
            header(MPVStatisticsStrings.color)

            if let primaries = string("video-params/primaries") {
                LabeledContent(MPVStatisticsStrings.primaries, value: primaries)
            }

            if let gamma = string("video-params/gamma") {
                LabeledContent(MPVStatisticsStrings.transfer, value: gamma)
            }

            if let peak = double("video-params/sig-peak"), peak > 0 {
                LabeledContent(
                    MPVStatisticsStrings.signalPeak,
                    value: peak.formatted(.number.precision(.fractionLength(2)))
                )
            }

            LabeledContent(
                MPVStatisticsStrings.dynamicRange,
                value: proxy.isHighDynamicRange ? "HDR" : "SDR"
            )
        }

        @ViewBuilder
        private var tracksSection: some View {
            if diagnostics.tracks.isNotEmpty {
                header(MPVStatisticsStrings.tracks)

                ForEach(diagnostics.tracks) { track in
                    LabeledContent(
                        "\(track.kind.rawValue) \(track.id)\(track.isSelected ? " ✓" : "")",
                        value: [track.title, track.codec, track.language]
                            .compactMap(\.self)
                            .joined(separator: " · ")
                    )
                }
            }
        }

        @ViewBuilder
        private var logSection: some View {
            if diagnostics.logs.isNotEmpty {
                HStack {
                    header(MPVStatisticsStrings.log)

                    Spacer()

                    Button(MPVStatisticsStrings.copyLog) {
                        UIPasteboard.general.string = diagnostics.logs.joined(separator: "\n")
                    }
                    .font(.caption)

                    Button(MPVStatisticsStrings.clearLog) {
                        diagnostics.clearLogs()
                    }
                    .font(.caption)
                }

                /// Newest first: a running player appends faster than anyone can
                /// scroll, so the tail is what matters.
                ForEach(Array(diagnostics.logs.suffix(50).reversed().enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption2)
                        .monospaced()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    decodingSection
                    presentationSection
                    colorSection
                    tracksSection
                    logSection
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
            .edgePadding()
        }
    }
}

// swiftlint:enable hard_coded_display_string
#endif
