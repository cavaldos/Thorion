import Foundation
import SMCKit

public enum SMCComponentPowerError: Error, Sendable {
    case readFailed(component: String, underlying: String)
}

/*
* Total system power draw, its CPU and display shares, adapter rated power and CPU/GPU
* die temperature.
*
* The SMC keyspace is not uniform across Mac models or macOS releases, so nothing
* here assumes a key exists. Every field resolves through an ordered candidate list
* and takes the first key that is both present and carrying a 32-bit float.
*
* Key selections were verified by enumerating the full SMC key table on an M1 Pro
* (macOS 27.0.1) and correlating readings against synthetic eight-core CPU load.
* Notes below are empirical for that machine; other models will need their own
* candidates.
*
* Why the data type is checked before decoding: SMCReadKey does not validate that the
* requested Swift type matches the key's SMC data type, and SMCKit's SMCCodable
* conformances simply reinterpret the first bytes. Reading a key typed `ioft ` (8
* bytes) as a Float therefore succeeds and returns a large meaningless number instead
* of throwing. Probing with isKeyFound alone is not enough, so each candidate's type is
* verified against `flt ` before the value is read.
*/
public struct SMCComponentPower {

    // Measured on M1 Pro: PSTR tracked load from 3.3 W idle to 25.0 W under eight-core
    // load, while PDTR decoded cleanly but was pinned at 0.0. PSTR is probed first so
    // a machine that populates only PDTR still works without a bogus zero from PSTR.
    private static let totalPowerKeys: [FourCharCode] = ["PSTR", "PDTR"]

    // Measured on M1 Pro: SBAW exists and decodes cleanly as `flt ` but is pinned at
    // 0.0 across every sample, while SBAS held a stable 84-86 W adapter rating. SBAW
    // is therefore tried first per the documented key, but a 0 W adapter rating is not
    // a physically meaningful value, so a zero is treated as unpopulated and SBAS is
    // used instead. Without this the UI would show a 0 W adapter on these machines.
    private static let adapterRatedPowerKeys: [FourCharCode] = ["SBAW", "SBAS"]

    // Measured on M1 Pro (macOS 27.2): PHPC rose from 2.7 W idle to 13.5 W under
    // eight-core load and fell back to 3.4 W on cooldown, so it tracks the CPU. PCPC is
    // the Intel CPU package key and is kept as a fallback for those machines.
    private static let cpuPowerKeys: [FourCharCode] = ["PHPC", "PCPC"]

    // Measured on M1 Pro (macOS 27.2): PDBR held 1.40-1.44 W at a fixed brightness and
    // did not move under CPU load, matching the display figure AlDente reports.
    private static let displayPowerKeys: [FourCharCode] = ["PDBR"]

    // TC0P/TC0D/TC0E/TC0F are the long-standing Intel CPU keys and none of them exist
    // on Apple Silicon. TCDX is the Apple Silicon CPU die sensor and is the fallback:
    // it measured 44.7 C idle rising to 65.5 C under eight-core load, and falling back
    // to 48.7 C on cooldown, so it genuinely tracks CPU load. ftP0 is the per-core
    // equivalent and tracked the same way (49.9 C to 70.3 C).
    private static let cpuTemperatureKeys: [FourCharCode] = [
        "TC0P", "TC0D", "TC0E", "TC0F", "TCDX", "ftP0",
    ]

    // TG0P/TG0D/TG0E are the Intel GPU keys and are absent on Apple Silicon. The
    // remaining GPU-named keys on Apple Silicon - TG0B, TG0C, TG0H, TG0V, TG1B, TG2B -
    // are typed `ioft ` at 8 bytes, not `flt `, so they are deliberately excluded: they
    // cannot be decoded as a temperature and would silently yield garbage.
    //
    // ftG0/ftG1 are the remaining float-typed candidates. They decode cleanly and sit
    // at 9.3 C while eight CPU cores are loaded and the CPU die is at 65 C, which is
    // consistent with a GPU that is idle. Their behaviour under real GPU load could
    // NOT be confirmed here because neither the Metal toolchain nor the CGL headers
    // are available in this Xcode install, so treat the GPU key identification as
    // probable rather than proven.
    private static let gpuTemperatureKeys: [FourCharCode] = [
        "TG0P", "TG0D", "TG0E", "ftG0", "ftG1",
    ]

    private static let floatType = FourCharCode(fromStaticString: "flt ")

    public static func read() throws -> SMCSystemPowerReading {
        SMCSystemPowerReading(
            totalWatts: try readTotalWatts(),
            cpuWatts: try readFirstValue(from: cpuPowerKeys, component: "cpuWatts"),
            displayWatts: try readFirstValue(from: displayPowerKeys, component: "displayWatts"),
            adapterRatedWatts: try readFirstValue(
                from: adapterRatedPowerKeys,
                component: "adapterRatedWatts",
                treatZeroAsUnpopulated: true
            ),
            cpuTemperature: try readFirstValue(from: cpuTemperatureKeys, component: "cpuTemperature"),
            gpuTemperature: try readFirstValue(from: gpuTemperatureKeys, component: "gpuTemperature")
        )
    }

    private static func readTotalWatts() throws -> Double? {
        if let watts = try readFirstValue(from: totalPowerKeys, component: "totalWatts") {
            return watts
        }

        // Neither total-power key resolved, so fall back to the adapter's measured
        // power. This is a poor approximation - it excludes the SoC, display and
        // other loads that do not pass through the adapter - but it is better than
        // reporting nothing on a machine that exposes neither key.
        guard
            let current = try readFirstValue(from: ["ID0R"], component: "totalWatts"),
            let voltage = try readFirstValue(from: ["VD0R"], component: "totalWatts")
        else {
            return nil
        }
        return current * voltage
    }

    private static func readFirstValue(
        from keys: [FourCharCode],
        component: String,
        treatZeroAsUnpopulated: Bool = false
    ) throws -> Double? {
        for key in keys {
            do {
                guard let value = try readFloat(key) else { continue }
                if treatZeroAsUnpopulated && value == 0 { continue }
                return value
            } catch SMCError.keyNotFound {
                continue
            } catch {
                throw SMCComponentPowerError.readFailed(
                    component: component,
                    underlying: String(describing: error)
                )
            }
        }
        return nil
    }

    private static func readFloat(_ key: FourCharCode) throws -> Double? {
        let information = try SMCKit.shared.getKeyInformation(key)
        guard information.type == floatType, information.size == 4 else { return nil }

        let value: Float = try SMCKit.shared.read(key)
        return Double(value)
    }
}
