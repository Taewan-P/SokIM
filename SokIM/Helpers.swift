import os
import Darwin
import IOKit.hid
import Foundation

// MARK: - Logger

func debug(_ message: String = "",
           fileID: String = #fileID,
           function: String = #function) {
    if Preferences.debug {
        Logger().debug("\(fileID, privacy: .public): \(function, privacy: .public) \(message, privacy: .public)")
    }
}

func notice(_ message: String = "",
            fileID: String = #fileID,
            function: String = #function) {
    Logger().notice("\(fileID, privacy: .public): \(function, privacy: .public) \(message, privacy: .public)")
}

func warning(_ message: String = "",
             fileID: String = #fileID,
             function: String = #function) {
    Logger().warning("\(fileID, privacy: .public): \(function, privacy: .public) \(message, privacy: .public)")
}

// MARK: - Array & Dictionary

@inlinable func flip<T>(_ array: [T]) -> [T: Int] { Dictionary(uniqueKeysWithValues: zip(array, 0..<array.count)) }
@inlinable func flip<T, U>(_ dictionary: [T: U]) -> [U: T] { dictionary.reduce(into: [:]) { $0[$1.value] = $1.key } }

// MARK: - Etc

// https://developer.apple.com/library/archive/qa/qa1398/
private var sTimebaseInfo = mach_timebase_info()
func ms(since: UInt64) -> Int64 {
    let current = mach_absolute_time()

    if sTimebaseInfo.denom == 0 {
        guard mach_timebase_info(&sTimebaseInfo) == KERN_SUCCESS else {
            return 0
        }
    }

    let diff = Int64(current) - Int64(since)
    let nsec = diff * Int64(sTimebaseInfo.numer) / Int64(sTimebaseInfo.denom)

    return nsec / Int64(NSEC_PER_MSEC)
}

/**
 "보조 키(Modifier Keys)" 매핑 설정에 맞는 usage 값 반환
 @see https://developer.apple.com/library/archive/technotes/tn2450/
 @see https://stackoverflow.com/a/37648516
 */
func getMappedModifierUsage(_ usage: UInt32, _ device: IOHIDDevice) -> UInt32 {
    guard let vendor = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int,
          let product = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int else {
        warning("알 수 없는 키보드: \(device)")

        return usage
    }

    let key = "com.apple.keyboard.modifiermapping.\(vendor)-\(product)-0"
    guard let maps = UserDefaults.standard.object(forKey: key) as? [[String: UInt64]] else {
        // 설정이 없는 경우 그대로 반환
        return usage
    }

    for map in maps {
        guard let src = map["HIDKeyboardModifierMappingSrc"],
              let dst = map["HIDKeyboardModifierMappingDst"] else {
            continue
        }

        // 설정에 매핑되어 있으면 맞는 값 반환
        if src & 0xFF == usage {
            debug("\(vendor) \(product): \(String(format: "0x%X", src)) -> \(String(format: "0x%X", dst))")

            return UInt32(dst & 0xFF)
        }
    }

    // 설정은 있으나 매핑이 없으면 그대로 반환
    return usage
}

/**
 연결된 키보드에 대해 Caps Lock 상태 및 LED 조정
 @see https://stackoverflow.com/a/75870807
 */
func setKeyboardCapsLock(enabled: Bool) {
    let block = {
        var conn = io_connect_t()
        let serv = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))

        guard IOServiceOpen(serv, mach_task_self_, UInt32(kIOHIDParamConnectType), &conn) == KERN_SUCCESS else {
            warning("IOServiceOpen 실패: \(serv)")
            return
        }
        defer { IOServiceClose(conn) }

        guard IOHIDSetModifierLockState(conn, Int32(kIOHIDCapsLockState), enabled) == KERN_SUCCESS else {
            warning("IOHIDSetModifierLockState 실패: \(conn)")
            return
        }

        debug("IOHIDSetModifierLockState 성공: \(conn) \(enabled)")
    }

    DispatchQueue.main.asyncAfter(deadline: .now(), execute: block)
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100), execute: block)
}

func getKeyboardCapsLock() -> Bool {
    var conn = io_connect_t()
    let serv = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))

    guard IOServiceOpen(serv, mach_task_self_, UInt32(kIOHIDParamConnectType), &conn) == KERN_SUCCESS else {
        warning("IOServiceOpen 실패: \(serv)")
        return false
    }
    defer { IOServiceClose(conn) }

    var enabled = false
    guard IOHIDGetModifierLockState(conn, Int32(kIOHIDCapsLockState), &enabled) == KERN_SUCCESS else {
        warning("IOHIDGetModifierLockState 실패: \(conn)")
        return false
    }

    debug("IOHIDGetModifierLockState 성공: \(conn) \(enabled)")

    return enabled
}
