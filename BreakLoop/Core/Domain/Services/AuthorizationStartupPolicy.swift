// A transient framework sample is not proof of revocation. Kept independent of
// FamilyControls so the real routing policy is exercised by host regressions.
enum AuthorizationStartupPolicy {
    enum Sample { case approved, denied, undetermined, unknown }
    enum Route: Equatable { case authorized, checking, onboarding, permissionRequired }
    static func route(sample: Sample, configured: Bool, settled: Bool) -> Route {
        switch sample {
        case .approved: return .authorized
        case .denied: return .permissionRequired
        case .undetermined: return settled ? (configured ? .permissionRequired : .onboarding) : .checking
        case .unknown: return settled ? .permissionRequired : .checking
        }
    }
    static func provesRevocation(previouslyApproved: Bool, sample: Sample) -> Bool {
        previouslyApproved && sample == .denied
    }
}
