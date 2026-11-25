import Foundation

/// Modo atual de cancelamento de ruído (comando `0x0C`).
public enum QCYNoiseCancelMode: UInt8, Equatable, Sendable {
    case off = 0x00
    case anc = 0x01
    case outdoor = 0x02
    case transparency = 0x03

    public var name: String {
        switch self {
        case .off: return "Desligado"
        case .anc: return "ANC"
        case .outdoor: return "ANC externo"
        case .transparency: return "Transparência"
        }
    }
}

/// Cena de ANC configurada (comando `0x17`): modo de ambiente, nível e profundidade.
///
/// Não é o mesmo que o modo atual. No MeloBuds Pro os dois discordam: o `0x0C` responde `2` (ANC externo)
/// enquanto o `0x17` responde `3/2`. Guardar num campo só fazia o valor oscilar conforme a ordem das respostas.
public struct QCYANScene: Equatable, Sendable {
    public let mode: UInt8
    public let subScene: UInt8
    public let noiseValue: UInt8

    public init(mode: UInt8, subScene: UInt8, noiseValue: UInt8) {
        self.mode = mode
        self.subScene = subScene
        self.noiseValue = noiseValue
    }

    /// O documento do Quicky dá `0x02/0x01..03` como ambiente silencioso, `0x03/0x01..03` como ambiente de
    /// trabalho, `0x04/0x01..03` como ambiente ruidoso e `0x0A/0x01..07` como transparência — mas também diz
    /// que o app dele remapeia `0x03/0x01` para `0x03/0x02` no caso da transparência. Como as duas leituras se
    /// contradizem, nada de nome: sai o par em hex.
    public var name: String {
        String(format: "%02X/%02X", mode, subScene)
    }
}

/// Versão de firmware. O fone devolve 3 bytes (só o lado esquerdo) ou 6 (um conjunto por lado).
public struct QCYFirmware: Equatable, Sendable {
    public let left: String
    public let right: String?

    public init(left: String, right: String?) {
        self.left = left
        self.right = right
    }
}

/// Estado montado a partir das notificações de `00001002`. Cada resposta traz só os blocos que mudaram,
/// então o estado é acumulativo: aplica o que chegou e mantém o resto.
public struct QCYState: Equatable, Sendable {
    public var left: QCYBatteryLevel?
    public var right: QCYBatteryLevel?
    public var caseBattery: QCYBatteryLevel?
    public var firmware: QCYFirmware?
    public var noiseCancelMode: QCYNoiseCancelMode?
    public var ancScene: QCYANScene?
    public var isLowLatencyEnabled: Bool?
    public var isInEarDetectionEnabled: Bool?
    public var isLDACEnabled: Bool?
    /// Balanço L/R: `0x00` (L100) a `0x64` (R100), centro `0x32`.
    public var balance: UInt8?
    public var powerOff: QCYPowerOff?
    public var toneVolume: QCYToneVolume?
    public var wearDetection: QCYWearDetection?
    public var soundEffect: QCYSoundEffect?
    /// Mapa de gestos lido da característica `0000000D`.
    public var keyMap: [QCYGesture: QCYKeyFunction] = [:]

    public init() {}

    public mutating func apply(_ packet: QCYPacket) {
        for block in packet.blocks {
            apply(block)
        }
    }

    public mutating func apply(_ block: QCYPacket.Block) {
        guard let command = QCYCommand(rawValue: block.command) else { return }
        switch command {
        case .battery: applyBattery(block.parameters)
        case .version: applyVersion(block.parameters)
        case .noiseCancelMode: applyNoiseCancelMode(block.parameters)
        case .ancSetting: applyANScene(block.parameters)
        case .lowLatency, .inEarDetection, .ldac: applyToggle(command, block.parameters)
        default: applySettings(command, block.parameters)
        }
    }

    private mutating func applySettings(_ command: QCYCommand, _ parameters: [UInt8]) {
        switch command {
        case .balance: applyBalance(parameters)
        case .powerOff: applyPowerOff(parameters)
        case .toneVolume: applyToneVolume(parameters)
        case .wearDetection: applyWearDetection(parameters)
        case .equalizer: applyEqualizer(parameters)
        default: break
        }
    }

    /// Aplica os pares `(keyId, funId)` lidos da característica `0000000D` (20 bytes com padding zero).
    public mutating func applyKeyMap(_ data: Data) {
        let bytes = Array(data)
        var offset = 0
        while offset + 1 < bytes.count {
            if let gesture = QCYGesture(rawValue: bytes[offset]),
               let function = QCYKeyFunction(rawValue: bytes[offset + 1]) {
                keyMap[gesture] = function
            }
            offset += 2
        }
    }

    private mutating func applyBattery(_ parameters: [UInt8]) {
        guard parameters.count >= 3 else { return }
        left = QCYBatteryLevel(raw: parameters[0])
        right = QCYBatteryLevel(raw: parameters[1])
        caseBattery = parameters[2] == 0 ? nil : QCYBatteryLevel(raw: parameters[2])
    }

    private mutating func applyVersion(_ parameters: [UInt8]) {
        guard parameters.count >= 3 else { return }
        firmware = QCYFirmware(left: Self.text(parameters, from: 0),
                               right: parameters.count >= 6 ? Self.text(parameters, from: 3) : nil)
    }

    private static func text(_ parameters: [UInt8], from start: Int) -> String {
        "\(parameters[start]).\(parameters[start + 1]).\(parameters[start + 2])"
    }

    private mutating func applyNoiseCancelMode(_ parameters: [UInt8]) {
        guard let raw = parameters.first else { return }
        noiseCancelMode = QCYNoiseCancelMode(rawValue: raw)
    }

    private mutating func applyANScene(_ parameters: [UInt8]) {
        guard parameters.count >= 3 else { return }
        ancScene = QCYANScene(mode: parameters[0], subScene: parameters[1], noiseValue: parameters[2])
    }

    private mutating func applyToggle(_ command: QCYCommand, _ parameters: [UInt8]) {
        guard let value = parameters.first else { return }
        let isEnabled = value == 0x01
        switch command {
        case .lowLatency: isLowLatencyEnabled = isEnabled
        case .inEarDetection: isInEarDetectionEnabled = isEnabled
        case .ldac: isLDACEnabled = isEnabled
        default: break
        }
    }

    private mutating func applyBalance(_ parameters: [UInt8]) {
        guard let value = parameters.first, value <= 0x64 else { return }
        balance = value
    }

    private mutating func applyPowerOff(_ parameters: [UInt8]) {
        guard parameters.count >= 2 else { return }
        let raw = UInt16(parameters[0]) | (UInt16(parameters[1]) << 8)
        powerOff = QCYPowerOff(rawMinutes: raw)
    }

    private mutating func applyToneVolume(_ parameters: [UInt8]) {
        guard let raw = parameters.first else { return }
        toneVolume = QCYToneVolume(rawValue: raw)
    }

    private mutating func applyWearDetection(_ parameters: [UInt8]) {
        guard parameters.count >= 3,
              let musicControl = QCYWearDetection.MusicControl(rawValue: parameters[1])
        else { return }
        wearDetection = QCYWearDetection(
            isEnabled: parameters[0] == 0x01,
            musicControl: musicControl,
            isANCSwitchEnabled: parameters[2] == 0x01
        )
    }

    private mutating func applyEqualizer(_ parameters: [UInt8]) {
        guard let id = parameters.first else { return }
        soundEffect = QCYSoundEffect(rawValue: id)
    }
}
