import Foundation

/// Comando do canal principal do QCY (característica `00001001`). Só os que o projeto usa ou mede.
public enum QCYCommand: UInt8, Equatable, Sendable {
    case inEarDetection = 0x06
    case lowLatency = 0x09
    case noiseCancelMode = 0x0C
    case powerOff = 0x14
    case balance = 0x16
    case ancSetting = 0x17
    case toneVolume = 0x1D
    case equalizer = 0x22
    case ldac = 0x23
    case wearDetection = 0x2C
    case battery = 0x2F
    case version = 0x30
    case requestData = 0xFE
}

/// Pacote do canal principal: `[0xFF, tamanho do corpo]` seguido de um ou mais blocos
/// `[comando, quantidade de parâmetros, parâmetros...]`. Várias respostas chegam num pacote só.
public struct QCYPacket: Equatable, Sendable {
    public struct Block: Equatable, Sendable {
        public let command: UInt8
        public let parameters: [UInt8]

        public init(command: UInt8, parameters: [UInt8]) {
            self.command = command
            self.parameters = parameters
        }
    }

    public var blocks: [Block]

    public init(_ blocks: [Block]) {
        self.blocks = blocks
    }

    public init(command: QCYCommand, parameters: [UInt8] = []) {
        blocks = [Block(command: command.rawValue, parameters: parameters)]
    }

    /// Lê o que chega em `00001002`. Devolve `nil` se não for `0xFF` ou se um bloco passar do corpo.
    /// Exceção medida no firmware: a resposta do EQ (`0x22`) declara 145 bytes mas chega truncada em 20 bytes
    /// na notificação BLE; nesse caso preserva-se o prefixo recebido (que já traz o byte do id do efeito).
    public init?(data: Data) {
        let bytes = Array(data)
        guard bytes.count >= 2, bytes[0] == 0xFF else { return nil }
        let bodyLength = Int(bytes[1])
        if bodyLength > bytes.count - 2 {
            guard bytes.count >= 5,
                  bytes[2] == QCYCommand.equalizer.rawValue,
                  Int(bytes[3]) + 2 == bodyLength
            else { return nil }
            blocks = [Block(command: bytes[2], parameters: Array(bytes.dropFirst(4)))]
            return
        }
        let end = 2 + bodyLength
        var blocks: [Block] = []
        var offset = 2
        while offset + 1 < end {
            let length = Int(bytes[offset + 1])
            guard offset + 2 + length <= end else { return nil }
            blocks.append(Block(command: bytes[offset], parameters: Array(bytes[(offset + 2)..<(offset + 2 + length)])))
            offset += 2 + length
        }
        self.blocks = blocks
    }

    public func encoded() -> Data {
        var body: [UInt8] = []
        for block in blocks {
            body.append(block.command)
            body.append(UInt8(block.parameters.count))
            body.append(contentsOf: block.parameters)
        }
        return Data([0xFF, UInt8(body.count)] + body)
    }
}

extension QCYPacket {
    /// `0xFE` pede ao fone o valor atual de qualquer comando (`0x2F` bateria, `0x30` versão...).
    public static func request(_ command: QCYCommand) -> QCYPacket {
        QCYPacket(command: .requestData, parameters: [command.rawValue])
    }

    /// Modo simples (`0x0C`): 0 desligado, 1 ANC, 2 ANC externo, 3 transparência.
    public static func noiseCancelMode(_ mode: UInt8) -> QCYPacket {
        QCYPacket(command: .noiseCancelMode, parameters: [mode])
    }

    /// Cena de ANC (`0x17`) usada por quem tem nível por ambiente.
    public static func ancSetting(mode: UInt8, subScene: UInt8, noiseValue: UInt8) -> QCYPacket {
        QCYPacket(command: .ancSetting, parameters: [mode, subScene, noiseValue])
    }

    public static func ancSetting(_ scene: QCYANScene) -> QCYPacket {
        ancSetting(mode: scene.mode, subScene: scene.subScene, noiseValue: scene.noiseValue)
    }

    public static func ancNormal() -> QCYPacket { ancSetting(.normal) }
    public static func ancAdaptive() -> QCYPacket { ancSetting(.ancAdaptive) }
    public static func ancIndoor() -> QCYPacket { ancSetting(.ancIndoor) }
    public static func ancCommuting() -> QCYPacket { ancSetting(.ancCommuting) }
    public static func transparencyVocal() -> QCYPacket { ancSetting(.transparencyVocal) }

    public static func transparency(level: UInt8) -> QCYPacket {
        ancSetting(.transparency(level: level))
    }

    /// `0x01` liga, `0x02` desliga — mesmo par para jogo, detecção de ouvido e LDAC.
    public static func setLowLatency(_ enabled: Bool) -> QCYPacket {
        QCYPacket(command: .lowLatency, parameters: [enabled ? 0x01 : 0x02])
    }

