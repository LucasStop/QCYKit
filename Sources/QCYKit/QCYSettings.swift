import Foundation

/// Gesto físico configurável nos fones (característica `0000000D`).
public enum QCYGesture: UInt8, Equatable, Hashable, Sendable, CaseIterable {
    case leftSingleTap = 0x01
    case rightSingleTap = 0x02
    case leftDoubleTap = 0x03
    case rightDoubleTap = 0x04
    case leftTripleTap = 0x05
    case rightTripleTap = 0x06

    public enum Side: Equatable, Hashable, Sendable, CaseIterable {
        case left
        case right
    }

    public enum Tap: Int, Equatable, Hashable, Sendable, CaseIterable {
        case single = 1
        case double = 2
        case triple = 3
    }

    public var keyID: UInt8 { rawValue }

    public var side: Side {
        switch self {
        case .leftSingleTap, .leftDoubleTap, .leftTripleTap: return .left
        case .rightSingleTap, .rightDoubleTap, .rightTripleTap: return .right
        }
    }

    public var tap: Tap {
        switch self {
        case .leftSingleTap, .rightSingleTap: return .single
        case .leftDoubleTap, .rightDoubleTap: return .double
        case .leftTripleTap, .rightTripleTap: return .triple
        }
    }

    public init(side: Side, tap: Tap) {
        switch (side, tap) {
        case (.left, .single): self = .leftSingleTap
        case (.right, .single): self = .rightSingleTap
        case (.left, .double): self = .leftDoubleTap
        case (.right, .double): self = .rightDoubleTap
        case (.left, .triple): self = .leftTripleTap
        case (.right, .triple): self = .rightTripleTap
        }
    }
}

/// Função atribuída a um gesto na característica `0000000D`.
public enum QCYKeyFunction: UInt8, Equatable, Hashable, Sendable, CaseIterable {
    /// Sem ação (`0x00`). Evita `.none` para não colidir com `Optional.none` ao ler `keyMap[gesture]`.
    case unassigned = 0x00
    case playPause = 0x01
    case previousTrack = 0x02
    case nextTrack = 0x03
    case voiceAssistant = 0x04
    case volumeUp = 0x05
    case volumeDown = 0x06
    case lowLatency = 0x07
    case ancMode = 0x0B
}

/// Efeito de equalização (comando `0x22`). Os 4 medidos têm payload de escrita; outros chegam como `.unknown`.
public enum QCYSoundEffect: Equatable, Hashable, Sendable {
    case `default`
    case pop
    case heavyBass
    case spatial
    case unknown(UInt8)

    public static let measuredCases: [QCYSoundEffect] = [.default, .pop, .heavyBass, .spatial]

    public init(rawValue: UInt8) {
        switch rawValue {
        case 0x01: self = .default
        case 0x02: self = .pop
        case 0x03: self = .heavyBass
        case 0x0A: self = .spatial
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: UInt8 {
        switch self {
        case .default: return 0x01
        case .pop: return 0x02
        case .heavyBass: return 0x03
        case .spatial: return 0x0A
        case .unknown(let id): return id
        }
    }
}

/// Volume do bipe do fone (comando `0x1D`).
public enum QCYToneVolume: UInt8, Equatable, Hashable, Sendable, CaseIterable {
    case lower = 0x04
    case medium = 0x06
    case higher = 0x08
    case maximum = 0x0A
}

/// Temporizador de desligamento automático (comando `0x14`, minutos em little-endian; `0xFFFF` desativa).
public enum QCYPowerOff: Equatable, Hashable, Sendable {
    case disabled
    case minutes(UInt16)

    public static let fifteenMinutes: QCYPowerOff = .minutes(15)
    public static let thirtyMinutes: QCYPowerOff = .minutes(30)
    public static let sixtyMinutes: QCYPowerOff = .minutes(60)
    public static let ninetyMinutes: QCYPowerOff = .minutes(90)

    public init(rawMinutes: UInt16) {
        self = rawMinutes == 0xFFFF ? .disabled : .minutes(rawMinutes)
    }

    public var rawMinutes: UInt16 {
        switch self {
        case .disabled: return 0xFFFF
        case .minutes(let value): return value
        }
    }
}

/// Detecção de uso no ouvido (comando `0x2C`): estado geral, controle de música e troca de ANC.
public struct QCYWearDetection: Equatable, Hashable, Sendable {
    public enum MusicControl: UInt8, Equatable, Hashable, Sendable, CaseIterable {
        case off = 0x00
        case pauseAndResume = 0x01
        case pauseOnly = 0x02
        case bothEarbuds = 0x03
    }

    public let isEnabled: Bool
    public let musicControl: MusicControl
    public let isANCSwitchEnabled: Bool

    public init(isEnabled: Bool, musicControl: MusicControl, isANCSwitchEnabled: Bool) {
        self.isEnabled = isEnabled
        self.musicControl = musicControl
        self.isANCSwitchEnabled = isANCSwitchEnabled
    }
}

extension QCYANScene {
    public static let normal = QCYANScene(mode: 0x02, subScene: 0x00, noiseValue: 0x00)
    public static let ancAdaptive = QCYANScene(mode: 0x01, subScene: 0x05, noiseValue: 0x00)
    public static let ancIndoor = QCYANScene(mode: 0x01, subScene: 0x02, noiseValue: 0x02)
    public static let ancCommuting = QCYANScene(mode: 0x01, subScene: 0x01, noiseValue: 0x00)
    public static let transparencyVocal = QCYANScene(mode: 0x03, subScene: 0x02, noiseValue: 0x00)

    /// Transparência sem reforço vocal; nível limitado a `1...6` conforme medido no app oficial.
    public static func transparency(level: UInt8) -> QCYANScene {
        QCYANScene(mode: 0x03, subScene: 0x01, noiseValue: min(max(level, 1), 6))
    }
}
