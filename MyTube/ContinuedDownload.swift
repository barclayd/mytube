import BackgroundTasks
import Foundation

/// One lease covers extraction, both transfers and remuxing for one user-started download.
@MainActor protocol DownloadBackgroundWork: AnyObject {
  func begin(title: String, onExpiration: @escaping @MainActor () -> Void) async throws
  func report(completed: Int64, total: Int64, subtitle: String)
  func finish(success: Bool)
}

@MainActor final class ContinuedDownload: DownloadBackgroundWork {
  static let shared = ContinuedDownload()
  private static let prefix = "com.barclayd.MyTube.downloads"
  private var identifier: String?
  private var waiting: CheckedContinuation<Void, Error>?
  private var active: BGContinuedProcessingTask?
  private var onExpiration: (@MainActor () -> Void)?
  private let registered: Bool

  private init() {
    registered = BGTaskScheduler.shared.register(
      forTaskWithIdentifier: "\(Self.prefix).*", using: .main
    ) { task in
      MainActor.assumeIsolated { Self.shared.accept(task) }
    }
  }

  func begin(title: String, onExpiration: @escaping @MainActor () -> Void) async throws {
    guard registered else { throw BackgroundError.unavailable }
    try Task.checkCancellation()
    let identifier = "\(Self.prefix).\(UUID().uuidString)"
    self.identifier = identifier
    self.onExpiration = onExpiration
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        waiting = continuation
        Task {
          do {
            try await Self.submit(identifier: identifier, title: title)
          } catch {
            failPending(identifier: identifier, error: error)
          }
        }
      }
    } onCancel: {
      Task { @MainActor in
        self.failPending(identifier: identifier, error: CancellationError())
      }
    }
    try Task.checkCancellation()
  }

  // iOS 27's asynchronous submission reports failures the old submit API could miss.
  private nonisolated static func submit(identifier: String, title: String) async throws {
    let request = BGContinuedProcessingTaskRequest(
      identifier: identifier, title: title, subtitle: "Preparing video…")
    request.strategy = .fail
    try await BGTaskScheduler.shared.submitTaskRequest(request)
  }

  private func accept(_ task: BGTask) {
    guard let task = task as? BGContinuedProcessingTask,
      task.identifier == identifier, let continuation = waiting
    else {
      task.setTaskCompleted(success: false)
      return
    }
    active = task
    waiting = nil
    task.progress.totalUnitCount = 1000
    task.expirationHandler = {
      Task { @MainActor in
        guard self.active?.identifier == task.identifier else { return }
        self.onExpiration?()
        self.finish(success: false)
      }
    }
    continuation.resume()
  }

  private func failPending(identifier: String, error: Error) {
    guard self.identifier == identifier, let continuation = waiting else { return }
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    waiting = nil
    self.identifier = nil
    onExpiration = nil
    continuation.resume(throwing: error)
  }

  func report(completed: Int64, total: Int64, subtitle: String) {
    guard let active else { return }
    active.progress.totalUnitCount = total
    active.progress.completedUnitCount = max(
      active.progress.completedUnitCount, min(completed, total))
    if active.subtitle != subtitle { active.updateTitle(active.title, subtitle: subtitle) }
  }

  func finish(success: Bool) {
    if let active {
      active.expirationHandler = nil
      if success { active.progress.completedUnitCount = active.progress.totalUnitCount }
      active.setTaskCompleted(success: success)
    }
    active = nil
    if let identifier { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier) }
    identifier = nil
    onExpiration = nil
  }

  enum BackgroundError: Error { case unavailable }
}
