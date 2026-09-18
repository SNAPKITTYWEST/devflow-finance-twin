import SwiftUI
import Foundation

// ============================================================
// M5 DETERMINISTIC MEMORY GATEWAY
// Swift Front-End OS Prototype
// 0.0 Deterministic Memory Buffer
// ============================================================

// MARK: - Configuration

enum M5Config {
    static let version = "0.0"
    static let memorySize = 4096
    static let wordSize = 8
    static let maxCommandLength = 256
}

// MARK: - Gateway Errors

enum GatewayError: Error, CustomStringConvertible {
    case addressOutOfBounds
    case lengthOutOfBounds
    case invalidCommand
    case invalidValue
    case memoryLocked
    case emptyBuffer

    var description: String {
        switch self {
        case .addressOutOfBounds:
            return "ADDRESS_OUT_OF_BOUNDS"
        case .lengthOutOfBounds:
            return "LENGTH_OUT_OF_BOUNDS"
        case .invalidCommand:
            return "INVALID_COMMAND"
        case .invalidValue:
            return "INVALID_VALUE"
        case .memoryLocked:
            return "MEMORY_LOCKED"
        case .emptyBuffer:
            return "EMPTY_BUFFER"
        }
    }
}

// MARK: - Deterministic Memory Cell

struct MemoryCell: Identifiable {
    let id: Int
    let address: Int
    var value: UInt8
}

// MARK: - Deterministic Memory Buffer

final class DeterministicMemoryBuffer: ObservableObject {

    let capacity: Int

    @Published private(set) var bytes: [UInt8]
    @Published private(set) var locked: Bool = false

    init(capacity: Int = M5Config.memorySize) {
        self.capacity = capacity
        self.bytes = Array(repeating: 0, count: capacity)
    }

    func reset() {
        guard !locked else { return }
        bytes = Array(repeating: 0, count: capacity)
    }

    func lock() {
        locked = true
    }

    func unlock() {
        locked = false
    }

    func validate(address: Int, length: Int) throws {
        guard address >= 0,
              address < capacity else {
            throw GatewayError.addressOutOfBounds
        }

        guard length >= 0,
              address + length <= capacity else {
            throw GatewayError.lengthOutOfBounds
        }
    }

    func read(address: Int, length: Int) throws -> [UInt8] {
        try validate(address: address, length: length)

        return Array(
            bytes[address ..< address + length]
        )
    }

    func write(address: Int, values: [UInt8]) throws {
        guard !locked else {
            throw GatewayError.memoryLocked
        }

        try validate(
            address: address,
            length: values.count
        )

        for offset in 0 ..< values.count {
            bytes[address + offset] = values[offset]
        }
    }

    func writeByte(
        address: Int,
        value: UInt8
    ) throws {
        try write(
            address: address,
            values: [value]
        )
    }

    func readByte(
        address: Int
    ) throws -> UInt8 {
        try validate(
            address: address,
            length: 1
        )

        return bytes[address]
    }

    func checksum() -> UInt64 {
        var result: UInt64 = 0

        for byte in bytes {
            result = result &+ UInt64(byte)
        }

        return result
    }

    func cells(
        start: Int = 0,
        count: Int = 128
    ) -> [MemoryCell] {

        let safeStart = max(0, start)
        let safeEnd = min(
            capacity,
            safeStart + max(0, count)
        )

        return Array(
            safeStart ..< safeEnd
        ).map {
            MemoryCell(
                id: $0,
                address: $0,
                value: bytes[$0]
            )
        }
    }
}

// MARK: - CPU Register State

struct RegisterState {

    var r0: UInt64 = 0
    var r1: UInt64 = 0
    var r2: UInt64 = 0
    var r3: UInt64 = 0

    var pc: UInt64 = 0
    var sp: UInt64 = 0

    var status: UInt64 = 0

    mutating func reset() {
        r0 = 0
        r1 = 0
        r2 = 0
        r3 = 0
        pc = 0
        sp = 0
        status = 0
    }
}

// MARK: - Gateway Result

struct GatewayResult {

    let success: Bool
    let message: String

    static func ok(
        _ message: String
    ) -> GatewayResult {
        GatewayResult(
            success: true,
            message: message
        )
    }

    static func failure(
        _ message: String
    ) -> GatewayResult {
        GatewayResult(
            success: false,
            message: message
        )
    }
}

// MARK: - M5 OS Gateway

final class M5Gateway: ObservableObject {

    @Published var registers = RegisterState()

    @Published private(set) var lastResult =
        GatewayResult.ok("READY")

    let memory = DeterministicMemoryBuffer()

    func resetSystem() {
        memory.unlock()
        memory.reset()
        registers.reset()

        lastResult =
            .ok("SYSTEM_RESET")
    }

    func write(
        address: Int,
        value: UInt8
    ) {

        do {
            try memory.writeByte(
                address: address,
                value: value
            )

            lastResult = .ok(
                "WRITE \(address) = \(value)"
            )

        } catch {
            lastResult =
                .failure(error.localizedDescription)
        }
    }

    func read(
        address: Int
    ) {

        do {
            let value =
                try memory.readByte(
                    address: address
                )

            lastResult = .ok(
                "READ \(address) = \(value)"
            )

        } catch {
            lastResult =
                .failure(error.localizedDescription)
        }
    }

