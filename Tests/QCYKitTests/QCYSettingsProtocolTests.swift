import XCTest
@testable import QCYKit

/// Cobertura dos comandos medidos em 2026-11-25 (cenas nomeadas, balanço, desligamento, bipe, detecção de uso,
/// efeitos de EQ e gestos da característica `000D`), todos conferidos contra fixtures gravadas via PacketLogger.
final class QCYSettingsProtocolTests: XCTestCase {
    // MARK: - Cenas nomeadas (0x17)

    private struct SceneCase {
        let packet: QCYPacket
        let expectedScene: QCYANScene
        let fixture: String
    }

    private struct EffectCase {
        let effect: QCYSoundEffect
        let writeFixture: String
        let notifyFixture: String
    }

    func testNamedANCScenesMatchMeasuredFixturesAndRoundTrip() throws {
        let cases: [SceneCase] = [
            SceneCase(packet: .ancNormal(), expectedScene: .normal, fixture: "qcy-anc-normal"),
            SceneCase(packet: .ancAdaptive(), expectedScene: .ancAdaptive, fixture: "qcy-anc-adaptive"),
            SceneCase(packet: .ancIndoor(), expectedScene: .ancIndoor, fixture: "qcy-anc-indoor"),
            SceneCase(packet: .ancCommuting(), expectedScene: .ancCommuting, fixture: "qcy-anc-commuting"),
            SceneCase(packet: .transparencyVocal(), expectedScene: .transparencyVocal,
                      fixture: "qcy-transparency-vocal"),
            SceneCase(packet: .transparency(level: 3), expectedScene: .transparency(level: 3),
                      fixture: "qcy-transparency-level-3")
        ]

        for item in cases {
            let expectedBytes = try qcyFixture(item.fixture)
            XCTAssertEqual(Array(item.packet.encoded()), expectedBytes, item.fixture)

            let decoded = try XCTUnwrap(QCYPacket(data: Data(expectedBytes)))
            XCTAssertEqual(decoded, item.packet, item.fixture)

            var state = QCYState()
            state.apply(decoded)
            XCTAssertEqual(state.ancScene, item.expectedScene, item.fixture)
        }
    }

    func testTransparencyLevelClampsToMeasuredRange() {
        XCTAssertEqual(QCYANScene.transparency(level: 0).noiseValue, 1)
        XCTAssertEqual(QCYANScene.transparency(level: 1).noiseValue, 1)
        XCTAssertEqual(QCYANScene.transparency(level: 6).noiseValue, 6)
        XCTAssertEqual(QCYANScene.transparency(level: 9).noiseValue, 6)
        XCTAssertEqual(Array(QCYPacket.transparency(level: 6).encoded()), [0xFF, 0x05, 0x17, 0x03, 0x03, 0x01, 0x06])
    }

    // MARK: - Balanço (0x16)

    func testBalanceEncodeDecodeAndClamp() throws {
        let centerBytes = try qcyFixture("qcy-balance-center")
        let rightBytes = try qcyFixture("qcy-balance-right")

        XCTAssertEqual(Array(QCYPacket.setBalance(0x32).encoded()), centerBytes)
        XCTAssertEqual(Array(QCYPacket.setBalance(0x5F).encoded()), rightBytes)
        XCTAssertEqual(Array(QCYPacket.setBalance(0xFF).encoded()), [0xFF, 0x03, 0x16, 0x01, 0x64])
        XCTAssertEqual(Array(QCYPacket.request(.balance).encoded()), [0xFF, 0x03, 0xFE, 0x01, 0x16])

        var state = QCYState()
        state.apply(try XCTUnwrap(QCYPacket(data: Data(rightBytes))))
        XCTAssertEqual(state.balance, 0x5F)
        state.apply(try XCTUnwrap(QCYPacket(data: Data(centerBytes))))
        XCTAssertEqual(state.balance, 0x32)
        // Valor acima de 0x64 é ignorado sem corromper o estado anterior.
        state.apply(QCYPacket.Block(command: QCYCommand.balance.rawValue, parameters: [0x65]))
        XCTAssertEqual(state.balance, 0x32)
    }

