@preconcurrency import StreamWebRTC
import SwiftUI

struct VisionLinkVideoView: UIViewRepresentable {
    let track: RTCVideoTrack?
    let onFirstFrame: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFirstFrame: onFirstFrame)
    }

    func makeUIView(
        context: Context
    ) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero)
        view.videoContentMode = .scaleAspectFit
        view.delegate = context.coordinator
        view.backgroundColor = .black
        context.coordinator.renderer = view
        return view
    }

    func updateUIView(
        _ view: RTCMTLVideoView,
        context: Context
    ) {
        context.coordinator.attach(track)
    }

    static func dismantleUIView(
        _ view: RTCMTLVideoView,
        coordinator: Coordinator
    ) {
        coordinator.attach(nil)
        view.delegate = nil
    }

    final class Coordinator:
        NSObject,
        RTCVideoViewDelegate
    {
        weak var renderer: RTCMTLVideoView?
        private var track: RTCVideoTrack?
        private var didRenderFirstFrame = false
        private let onFirstFrame: @MainActor () -> Void

        init(
            onFirstFrame: @escaping @MainActor () -> Void
        ) {
            self.onFirstFrame = onFirstFrame
        }

        func attach(_ newTrack: RTCVideoTrack?) {
            guard track !== newTrack else {
                return
            }
            if let renderer {
                track?.remove(renderer)
                newTrack?.add(renderer)
            }
            track = newTrack
            didRenderFirstFrame = false
        }

        func videoView(
            _ videoView: any RTCVideoRenderer,
            didChangeVideoSize size: CGSize
        ) {
            guard !didRenderFirstFrame,
                  size.width > 0,
                  size.height > 0 else {
                return
            }
            didRenderFirstFrame = true
            Task { @MainActor in
                onFirstFrame()
            }
        }
    }
}