    func execute(
        command: String
    ) {

        let tokens =
            command
                .split(separator: " ")
                .map(String.init)

        guard !tokens.isEmpty else {
            lastResult =
                .failure(
                    GatewayError.emptyBuffer.description
                )
            return
        }

        switch tokens[0].uppercased() {

        case "RESET":

            resetSystem()

        case "LOCK":

            memory.lock()

            lastResult =
                .ok("MEMORY_LOCKED")

        case "UNLOCK":

            memory.unlock()

            lastResult =
                .ok("MEMORY_UNLOCKED")

        case "READ":

            guard tokens.count == 2,
                  let address =
                    Int(tokens[1]) else {

                lastResult =
                    .failure(
                        GatewayError.invalidCommand.description
                    )

                return
            }

            read(address: address)

        case "WRITE":

            guard tokens.count == 3,
                  let address =
                    Int(tokens[1]),
                  let value =
                    UInt8(tokens[2]) else {

                lastResult =
                    .failure(
                        GatewayError.invalidCommand.description
                    )

                return
            }

            write(
                address: address,
                value: value
            )

        case "CHECKSUM":

            lastResult =
                .ok(
                    "CHECKSUM \(memory.checksum())"
                )

        case "STATUS":

            lastResult =
                .ok(
                    statusString()
                )

        default:

            lastResult =
                .failure(
                    GatewayError.invalidCommand.description
                )
        }
    }

    func statusString() -> String {

        let lockState =
            memory.locked
            ? "LOCKED"
            : "UNLOCKED"

        return """
        M5-OS \(M5Config.version)
        MEMORY \(memory.capacity) BYTES
        \(lockState)
        PC \(registers.pc)
        SP \(registers.sp)
        """
    }
}

// MARK: - Memory Cell View

struct MemoryCellView: View {

    let cell: MemoryCell

    var body: some View {

        HStack {

            Text(
                String(
                    format: "0x%04X",
                    cell.address
                )
            )
            .font(
                .system(
                    .body,
                    design: .monospaced
                )
            )

            Spacer()

            Text(
                String(
                    format: "%02X",
                    cell.value
                )
            )
            .font(
                .system(
                    .body,
                    design: .monospaced
                )
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - Register Panel

struct RegisterPanel: View {

    @ObservedObject var gateway: M5Gateway

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 8
        ) {

            Text("REGISTERS")
                .font(.headline)

            register(
                "R0",
                gateway.registers.r0
            )

            register(
                "R1",
                gateway.registers.r1
            )

            register(
                "R2",
                gateway.registers.r2
            )

            register(
                "R3",
                gateway.registers.r3
            )

            register(
                "PC",
                gateway.registers.pc
            )

            register(
                "SP",
                gateway.registers.sp
            )
        }
        .padding()
    }

    private func register(
        _ name: String,
        _ value: UInt64
    ) -> some View {

        HStack {

            Text(name)
                .font(
                    .system(
                        .body,
                        design: .monospaced
                    )
                )

            Spacer()

            Text(
                String(format: "%016llX", value)
            )
            .font(
                .system(
                    .body,
                    design: .monospaced
                )
            )
        }
    }
}

// MARK: - Gateway Console

struct GatewayConsole: View {

    @ObservedObject var gateway: M5Gateway

    @State private var command = ""

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 10
        ) {

            Text("GATEWAY")

                .font(.headline)

            HStack {

                TextField(
                    "READ 0 / WRITE 0 255 / STATUS",
                    text: $command
                )
                .textFieldStyle(.roundedBorder)

                Button("EXEC") {

                    gateway.execute(
                        command: command
                    )

                    command = ""
                }
            }

            Text(
                gateway.lastResult.message
            )
            .font(
                .system(
                    .body,
                    design: .monospaced
                )
            )
        }
        .padding()
    }
}

// MARK: - Memory Inspector

struct MemoryInspector: View {

    @ObservedObject var gateway: M5Gateway

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 0
        ) {

            Text("MEMORY BUFFER")
                .font(.headline)
                .padding()

            ScrollView {

                LazyVStack(
                    spacing: 0
                ) {

                    ForEach(
                        gateway.memory.cells()
                    ) { cell in

                        MemoryCellView(
                            cell: cell
                        )

                        Divider()
                    }
                }
            }
        }
    }
}

// MARK: - Main OS Interface

struct M5OSView: View {

    @StateObject private var gateway =
        M5Gateway()

    var body: some View {

        NavigationStack {

            VStack(
                spacing: 0
            ) {

                HStack {

                    VStack(
                        alignment: .leading
                    ) {

                        Text("M5 OS")
                            .font(.largeTitle)
                            .bold()

                        Text(
                            "DETERMINISTIC MEMORY GATEWAY 0.0"
                        )
                        .font(
                            .system(
                                .caption,
                                design: .monospaced
                            )
                        )
                    }

                    Spacer()

                    Button("RESET") {

                        gateway.resetSystem()
                    }
                }
                .padding()

                Divider()

                HStack(
                    alignment: .top,
                    spacing: 0
                ) {

                    RegisterPanel(
                        gateway: gateway
                    )
                    .frame(
                        maxWidth: 320
                    )

                    Divider()

                    MemoryInspector(
                        gateway: gateway
                    )
                }

                Divider()

                GatewayConsole(
                    gateway: gateway
                )
            }
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Application Entry

@main
struct M5OSApp: App {

    var body: some Scene {

        WindowGroup {

            M5OSView()
        }
    }
}
