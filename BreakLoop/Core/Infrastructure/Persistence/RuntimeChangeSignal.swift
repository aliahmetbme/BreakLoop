import Foundation
import notify

// Idempotent cancellation also covers queued work and deallocation without raw observer pointers.
final class RuntimeCancellation {
    private let lock = NSLock()
    private var action: (() -> Void)?
    init(_ action: @escaping () -> Void) { self.action = action }
    func cancel() {
        lock.lock()
        let action = self.action
        self.action = nil
        lock.unlock()
        action?()
    }
    deinit { cancel() }
}

enum RuntimeChangeSignal {
    static let name = "com.aliahmeterdogdu.BreakLoop.runtimeChanged.v1"

    // No selection, runtime payload, or old deadline travels in the notification.
    static func post() -> UInt32 { notify_post(name) }

    static func observe(_ changed: @escaping @Sendable () -> Void) throws -> RuntimeCancellation {
        var token: Int32 = 0
        let status = notify_register_dispatch(name, &token, .main) { _ in changed() }
        guard status == NOTIFY_STATUS_OK else { throw LifecycleError.storageUnavailable }
        return RuntimeCancellation { notify_cancel(token) }
    }
}