    // MARK: - Desligamento automático (0x14)

    func testPowerOffMatchesMeasuredFixturesAndRoundTrip() throws {
        let cases: [(QCYPowerOff, String)] = [
            (.disabled, "qcy-poweroff-disabled"),
            (.fifteenMinutes, "qcy-poweroff-15m"),
            (.thirtyMinutes, "qcy-poweroff-30m"),
            (.sixtyMinutes, "qcy-poweroff-60m"),
            (.ninetyMinutes, "qcy-poweroff-90m")
        ]

        XCTAssertEqual(Array(QCYPacket.request(.powerOff).encoded()), [0xFF, 0x03, 0xFE, 0x01, 0x14])

        for (setting, fixture) in cases {
            let expectedBytes = try qcyFixture(fixture)
            let packet = QCYPacket.setPowerOff(setting)
            XCTAssertEqual(Array(packet.encoded()), expectedBytes, fixture)

            let decoded = try XCTUnwrap(QCYPacket(data: Data(expectedBytes)))
            XCTAssertEqual(decoded, packet, fixture)

            var state = QCYState()
            state.apply(decoded)
            XCTAssertEqual(state.powerOff, setting, fixture)
        }

        // Minutos em little-endian acima de 255 (ex.: 300 min = 0x012C -> 2C 01).
        let custom = QCYPacket.setPowerOff(.minutes(300))
        XCTAssertEqual(Array(custom.encoded()), [0xFF, 0x06, 0x14, 0x04, 0x2C, 0x01, 0x00, 0x00])
        var state = QCYState()
        state.apply(try XCTUnwrap(QCYPacket(data: custom.encoded())))
        XCTAssertEqual(state.powerOff, .minutes(300))
    }

    // MARK: - Volume do bipe (0x1D)

    func testToneVolumeWriteAndReadFixtures() throws {
        XCTAssertEqual(Array(QCYPacket.setToneVolume(.lower).encoded()),
                       try qcyFixture("qcy-tone-volume-write-lower"))
        XCTAssertEqual(Array(QCYPacket.setToneVolume(.higher).encoded()),
                       try qcyFixture("qcy-tone-volume-write-higher"))
        XCTAssertEqual(Array(QCYPacket.setToneVolume(.medium).encoded()), [0xFF, 0x04, 0x1D, 0x02, 0x06, 0x00])
        XCTAssertEqual(Array(QCYPacket.setToneVolume(.maximum).encoded()), [0xFF, 0x04, 0x1D, 0x02, 0x0A, 0x00])
        XCTAssertEqual(Array(QCYPacket.request(.toneVolume).encoded()), [0xFF, 0x03, 0xFE, 0x01, 0x1D])

        var state = QCYState()
        state.apply(try XCTUnwrap(QCYPacket(data: Data(try qcyFixture("qcy-tone-volume-read-higher")))))
        XCTAssertEqual(state.toneVolume, .higher)

        state.apply(try XCTUnwrap(QCYPacket(data: Data(try qcyFixture("qcy-tone-volume-read-max")))))
        XCTAssertEqual(state.toneVolume, .maximum)

        // Round-trip também funciona a partir do quadro de escrita (segundo byte 0x00).
        state.apply(try XCTUnwrap(QCYPacket(data: QCYPacket.setToneVolume(.lower).encoded())))
        XCTAssertEqual(state.toneVolume, .lower)
    }

    // MARK: - Detecção de uso (0x2C)

