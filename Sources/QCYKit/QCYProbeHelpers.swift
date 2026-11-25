import Foundation

/// Helpers internos de parsing e formatação para os modos somente leitura da sonda `qcyctl`.
enum QCYProbeFormat {
    /// Faz o parsing de uma lista separada por vírgula de IDs hexadecimais de 1 byte (ex: `"0x16,0x14,2C"`).
    static func parseIDList(_ text: String) -> [UInt8]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ",", omittingEmptySubsequences: false)
        var ids: [UInt8] = []
        ids.reserveCapacity(parts.count)
        for part in parts {
            var token = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { return nil }
            if token.hasPrefix("0x") || token.hasPrefix("0X") {
                token.removeFirst(2)
            }
            guard !token.isEmpty, let value = UInt8(token, radix: 16) else { return nil }
            ids.append(value)
        }
        return ids
    }

    /// Monta um pacote `0xFE` de leitura para qualquer ID de propriedade (somente leitura).
    static func requestPacket(for id: UInt8) -> QCYPacket {
        QCYPacket([QCYPacket.Block(command: QCYCommand.requestData.rawValue, parameters: [id])])
    }

    /// Formata bytes em hex minúsculo separado por espaço.
    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    /// Formata uma resposta no padrão `id=0x.. len=N hex=..` (somente payload em hex).
    static func formatReply(id: UInt8, payload: [UInt8]) -> String {
        "id=\(String(format: "0x%02X", id)) len=\(payload.count) hex=\(hex(payload))"
    }

    /// Formata pares `keyId->funId` em hex a partir do payload cru da propriedade `0x0D`.
    static func formatKeyPairs(_ bytes: [UInt8]) -> String {
        guard !bytes.isEmpty else { return "" }
        var parts: [String] = []
        var index = 0
        while index + 1 < bytes.count {
            parts.append(String(format: "0x%02X->0x%02X", bytes[index], bytes[index + 1]))
            index += 2
        }
        if index < bytes.count {
            parts.append(String(format: "trailing=0x%02X", bytes[index]))
        }
        return parts.joined(separator: " ")
    }

    private static let mediaKeyNames: [Int: String] = [
        0: "volumeUp",
        1: "volumeDown",
        7: "mute",
        16: "play",
        17: "next",
        18: "previous",
        19: "fast",
        20: "rewind"
    ]

    /// Decodifica um evento `NSEvent.EventType.systemDefined` de teclas de mídia (`subtype == 8`).
    static func describeSystemDefinedEvent(subtype: Int, data1: Int) -> String? {
        guard subtype == 8 else { return nil }
        let keyCode = (data1 & 0xFFFF0000) >> 16
        let keyFlags = data1 & 0x0000FFFF
        let keyState = (keyFlags & 0xFF00) >> 8
        let isRepeat = (keyFlags & 0x01) != 0

        let keyName = mediaKeyNames[keyCode] ?? String(format: "0x%02X", keyCode)
        let stateName: String
        switch keyState {
        case 0x0A: stateName = "down"
        case 0x0B: stateName = "up"
        default: stateName = String(format: "0x%02X", keyState)
        }

        return "key=\(keyName) state=\(stateName) repeat=\(isRepeat)"
    }
}
