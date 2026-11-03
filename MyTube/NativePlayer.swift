import AVKit
import Observation
import SwiftUI

@MainActor @Observable
final class PlaybackSession {
  let player = AVPlayer()
  var isPictureInPictureActive = false
  @ObservationIgnored var pictureInPictureController: AVPlayerViewController?
  @ObservationIgnored var pictureInPictureDelegate: AnyObject?
  private(set) var filename: String?

  func open(_ video: SavedVideo, url: URL) {
    guard filename != video.filename else { return }
    player.pause()
    player.replaceCurrentItem(with: AVPlayerItem(url: url))
    filename = video.filename
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      // The standard player still reports playback errors if the audio session is unavailable.
    }
  }
}

/// AVKit supplies the system full-screen, AirPlay, transport and PiP controls.
struct NativePlayer: UIViewControllerRepresentable {
  let session: PlaybackSession
  var onRestore: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(session: session, onRestore: onRestore) }

  func makeUIViewController(context: Context) -> AVPlayerViewController {
    let controller = AVPlayerViewController()
    controller.player = session.player
    controller.showsPlaybackControls = true
    controller.allowsPictureInPicturePlayback = true
    controller.canStartPictureInPictureAutomaticallyFromInline = true
    controller.delegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
    if controller.player !== session.player { controller.player = session.player }
    context.coordinator.onRestore = onRestore
  }

  @MainActor final class Coordinator: NSObject, @preconcurrency AVPlayerViewControllerDelegate {
    let session: PlaybackSession
    var onRestore: () -> Void
    init(session: PlaybackSession, onRestore: @escaping () -> Void) {
      self.session = session
      self.onRestore = onRestore
    }
    func playerViewControllerWillStartPictureInPicture(
      _ playerViewController: AVPlayerViewController
    ) {
      session.isPictureInPictureActive = true
      session.pictureInPictureController = playerViewController
      session.pictureInPictureDelegate = self
    }
    func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController)
    {
      session.isPictureInPictureActive = false
      session.pictureInPictureController = nil
      session.pictureInPictureDelegate = nil
    }
    func playerViewController(
      _ playerViewController: AVPlayerViewController,
      failedToStartPictureInPictureWithError error: Error
    ) {
      session.isPictureInPictureActive = false
      session.pictureInPictureController = nil
      session.pictureInPictureDelegate = nil
    }
    func playerViewController(
      _ playerViewController: AVPlayerViewController,
      restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler:
        @escaping (Bool) -> Void
    ) {
      onRestore()
      completionHandler(true)
    }
  }
}