    func testWearDetectionWriteAndReadFixtures() throws {
        let setting = QCYWearDetection(isEnabled: true, musicControl: .pauseOnly, isANCSwitchEnabled: true)
        let writeBytes = try qcyFixture("qcy-wear-detection-write")
        let readBytes = try qcyFixture("qcy-wear-detection-read")

        XCTAssertEqual(Array(QCYPacket.setWearDetection(setting).encoded()), writeBytes)
        XCTAssertEqual(Array(QCYPacket.request(.wearDetection).encoded()), [0xFF, 0x03, 0xFE, 0x01, 0x2C])

        // Leitura real (4 parâmetros) e round-trip de escrita (3 parâmetros) produzem o mesmo estado.
        var fromRead = QCYState()
        fromRead.apply(try XCTUnwrap(QCYPacket(data: Data(readBytes))))
        XCTAssertEqual(fromRead.wearDetection, setting)

        var fromWrite = QCYState()
        fromWrite.apply(try XCTUnwrap(QCYPacket(data: Data(writeBytes))))
        XCTAssertEqual(fromWrite.wearDetection, setting)

        let disabled = QCYWearDetection(isEnabled: false, musicControl: .off, isANCSwitchEnabled: false)
        XCTAssertEqual(Array(QCYPacket.setWearDetection(disabled).encoded()),
                       [0xFF, 0x05, 0x2C, 0x03, 0x00, 0x00, 0x00])
        var offState = QCYState()
        offState.apply(try XCTUnwrap(QCYPacket(data: QCYPacket.setWearDetection(disabled).encoded())))
        XCTAssertEqual(offState.wearDetection, disabled)
    }

    // MARK: - Efeitos de EQ (0x22)

    func testSoundEffectWritePacketsMatchFullMeasuredFixtures() throws {
        let cases: [EffectCase] = [
            EffectCase(effect: .default, writeFixture: "qcy-eq-write-default", notifyFixture: "qcy-eq-notify-default"),
            EffectCase(effect: .pop, writeFixture: "qcy-eq-write-pop", notifyFixture: "qcy-eq-notify-pop"),
            EffectCase(effect: .heavyBass, writeFixture: "qcy-eq-write-heavy-bass",
                       notifyFixture: "qcy-eq-notify-heavy-bass"),
            EffectCase(effect: .spatial, writeFixture: "qcy-eq-write-spatial", notifyFixture: "qcy-eq-notify-spatial")
        ]

        XCTAssertEqual(Array(QCYPacket.request(.equalizer).encoded()), [0xFF, 0x03, 0xFE, 0x01, 0x22])
        XCTAssertNil(QCYPacket.setSoundEffect(.unknown(0x05)))

        for item in cases {
            let expectedWrite = try qcyFixture(item.writeFixture)
            let packet = try XCTUnwrap(QCYPacket.setSoundEffect(item.effect), item.writeFixture)
            XCTAssertEqual(Array(packet.encoded()), expectedWrite, item.writeFixture)
            XCTAssertEqual(expectedWrite.count, 147)

            // Round-trip completo dos 147 bytes.
            let decodedFull = try XCTUnwrap(QCYPacket(data: Data(expectedWrite)), item.writeFixture)
            XCTAssertEqual(decodedFull, packet, item.writeFixture)

            var fullState = QCYState()
            fullState.apply(decodedFull)
            XCTAssertEqual(fullState.soundEffect, item.effect, item.writeFixture)

            // Notificação truncada em 20 bytes vinda do fone.
            let notifyBytes = try qcyFixture(item.notifyFixture)
            XCTAssertEqual(notifyBytes.count, 20)
            let decodedTruncated = try XCTUnwrap(QCYPacket(data: Data(notifyBytes)), item.notifyFixture)
            var notifyState = QCYState()
            notifyState.apply(decodedTruncated)
            XCTAssertEqual(notifyState.soundEffect, item.effect, item.notifyFixture)
        }
    }

