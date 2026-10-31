import AppKit
import Darwin
import Observation

struct EnergyApp: Identifiable {
    let id: pid_t
    let name: String
    let icon: NSImage?
    /// Same scale as Activity Monitor's Energy Impact: roughly CPU % over the sample window.
    let impact: Double
}

/// Tracks which apps used the most energy, the way the system Battery menu does.
/// Samples only while the menu is open; the first reading after opening covers the
/// whole time since the menu was last closed.
@MainActor
@Observable
final class EnergyAppsMonitor {
    static let significantImpact = 1.0
    static let highImpact = 10.0
    private static let maximumApps = 5
    private static let refreshInterval: Duration = .seconds(3)

    private(set) var apps: [EnergyApp] = []

    @ObservationIgnored private var previous: [pid_t: ProcessSample] = [:]
    @ObservationIgnored private var previousTime: UInt64 = 0
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init() {
        (previous, previousTime) = Self.takeSamples()
    }

    func start() {
        guard refreshTask == nil else { return }
        refresh()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.refreshInterval)
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func refresh() {
        let (current, now) = Self.takeSamples()
        let elapsed = Self.nanoseconds(fromMachTicks: now &- previousTime)
        defer {
            previous = current
            previousTime = now
        }
        guard elapsed > 0 else { return }

        let runningApps = Dictionary(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .map { ($0.processIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var cpuByApp: [pid_t: UInt64] = [:]
        for (pid, sample) in current {
            // A missing or restarted process spent all of its CPU time inside the window.
            let base = previous[pid].flatMap { $0.startTime == sample.startTime ? $0.cpuTicks : nil } ?? 0
            let delta = sample.cpuTicks &- base
            guard delta > 0, sample.cpuTicks >= base else { continue }

            // Helpers such as WebContent are charged to the app responsible for them.
            let owner = Self.responsiblePID(for: pid)
            let appPID = runningApps[owner] != nil ? owner : pid
            guard runningApps[appPID] != nil else { continue }
            cpuByApp[appPID, default: 0] += delta
        }

        apps = cpuByApp
            .compactMap { pid, ticks -> EnergyApp? in
                guard let app = runningApps[pid] else { return nil }
                let impact = Double(Self.nanoseconds(fromMachTicks: ticks)) / Double(elapsed) * 100
                guard impact >= Self.significantImpact else { return nil }
                return EnergyApp(
                    id: pid,
                    name: app.localizedName ?? app.bundleIdentifier ?? "\(pid)",
                    icon: app.icon,
                    impact: impact
                )
            }
            .sorted { $0.impact > $1.impact }
            .prefix(Self.maximumApps)
            .map { $0 }
    }

    // MARK: - Sampling

    private struct ProcessSample {
        let startTime: UInt64
        let cpuTicks: UInt64
    }

    private static func takeSamples() -> ([pid_t: ProcessSample], UInt64) {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        var pids = [pid_t](repeating: 0, count: max(capacity, 0))
        let count = pids.withUnsafeMutableBytes { buffer in
            Int(proc_listallpids(buffer.baseAddress, Int32(buffer.count)))
        }

        var samples: [pid_t: ProcessSample] = [:]
        samples.reserveCapacity(max(count, 0))
        for pid in pids.prefix(max(count, 0)) where pid > 0 {
            var info = rusage_info_v2()
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
                }
            }
            // Processes owned by other users fail here, which is fine: they are not apps.
            guard result == 0 else { continue }
            samples[pid] = ProcessSample(
                startTime: info.ri_proc_start_abstime,
                cpuTicks: info.ri_user_time &+ info.ri_system_time
            )
        }
        return (samples, mach_absolute_time())
    }

    /// rusage CPU times and `mach_absolute_time` share the Mach tick unit, which is
    /// not nanoseconds on Apple silicon.
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private static func nanoseconds(fromMachTicks ticks: UInt64) -> UInt64 {
        guard timebase.denom != 0 else { return ticks }
        return ticks / UInt64(timebase.denom) * UInt64(timebase.numer)
    }

    private typealias ResponsiblePIDFunction = @convention(c) (pid_t) -> pid_t

    /// Private libsystem call that Activity Monitor uses to group helper processes under
    /// their app. Looked up at runtime so a missing symbol only disables grouping.
    private static let responsiblePIDFunction: ResponsiblePIDFunction? = {
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)
        guard let symbol = dlsym(defaultHandle, "responsibility_get_pid_responsible_for_pid") else {
            return nil
        }
        return unsafeBitCast(symbol, to: ResponsiblePIDFunction.self)
    }()

    private static func responsiblePID(for pid: pid_t) -> pid_t {
        guard let responsiblePIDFunction else { return pid }
        let owner = responsiblePIDFunction(pid)
        return owner > 0 ? owner : pid
    }
}
