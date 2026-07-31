import Combine
import Foundation
import WatchConnectivity
import WidgetKit

final class WatchShiftViewModel: NSObject, ObservableObject {
    @Published private(set) var snapshot: WatchShiftSnapshot?
    @Published private(set) var isReloading = false
    @Published private(set) var lastReloadFailed = false

    private let decoder = JSONDecoder()
    private let session: WCSession?
    private var didRequestAfterActivation = false

    override init() {
        snapshot = WatchShiftSnapshotCache.load()
        session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
        session?.delegate = self
        session?.activate()
        if let context = session?.receivedApplicationContext {
            apply(context: context)
        }
    }

    func requestSnapshot() {
        guard let session else { return }

        DispatchQueue.main.async {
            self.isReloading = true
            self.lastReloadFailed = false
        }

        let message: [String: Any] = [
            WatchSnapshotBridgeKeys.requestSnapshot: true,
            WatchSnapshotBridgeKeys.reloadIOSWidgets: true
        ]

        guard session.activationState == .activated else {
            session.activate()
            finishReloadAfterDelay(failed: false)
            return
        }

        if session.isReachable {
            session.sendMessage(message) { [weak self] reply in
                guard let self else { return }
                let didApplyFreshSnapshot = self.apply(context: reply, allowsStaleSnapshot: false)
                self.finishReloadAfterDelay(failed: false, delay: didApplyFreshSnapshot ? 0.55 : 2.0)
            } errorHandler: { [weak self] _ in
                self?.apply(context: session.receivedApplicationContext)
                self?.queueBackgroundSnapshotRequest(message, on: session)
                self?.finishReloadAfterDelay(failed: true)
            }
        } else {
            apply(context: session.receivedApplicationContext)
            queueBackgroundSnapshotRequest(message, on: session)
            finishReloadAfterDelay(failed: false)
        }
    }

    @discardableResult
    private func apply(context: [String: Any], allowsStaleSnapshot: Bool = true) -> Bool {
        guard let data = context[WatchSnapshotBridgeKeys.payloadData] as? Data else {
            return false
        }

        guard let decoded = try? decoder.decode(WatchShiftSnapshot.self, from: data) else {
            return false
        }

        if !allowsStaleSnapshot,
           let currentGeneratedAt = snapshot?.generatedAt,
           decoded.generatedAt <= currentGeneratedAt {
            return false
        }

        WatchShiftSnapshotCache.save(decoded)
        DispatchQueue.main.async {
            self.snapshot = decoded
            self.isReloading = false
            self.lastReloadFailed = false
            WidgetCenter.shared.reloadAllTimelines()
        }
        return true
    }

    private func queueBackgroundSnapshotRequest(_ message: [String: Any], on session: WCSession) {
        guard session.activationState == .activated else { return }
        session.transferUserInfo(message)
    }

    private func finishReloadAfterDelay(failed: Bool, delay: TimeInterval = 0.55) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.isReloading = false
            self.lastReloadFailed = failed
        }
    }
}

extension WatchShiftViewModel: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        apply(context: session.receivedApplicationContext)
        guard activationState == .activated, error == nil, !didRequestAfterActivation else { return }
        didRequestAfterActivation = true
        requestSnapshot()
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(context: applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        apply(context: message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        apply(context: userInfo)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        requestSnapshot()
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