    public static func setInEarDetection(_ enabled: Bool) -> QCYPacket {
        QCYPacket(command: .inEarDetection, parameters: [enabled ? 0x01 : 0x02])
    }

    public static func setLDAC(_ enabled: Bool) -> QCYPacket {
        QCYPacket(command: .ldac, parameters: [enabled ? 0x01 : 0x02])
    }

    /// Balanço L/R (`0x16`): `0x00` (L100) a `0x64` (R100), centro `0x32`.
    public static func setBalance(_ value: UInt8) -> QCYPacket {
        QCYPacket(command: .balance, parameters: [min(value, 0x64)])
    }

    /// Desligamento automático (`0x14`): minutos little-endian + `00 00` (`0xFFFF` desativa).
    public static func setPowerOff(_ powerOff: QCYPowerOff) -> QCYPacket {
        let raw = powerOff.rawMinutes
        return QCYPacket(command: .powerOff, parameters: [UInt8(raw & 0xFF), UInt8(raw >> 8), 0x00, 0x00])
    }

    /// Volume do bipe (`0x1D`): escrita envia `[nivel, 0x00]`; a resposta traz o máximo `0x0F` no segundo byte.
    public static func setToneVolume(_ volume: QCYToneVolume) -> QCYPacket {
        QCYPacket(command: .toneVolume, parameters: [volume.rawValue, 0x00])
    }

    /// Detecção de uso (`0x2C`): escrita envia 3 bytes `[W, M, A]`; resposta devolve 4 bytes (4º ignorado).
    public static func setWearDetection(_ setting: QCYWearDetection) -> QCYPacket {
        QCYPacket(command: .wearDetection, parameters: [
            setting.isEnabled ? 0x01 : 0x00,
            setting.musicControl.rawValue,
            setting.isANCSwitchEnabled ? 0x01 : 0x00
        ])
    }

    /// Efeito de equalização (`0x22`, 143 bytes de parâmetros). Devolve `nil` para IDs não medidos.
    public static func setSoundEffect(_ effect: QCYSoundEffect) -> QCYPacket? {
        guard let prefix = Self.soundEffectPrefixes[effect] else { return nil }
        var parameters = prefix
        parameters.reserveCapacity(143)
        for _ in 0..<14 {
            parameters.append(contentsOf: Self.emptyEQBand)
        }
        return QCYPacket(command: .equalizer, parameters: parameters)
    }

    private static let emptyEQBand: [UInt8] = [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF]

    private static let defaultEQTail: [UInt8] = [
        0x00, 0x00, 0x1E, 0x00, 0x00, 0x00, 0x46, 0x00, 0x04, 0xDC, 0x00,
        0xE0, 0xFC, 0x64, 0x00, 0x00, 0x84, 0x03, 0x38, 0xFF, 0x96, 0x00,
        0x00, 0xF0, 0x0A, 0x90, 0x01, 0x64, 0x00, 0x00, 0xE0, 0x2E, 0x2C,
        0x01, 0x50, 0x00, 0x00, 0xB4, 0x14, 0xD4, 0xFE, 0xC8, 0x00, 0x00
    ]

    /// Prefixos de 45 bytes gravados via PacketLogger no app oficial da QCY (2026-11-25).
    private static let soundEffectPrefixes: [QCYSoundEffect: [UInt8]] = [
        .default: [0x01] + defaultEQTail,
        .pop: [
            0x02, 0x00, 0x00, 0x1E, 0x00, 0x00, 0x00, 0x28, 0x00, 0x04, 0xDC, 0x00,
            0xE0, 0xFC, 0x64, 0x00, 0x00, 0xF0, 0x0A, 0x5E, 0x01, 0x64, 0x00,
            0x00, 0xE0, 0x2E, 0x2C, 0x01, 0x50, 0x00, 0x00, 0xB4, 0x14, 0xD4,
            0xFE, 0xC8, 0x00, 0x00, 0x3C, 0x00, 0xD4, 0xFE, 0x32, 0x00, 0x00
        ],
        .heavyBass: [
            0x03, 0x00, 0x00, 0x1E, 0x00, 0x00, 0x00, 0x46, 0x00, 0x04, 0xDC, 0x00,
            0xE0, 0xFC, 0x64, 0x00, 0x00, 0xF0, 0x0A, 0x64, 0x00, 0x64, 0x00,
            0x00, 0xE0, 0x2E, 0x20, 0x03, 0x50, 0x00, 0x00, 0xB4, 0x14, 0x0C,
            0xFE, 0xC8, 0x00, 0x00, 0x3C, 0x00, 0xF4, 0x01, 0x3C, 0x00, 0x00
        ],
        .spatial: [0x0A] + defaultEQTail
    ]
}
