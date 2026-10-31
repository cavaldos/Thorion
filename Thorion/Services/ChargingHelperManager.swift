import Foundation
import ServiceManagement
import os.log

enum ChargingHelperStatus {
    case notInstalled
    case requiresApproval
    case installed
}

enum ChargingHelperError: LocalizedError {
    case timedOut

    var errorDescription: String? {
        switch self {
        case .timedOut:
            "The charging helper did not respond"
        }
    }
}

/// Resumes a continuation exactly once, whichever comes first: the helper's reply, an
/// XPC error or the timeout.
private nonisolated final class ChargingHelperReply: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    /// Returns false when the continuation was already resumed.
    @discardableResult
    func resume(with result: Result<Void, Error>) -> Bool {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        guard let continuation else { return false }
        continuation.resume(with: result)
        return true
    }
}

@MainActor
@Observable
class ChargingHelperManager {
    static let shared = ChargingHelperManager()

    private static let machServiceName = "com.thorion.app.charging-helper"
    private static let plistName = "com.thorion.app.charging-helper.plist"

    private let service: SMAppService
    private var connection: NSXPCConnection?
    private let logger = Logger(
        subsystem: "com.thorion.app",
        category: "ChargingHelperManager"
    )

    private(set) var helperStatus: ChargingHelperStatus

    /// False once a command went unanswered. launchd keeps a daemon registered even when
    /// it can no longer start it, which happens after the app is rebuilt or updated:
    /// the registration still points at the old binary. Commands then wait forever
    /// unless they time out, so the LED and Discharge silently did nothing.
    private(set) var isResponding = true
    private var hasAttemptedAutomaticRepair = false

    private static let commandTimeout: Duration = .seconds(5)

    var isInstalled: Bool {
        service.status == .enabled
    }

    private init() {
        service = SMAppService.daemon(plistName: Self.plistName)
        switch service.status {
        case .enabled: helperStatus = .installed
        case .requiresApproval: helperStatus = .requiresApproval
        default: helperStatus = .notInstalled
        }
    }

    func install() throws {
        logger.info("Registering charging helper daemon")

        do {
            try service.register()
        } catch {
            // register() commonly throws "Operation not permitted" while macOS
            // processes the background item notification, even though the
            // registration advanced to requiresApproval or enabled.
            if service.status != .enabled && service.status != .requiresApproval {
                throw error
            }
        }

        refreshStatus()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func uninstall() throws {
        logger.info("Unregistering charging helper daemon")
        disconnect()
        try service.unregister()
        helperStatus = .notInstalled
    }

    func refreshStatus() {
        switch service.status {
        case .enabled: helperStatus = .installed
        case .requiresApproval: helperStatus = .requiresApproval
        default: helperStatus = .notInstalled
        }
    }

    /// Sends one command to the helper and waits for its reply, failing instead of
    /// hanging when the helper cannot be started.
    func send(
        _ command: @escaping (ChargingHelperProtocol, @escaping @Sendable (Bool, String?) -> Void) -> Void
    ) async throws {
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let reply = ChargingHelperReply(continuation)

                guard let helper = getHelper(errorHandler: { error in
                    reply.resume(with: .failure(error))
                }) else {
                    reply.resume(with: .failure(XPCError.helperUnavailable))
                    return
                }

                command(helper) { success, errorMessage in
                    reply.resume(
                        with: success
                            ? .success(())
                            : .failure(XPCError.commandFailed(errorMessage ?? "Unknown error"))
                    )
                }

                Task {
                    try? await Task.sleep(for: Self.commandTimeout)
                    reply.resume(with: .failure(ChargingHelperError.timedOut))
                }
            }
            setResponding(true)
        } catch let error as XPCError {
            // The helper answered, it just could not carry out the command.
            if case .commandFailed = error {
                setResponding(true)
            }
            throw error
        } catch {
            logger.error("Charging helper unreachable: \(error.localizedDescription)")
            setResponding(false)
            repairAutomaticallyIfNeeded()
            throw error
        }
    }

    private func setResponding(_ responding: Bool) {
        guard isResponding != responding else { return }
        isResponding = responding
    }

    private func repairAutomaticallyIfNeeded() {
        guard !hasAttemptedAutomaticRepair, service.status == .enabled else { return }
        hasAttemptedAutomaticRepair = true
        logger.warning("Charging helper is registered but does not respond, registering it again")
        Task { await repair() }
    }

    /// Registers the helper again so launchd starts the copy inside this app. macOS may
    /// ask for approval in System Settings → Login Items afterwards.
    func repair() async {
        disconnect()
        do {
            try await service.unregister()
        } catch {
            logger.error("Failed to unregister charging helper: \(error.localizedDescription)")
        }
        do {
            try install()
        } catch {
            logger.error("Failed to register charging helper: \(error.localizedDescription)")
        }
        // Assume it works until the next command says otherwise, so the commands that
        // follow are sent instead of being skipped.
        setResponding(true)
        if helperStatus == .requiresApproval {
            openLoginItemsSettings()
        }
    }

    func getHelper(errorHandler: @escaping @Sendable (Error) -> Void) -> ChargingHelperProtocol? {
        if connection == nil {
            connect()
        }
        guard let connection else { return nil }
        return connection.remoteObjectProxyWithErrorHandler(errorHandler)
            as? ChargingHelperProtocol
    }

    private func connect() {
        logger.info("Setting up XPC connection to charging helper daemon")
        let newConnection = NSXPCConnection(
            machServiceName: Self.machServiceName
        )
        newConnection.remoteObjectInterface = NSXPCInterface(
            with: ChargingHelperProtocol.self
        )

        newConnection.invalidationHandler = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.logger.warning("Charging helper XPC connection invalidated")
                self.connection = nil
            }
        }

        newConnection.interruptionHandler = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.logger.warning("Charging helper XPC connection interrupted")
                self.connection = nil
            }
        }

        newConnection.resume()
        connection = newConnection
    }

    func disconnect() {
        connection?.invalidate()
        connection = nil
    }
}