    func testSoundEffectUnknownIDAndMalformedTruncatedEQ() throws {
        var unknownNotify = try qcyFixture("qcy-eq-notify-default")
        unknownNotify[4] = 0x07
        let packet = try XCTUnwrap(QCYPacket(data: Data(unknownNotify)))
        var state = QCYState()
        state.apply(packet)
        XCTAssertEqual(state.soundEffect, .unknown(0x07))
        XCTAssertEqual(state.soundEffect?.rawValue, 0x07)

        // Sem o byte do id (< 5 bytes) ou com tamanho de bloco incoerente é rejeitado.
        XCTAssertNil(QCYPacket(data: Data([0xFF, 0x91, 0x22, 0x8F])))
        XCTAssertNil(QCYPacket(data: Data([0xFF, 0x91, 0x22, 0x10, 0x01])))
    }

    // MARK: - Gestos (característica 000D)

    func testKeyMapDecodesMeasuredFixturesAndIgnoresUnusedKeyIDs() throws {
        var state = QCYState()
        state.applyKeyMap(Data(try qcyFixture("qcy-keymap-read")))
        XCTAssertEqual(state.keyMap, [
            .leftSingleTap: .nextTrack,
            .rightSingleTap: .playPause,
            .leftDoubleTap: .previousTrack,
            .rightDoubleTap: .volumeUp,
            .leftTripleTap: .ancMode,
            .rightTripleTap: .volumeDown
        ])

        state.applyKeyMap(Data(try qcyFixture("qcy-keymap-read-unassigned")))
        XCTAssertEqual(state.keyMap[.leftSingleTap], .unassigned)
        XCTAssertEqual(state.keyMap[.leftTripleTap], .ancMode)

        // Atualização parcial de 2 bytes é acumulativa.
        let writePair = try qcyFixture("qcy-keymap-write-left-triple-game")
        XCTAssertEqual(writePair, [QCYGesture.leftTripleTap.keyID, QCYKeyFunction.lowLatency.rawValue])
        state.applyKeyMap(Data(writePair))
        XCTAssertEqual(state.keyMap[.leftTripleTap], .lowLatency)
        XCTAssertEqual(state.keyMap[.rightTripleTap], .volumeDown)
    }

    func testGestureSideTapAndKeyIDMapping() {
        for gesture in QCYGesture.allCases {
            XCTAssertEqual(QCYGesture(side: gesture.side, tap: gesture.tap), gesture)
            XCTAssertEqual(QCYGesture(rawValue: gesture.keyID), gesture)
        }
        XCTAssertNil(QCYGesture(rawValue: 0x00))
        XCTAssertNil(QCYGesture(rawValue: 0x07))
        XCTAssertNil(QCYGesture(rawValue: 0x08))
    }

    // MARK: - Estado acumulativo

    func testStateAccumulatesAllNewFieldsWithoutOverwriting() throws {
        var state = QCYState()
        state.apply(try XCTUnwrap(QCYPacket(data: Data(try qcyFixture("qcy-anc-indoor")))))
        state.apply(try XCTUnwrap(QCYPacket(data: Data(try qcyFixture("qcy-balance-right")))))
        state.apply(try XCTUnwrap(QCYPacket(data: Data(try qcyFixture("qcy-poweroff-30m")))))
        state.apply(try XCTUnwrap(QCYPacket(data: Data(try qcyFixture("qcy-tone-volume-read-higher")))))
        state.apply(try XCTUnwrap(QCYPacket(data: Data(try qcyFixture("qcy-wear-detection-read")))))
        state.apply(try XCTUnwrap(QCYPacket(data: Data(try qcyFixture("qcy-eq-notify-pop")))))
        state.applyKeyMap(Data(try qcyFixture("qcy-keymap-read")))

        XCTAssertEqual(state.ancScene, .ancIndoor)
        XCTAssertEqual(state.balance, 0x5F)
        XCTAssertEqual(state.powerOff, .thirtyMinutes)
        XCTAssertEqual(state.toneVolume, .higher)
        XCTAssertEqual(state.wearDetection,
                       QCYWearDetection(isEnabled: true, musicControl: .pauseOnly, isANCSwitchEnabled: true))
        XCTAssertEqual(state.soundEffect, .pop)
        XCTAssertEqual(state.keyMap.count, 6)
    }
}
