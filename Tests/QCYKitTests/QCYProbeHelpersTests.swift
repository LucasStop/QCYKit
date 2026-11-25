import XCTest
@testable import QCYKit

final class QCYProbeHelpersTests: XCTestCase {
    func testParsesCommaSeparatedHexIDList() {
        XCTAssertEqual(
            QCYProbeFormat.parseIDList("0x16,0x14,0x1D,0x2C,0x2D,0x2E,0x20,0x22,0x44"),
            [0x16, 0x14, 0x1D, 0x2C, 0x2D, 0x2E, 0x20, 0x22, 0x44]
        )
        XCTAssertEqual(QCYProbeFormat.parseIDList(" 0X0b , 20, 0x22 "), [0x0B, 0x20, 0x22])
    }

    func testRejectsMalformedIDList() {
        XCTAssertNil(QCYProbeFormat.parseIDList(""))
        XCTAssertNil(QCYProbeFormat.parseIDList("   "))
        XCTAssertNil(QCYProbeFormat.parseIDList("0x16,"))
        XCTAssertNil(QCYProbeFormat.parseIDList(",0x16"))
        XCTAssertNil(QCYProbeFormat.parseIDList("0x100"))
        XCTAssertNil(QCYProbeFormat.parseIDList("0xZZ"))
        XCTAssertNil(QCYProbeFormat.parseIDList("0x"))
    }

    func testEncodesGenericReadRequestPacket() {
        let packet = QCYProbeFormat.requestPacket(for: 0x44)
        XCTAssertEqual(Array(packet.encoded()), [0xFF, 0x03, 0xFE, 0x01, 0x44])
    }

    func testFormatsReplyPayloadAsHexOnly() {
        XCTAssertEqual(QCYProbeFormat.formatReply(id: 0x16, payload: [0x32]), "id=0x16 len=1 hex=32")
        XCTAssertEqual(QCYProbeFormat.formatReply(id: 0x2C, payload: [0x01, 0x02, 0x0A]), "id=0x2C len=3 hex=01 02 0a")
        XCTAssertEqual(QCYProbeFormat.formatReply(id: 0x44, payload: []), "id=0x44 len=0 hex=")
    }

    func testFormatsKeyPairsAndTrailingByte() {
        XCTAssertEqual(QCYProbeFormat.formatKeyPairs([0x01, 0x05, 0x02, 0x06]), "0x01->0x05 0x02->0x06")
        XCTAssertEqual(QCYProbeFormat.formatKeyPairs([0x01, 0x05, 0xFF]), "0x01->0x05 trailing=0xFF")
        XCTAssertEqual(QCYProbeFormat.formatKeyPairs([]), "")
    }

    func testDescribesSystemDefinedMediaKeyEvents() {
        // keyCode = 16 (play), keyState = 0x0A (down), repeat = false
        let playDown = (16 << 16) | (0x0A << 8)
        XCTAssertEqual(
            QCYProbeFormat.describeSystemDefinedEvent(subtype: 8, data1: playDown),
            "key=play state=down repeat=false"
        )

        // keyCode = 17 (next), keyState = 0x0B (up), repeat = true
        let nextUpRepeat = (17 << 16) | (0x0B << 8) | 0x01
        XCTAssertEqual(
            QCYProbeFormat.describeSystemDefinedEvent(subtype: 8, data1: nextUpRepeat),
            "key=next state=up repeat=true"
        )

        // Non-media subtype ignored
        XCTAssertNil(QCYProbeFormat.describeSystemDefinedEvent(subtype: 7, data1: playDown))
    }
}
