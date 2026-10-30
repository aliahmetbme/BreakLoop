import Foundation

// Host-side substitutes for the Apple framework boundary only. The runner compiles the
// production OnboardingViewModel unchanged apart from its unavailable FamilyControls import.
enum AuthorizationStatus { case notDetermined, denied, approved }
@MainActor protocol ScreenTimeAuthorizationServiceProtocol {
    var authorizationStatus: AuthorizationStatus { get }
    func requestAuthorization() async throws
}
@MainActor private final class AuthorizationStub: ScreenTimeAuthorizationServiceProtocol {
    var authorizationStatus = AuthorizationStatus.notDetermined
    var requests = 0
    var continuation: CheckedContinuation<Void, Error>?
    func requestAuthorization() async throws {
        requests += 1
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func complete(_ status: AuthorizationStatus, error: Error? = nil) {
        authorizationStatus = status
        if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
        continuation = nil
    }
}
@main struct OnboardingPermissionTests {
    @MainActor static func main() async {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            checks += 1; precondition(value(), message)
        }
        let service = AuthorizationStub()
        let model = OnboardingViewModel(authorizationService: service)
        check(!model.isAuthorized && !model.isRequestingAuthorization, "initial undetermined state")
        let first = Task { await model.requestAuthorization() }
        while service.continuation == nil { await Task.yield() }
        check(model.isRequestingAuthorization && model.errorMessage == nil, "pending permission state")
        await model.requestAuthorization()
        check(service.requests == 1, "duplicate taps do not request authorization twice")
        service.complete(.denied)
        await first.value
        check(!model.isAuthorized && !model.isRequestingAuthorization, "denial does not continue onboarding")
        let failedRetry = Task { await model.requestAuthorization() }
        while service.continuation == nil { await Task.yield() }
        service.complete(.denied, error: NSError(domain: "OnboardingTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "permission failed"]))
        await failedRetry.value
        check(model.errorMessage == "permission failed" && !model.isRequestingAuthorization, "request error is visible and loading stops")
        let retry = Task { await model.requestAuthorization() }
        while service.continuation == nil { await Task.yield() }
        check(model.errorMessage == nil, "retry clears previous error")
        service.complete(.approved)
        await retry.value
        check(model.isAuthorized && !model.isRequestingAuthorization, "approved retry can continue")
        check(service.requests == 3, "expected request count")
        service.authorizationStatus = .denied
        model.refreshAuthorizationStatus()
        check(!model.isAuthorized, "refresh follows actual service status")
        print("Onboarding permission: \(checks) checks passed (mock framework boundary)")
    }
}
