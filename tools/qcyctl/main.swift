// Sonda do fone QCY: lê advertising, bateria, versão e estado; tem modos somente leitura para sondar
// propriedades, teclas, EQ, notificações de 1002 e eventos de mídia do macOS, e só escreve quando um flag
// de escrita é pedido explicitamente (nunca combinado com modos de sonda).
// Roda dentro de um .app assinado por tools/qcyctl/run.sh — sem bundle o TCC aborta o processo por falta de
// NSBluetoothAlwaysUsageDescription. Não loga série; nos modos de sonda não loga MAC nem nome.
//
// Uso: tools/qcyctl/run.sh [--seconds 8] [--verbose] [--log caminho]
//   Sondas somente leitura (não escrevem no fone):
//     --request 0x16,0x14,...    pede leitura (0xFE) de cada ID em hex e imprime id=0x.. len=N hex=..
//     --dump-keys                lê 0x0D (GATT 000D + canal 0xFE) e imprime pares keyId->funId em hex
//     --dump-eq                  lê 0x0B (GATT 000B + canal 0xFE) e 0x20/0x22 e imprime hex cru
//     --listen-notify            assina notificações de 1002 e imprime cada pacote com timestamp (ms)
//     --media-events             escuta MPRemoteCommandCenter e NSEvent (.systemDefined) com timestamp (ms)
//   Escrita explícita (incompatível com as sondas acima):
//     --anc off|anc|outdoor|transparency
//     --scene MM/SS/NV           em hex
//     --low-latency on|off
//     --ldac on|off
//   Escrita protegida de teclas em 000D (exige --yes-write; sem ele mostra o plano e sai com 64;
//   nunca imprime MAC, nome ou série):
//     --set-key 0x07=0x03[,0x08=0x04] --yes-write   salva backup em $TMPDIR/qcy-keys-original.hex, escreve e relê
//     --restore-keys --yes-write                    restaura $TMPDIR/qcy-keys-original.hex em 000D e relê
import AppKit
import ApplicationServices
import CoreBluetooth
import Foundation
import MediaPlayer

final class Tool: @unchecked Sendable {
    private enum KeyWritePhase {
        case idle
        case waitingInitialRead
        case waitingVerify(before: [UInt8]?, expected: [UInt8])
        case done
    }

    private let logURL: URL?
    private let logLock = NSLock()
    private let stateLock = NSLock()
    private let seconds: TimeInterval
    private let writePacket: QCYPacket?
    private let verbose: Bool
    private let requestIDs: [UInt8]
    private let dumpKeys: Bool
    private let dumpEQ: Bool
    private let listenNotify: Bool
    private let mediaEvents: Bool
    private let keyChanges: [(UInt8, UInt8)]
    private let restoreKeys: Bool
    private let yesWrite: Bool
    private let backupURL: URL
    private var restorePayload: [UInt8]?
    private var keyWritePhase: KeyWritePhase = .idle
    private let client = QCYClient()
    private let startUptime = ProcessInfo.processInfo.systemUptime
    private let requestQueue = DispatchQueue(label: "com.lucasstop.QCYCTL.requests")

    private var isReadOnlyProbe: Bool {
        !requestIDs.isEmpty || dumpKeys || dumpEQ || listenNotify || mediaEvents
    }

    private var isKeyWriteMode: Bool {
        !keyChanges.isEmpty || restoreKeys
    }

    private var needsBluetooth: Bool {
        !mediaEvents || !requestIDs.isEmpty || dumpKeys || dumpEQ || listenNotify
            || writePacket != nil || isKeyWriteMode
    }

    init(arguments: [String]) {
        var logPath: String?
        var seconds: TimeInterval = 8
        var blocks: [QCYPacket.Block] = []
        var verbose = false
        var requestIDs: [UInt8] = []
        var dumpKeys = false
        var dumpEQ = false
        var listenNotify = false
        var mediaEvents = false
        var keyChanges: [(UInt8, UInt8)] = []
        var restoreKeys = false
        var yesWrite = false
        var index = 0
        func value(_ flag: String) -> String {
            guard index < arguments.count else {
                print("falta valor para \(flag)")
                exit(64)
            }
            return arguments[index]
        }
        while index < arguments.count {
            let flag = arguments[index]
            switch flag {
            case "--log":
                index += 1
                logPath = index < arguments.count ? arguments[index] : nil
            case "--seconds":
                index += 1
                seconds = TimeInterval(index < arguments.count ? arguments[index] : "") ?? seconds
            case "--request":
                index += 1
                guard let parsed = QCYProbeFormat.parseIDList(value(flag)) else {
                    print("lista de IDs inválida para --request (use hex separado por vírgula, ex: 0x16,0x14)")
                    exit(64)
                }
                requestIDs.append(contentsOf: parsed)
            case "--dump-keys":
                dumpKeys = true
            case "--dump-eq":
                dumpEQ = true
            case "--listen-notify":
                listenNotify = true
            case "--media-events":
                mediaEvents = true
            case "--set-key":
                index += 1
                guard let parsed = QCYProbeFormat.parseKeyChanges(value(flag)),
                      parsed.allSatisfy({ $0.0 != 0x00 && $0.1 <= QCYProbeFormat.maxKeyFunctionID }) else {
                    print("pares inválidos para --set-key (use hex keyId=funId com keyId!=0x00 e funId<=0x0B, ex: 0x07=0x03)")
                    exit(64)
                }
                keyChanges.append(contentsOf: parsed)
            case "--restore-keys":
                restoreKeys = true
            case "--yes-write":
                yesWrite = true
            case "--anc":
                index += 1
                let modes: [String: UInt8] = ["off": 0x00, "anc": 0x01, "outdoor": 0x02, "transparency": 0x03]
                guard let mode = modes[value(flag)] else { exit(64) }
                blocks += QCYPacket.noiseCancelMode(mode).blocks
            case "--scene":
                index += 1
                guard let scene = Self.scene(value(flag)) else { exit(64) }
                blocks += QCYPacket.ancSetting(mode: scene.mode,
                                               subScene: scene.subScene,
                                               noiseValue: scene.noiseValue).blocks
            case "--low-latency":
                index += 1
                guard let enabled = Self.toggle(value(flag)) else { exit(64) }
                blocks += QCYPacket.setLowLatency(enabled).blocks
            case "--ldac":
                index += 1
                guard let enabled = Self.toggle(value(flag)) else { exit(64) }
                blocks += QCYPacket.setLDAC(enabled).blocks
            case "--verbose":
                verbose = true
            default:
                print("argumento desconhecido: \(flag)")
                exit(64)
            }
            index += 1
        }

        let probeSelected = !requestIDs.isEmpty || dumpKeys || dumpEQ || listenNotify || mediaEvents
        let keyWriteSelected = !keyChanges.isEmpty || restoreKeys
        if probeSelected && (!blocks.isEmpty || keyWriteSelected) {
            print("erro: flags de escrita não podem ser combinadas com modos de sonda somente leitura")
            exit(64)
        }
        if !keyChanges.isEmpty && restoreKeys {
            print("erro: --set-key e --restore-keys não podem ser usados juntos")
            exit(64)
        }
        if keyWriteSelected && !blocks.isEmpty {
            print("erro: --set-key/--restore-keys não podem ser combinados com outras escritas")
            exit(64)
        }

        self.logURL = logPath.map { URL(fileURLWithPath: $0) }
        self.seconds = seconds
        self.writePacket = blocks.isEmpty ? nil : QCYPacket(blocks)
        self.verbose = verbose
        self.requestIDs = requestIDs
        self.dumpKeys = dumpKeys
        self.dumpEQ = dumpEQ
        self.listenNotify = listenNotify
        self.mediaEvents = mediaEvents
        self.keyChanges = keyChanges
        self.restoreKeys = restoreKeys
        self.yesWrite = yesWrite
        self.backupURL = Self.defaultKeyBackupURL()
    }

    private static func defaultKeyBackupURL() -> URL {
        let dir: URL
        if let envTmp = ProcessInfo.processInfo.environment["TMPDIR"], !envTmp.isEmpty {
            dir = URL(fileURLWithPath: envTmp, isDirectory: true)
        } else {
            dir = FileManager.default.temporaryDirectory
        }
        return dir.appendingPathComponent("qcy-keys-original.hex")
    }

    /// `MM/SS/NV` em hexadecimal, como o fone devolve em `0x17`.
    private static func scene(_ text: String) -> (mode: UInt8, subScene: UInt8, noiseValue: UInt8)? {
        let parts = text.split(separator: "/")
        guard parts.count == 3,
              let mode = UInt8(parts[0], radix: 16),
              let subScene = UInt8(parts[1], radix: 16),
              let noiseValue = UInt8(parts[2], radix: 16) else { return nil }
        return (mode, subScene, noiseValue)
    }

    private static func toggle(_ text: String) -> Bool? {
        switch text {
        case "on", "1", "true": return true
        case "off", "0", "false": return false
        default: return nil
        }
    }

    func run() {
        if isKeyWriteMode {
            prepareKeyWriteOrExit()
        }

        if needsBluetooth {
            configureBluetooth()
            client.start()
        }

        if mediaEvents {
            MainActor.assumeIsolated { runWithMediaEvents() }
        } else {
            RunLoop.current.run(until: Date().addingTimeInterval(seconds))
        }

        if isKeyWriteMode {
            let unfinished: Bool = stateLock.withLock {
                if case .done = keyWritePhase { return false }
                return true
            }
            if unfinished {
                log("aviso: operacao em 000D nao completou dentro de \(Int(seconds))s")
            }
        }

        if needsBluetooth {
            client.stop()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        log("fim")
    }

    private func prepareKeyWriteOrExit() {
        if !yesWrite {
            if !keyChanges.isEmpty {
                let summary = keyChanges
                    .map { String(format: "0x%02X->0x%02X", $0.0, $0.1) }
                    .joined(separator: " ")
                log("dry-run (--yes-write ausente): nada foi escrito no fone.")
                log("plano: conectar ao QCY, ler 000D, salvar backup em \(backupURL.path) (se ainda nao existir), "
                    + "aplicar \(summary), escrever 000D, aguardar 1s e reler 000D para confirmar.")
                log("para executar de verdade, repita o comando com --yes-write.")
            } else {
                log("dry-run (--yes-write ausente): nada foi escrito no fone.")
                log("plano: ler backup em \(backupURL.path), conectar ao QCY, escrever em 000D, "
                    + "aguardar 1s e reler 000D para confirmar.")
                log("para executar de verdade, repita o comando com --yes-write.")
            }
            exit(64)
        }

        if restoreKeys {
            guard let text = try? String(contentsOf: backupURL, encoding: .utf8),
                  let bytes = QCYProbeFormat.parseHexBytes(text),
                  bytes.count <= QCYProbeFormat.maxKeyPayloadLength,
                  bytes.count.isMultiple(of: 2) else {
                log("erro: backup ausente ou invalido em \(backupURL.path)")
                exit(64)
            }
            restorePayload = bytes
        }
    }

    private func configureBluetooth() {
        let watchedIDs = Set(allProbeRequestIDs())

        if isReadOnlyProbe {
            log("conectando ao QCY em modo somente leitura…")
        } else if isKeyWriteMode {
            log("conectando ao QCY para operacao protegida em 000D…")
        } else {
            log("procurando QCY por manufacturer data 0x521C…")
            client.onAdvertisement = { [weak self] advertisement in
                self?.log("advertising: vendor=\(String(format: "0x%04X", advertisement.vendorID)) "
                          + "L=\(advertisement.left.percent)%\(advertisement.left.isCharging ? " (carregando)" : "") "
                          + "R=\(advertisement.right.percent)%\(advertisement.right.isCharging ? " (carregando)" : "") "
                          + "estojo=\(advertisement.caseBattery.map { "\($0.percent)%" } ?? "-") "
                          + "control=\(advertisement.controlMAC ?? "-") outr=\(advertisement.otherMAC ?? "-")")
            }
            client.onState = { [weak self] state in
                self?.log(Self.describe(state))
            }
        }

        client.onCharacteristicValue = { [weak self] uuid, data in
            guard let self else { return }
            let upper = uuid.uppercased()
            let bytes = Array(data)
            if self.isKeyWriteMode && (upper == "000D" || upper.hasPrefix("0000000D-")) {
                self.handleKeyCharacteristicRead(bytes)
                return
            }
            if self.dumpKeys && (upper == "000D" || upper.hasPrefix("0000000D-")) {
                let pairs = QCYProbeFormat.formatKeyPairs(bytes)
                self.log("gatt=000D \(QCYProbeFormat.formatReply(id: 0x0D, payload: bytes))")
                self.log("keys(gatt 000D): \(pairs.isEmpty ? "(vazio)" : pairs)")
            }
            if self.dumpEQ && (upper == "000B" || upper.hasPrefix("0000000B-")) {
                self.log("gatt=000B len=\(bytes.count) hex=\(QCYProbeFormat.hex(bytes))")
            }
        }

        client.onPacket = { [weak self] data in
            guard let self else { return }
            let bytes = Array(data)
            if self.verbose && !self.listenNotify {
                self.log("rx \(QCYProbeFormat.hex(bytes))")
            }
            if self.listenNotify {
                let ms = self.elapsedMilliseconds()
                var line = "[+\(ms)ms] len=\(bytes.count) hex=\(QCYProbeFormat.hex(bytes))"
                if let packet = QCYPacket(data: data), !packet.blocks.isEmpty {
                    let blocks = packet.blocks
                        .map { QCYProbeFormat.formatReply(id: $0.command, payload: $0.parameters) }
                        .joined(separator: "; ")
                    line += " (\(blocks))"
                }
                self.log(line)
            }
            if !watchedIDs.isEmpty, let packet = QCYPacket(data: data) {
                for block in packet.blocks where watchedIDs.contains(block.command) {
                    self.log(QCYProbeFormat.formatReply(id: block.command, payload: block.parameters))
                    if self.dumpKeys && block.command == 0x0D {
                        let pairs = QCYProbeFormat.formatKeyPairs(block.parameters)
                        self.log("keys(cmd 0x0D): \(pairs.isEmpty ? "(vazio)" : pairs)")
                    }
                }
            }
        }

        client.onReady = { [weak self] in
            guard let self else { return }
            if self.listenNotify {
                self.log("[+\(self.elapsedMilliseconds())ms] pronto: ouvindo notificacoes de 1002 por \(Int(self.seconds))s")
            }
            if self.isReadOnlyProbe {
                self.sendProbeReads()
                return
            }
            if self.isKeyWriteMode {
                self.beginKeyWriteOnReady()
                return
            }
            guard let writePacket else { return }
            self.log("escrevendo \(QCYProbeFormat.hex(Array(writePacket.encoded())))")
            self.client.send(writePacket)
        }

        client.onFailure = { [weak self] message in
            self?.log("falha: \(message)")
        }
    }

    private func beginKeyWriteOnReady() {
        if !keyChanges.isEmpty {
            let shouldStart: Bool = stateLock.withLock {
                guard case .idle = keyWritePhase else { return false }
                keyWritePhase = .waitingInitialRead
                return true
            }
            guard shouldStart else { return }
            log("lendo 000D antes da alteracao…")
            client.readCharacteristic("000D")
        } else if let payload = restorePayload {
            let shouldStart: Bool = stateLock.withLock {
                guard case .idle = keyWritePhase else { return false }
                keyWritePhase = .waitingVerify(before: nil, expected: payload)
                return true
            }
            guard shouldStart else { return }
            log("restaurando 000D de \(backupURL.path): hex=\(QCYProbeFormat.hex(payload)) "
                + "(\(QCYProbeFormat.formatKeyPairs(payload)))")
            client.writeCharacteristic("000D", data: Data(payload))
            requestQueue.asyncAfter(deadline: .now() + .seconds(1)) { [weak self] in
                self?.client.readCharacteristic("000D")
            }
        }
    }

    private func handleKeyCharacteristicRead(_ bytes: [UInt8]) {
        let phase: KeyWritePhase = stateLock.withLock { keyWritePhase }
        switch phase {
        case .waitingInitialRead:
            saveBackupIfMissing(bytes)
            log("original (000D): len=\(bytes.count) hex=\(QCYProbeFormat.hex(bytes)) "
                + "(\(QCYProbeFormat.formatKeyPairs(bytes)))")
            guard let updated = QCYProbeFormat.applyPairs(original: bytes, changes: keyChanges) else {
                stateLock.withLock { keyWritePhase = .done }
                log("erro: nao foi possivel aplicar pares sobre o payload lido de 000D (nada escrito)")
                return
            }
            stateLock.withLock { keyWritePhase = .waitingVerify(before: bytes, expected: updated) }
            log("escrevendo (000D): len=\(updated.count) hex=\(QCYProbeFormat.hex(updated)) "
                + "(\(QCYProbeFormat.formatKeyPairs(updated)))")
            client.writeCharacteristic("000D", data: Data(updated))
            requestQueue.asyncAfter(deadline: .now() + .seconds(1)) { [weak self] in
                self?.client.readCharacteristic("000D")
            }
        case .waitingVerify(let before, let expected):
            stateLock.withLock { keyWritePhase = .done }
            if let before {
                log("antes   (000D): hex=\(QCYProbeFormat.hex(before)) (\(QCYProbeFormat.formatKeyPairs(before)))")
            }
            log("escrito (000D): hex=\(QCYProbeFormat.hex(expected)) (\(QCYProbeFormat.formatKeyPairs(expected)))")
            log("depois  (000D): hex=\(QCYProbeFormat.hex(bytes)) (\(QCYProbeFormat.formatKeyPairs(bytes)))")
            let matched = bytes == expected
            log("confirmacao releitura: \(matched ? "OK (bate com o escrito)" : "DIVERGENTE (nao confiar na escrita)")")
        case .idle, .done:
            break
        }
    }

    private func saveBackupIfMissing(_ bytes: [UInt8]) {
        if FileManager.default.fileExists(atPath: backupURL.path) {
            log("backup original preservado em \(backupURL.path) (ja existia, nao sobrescrito)")
            return
        }
        guard let data = (QCYProbeFormat.hex(bytes) + "\n").data(using: .utf8) else { return }
        do {
            try data.write(to: backupURL, options: .withoutOverwriting)
            log("backup original salvo em \(backupURL.path)")
        } catch {
            log("aviso: nao foi possivel salvar backup em \(backupURL.path): \(error.localizedDescription)")
        }
    }

    private func allProbeRequestIDs() -> [UInt8] {
        var ids: [UInt8] = []
        var seen = Set<UInt8>()
        func appendUnique(_ id: UInt8) {
            if seen.insert(id).inserted { ids.append(id) }
        }
        for id in requestIDs { appendUnique(id) }
        if dumpKeys { appendUnique(0x0D) }
        if dumpEQ {
            appendUnique(0x0B)
            appendUnique(0x20)
            appendUnique(0x22)
        }
        return ids
    }

    /// Dispara apenas leituras (GATT read + pacotes `0xFE`) para os modos de sonda.
    private func sendProbeReads() {
        if dumpKeys {
            client.readCharacteristic("000D")
        }
        if dumpEQ {
            client.readCharacteristic("000B")
        }
        let ids = allProbeRequestIDs()
        for (offset, id) in ids.enumerated() {
            let delay = DispatchTimeInterval.milliseconds(offset * 80)
            requestQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.client.send(QCYProbeFormat.requestPacket(for: id))
            }
        }
    }

    @MainActor
    private func runWithMediaEvents() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        if !AXIsProcessTrusted() {
            log("aviso: Acessibilidade nao autorizada para QCYCTL; o monitor global NSEvent (.systemDefined) "
                + "pode nao receber eventos ate autorizar em Ajustes do Sistema > Privacidade e Seguranca > Acessibilidade.")
        }

        let monitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            guard let self else { return }
            guard let description = QCYProbeFormat.describeSystemDefinedEvent(
                subtype: Int(event.subtype.rawValue),
                data1: event.data1
            ) else { return }
            self.log("[+\(self.elapsedMilliseconds())ms] nsevent: \(description)")
        }
        if monitor == nil {
            log("aviso: NSEvent.addGlobalMonitorForEvents retornou nil (permissao de Acessibilidade/Monitoramento de Entrada ausente).")
        }

        let center = MPRemoteCommandCenter.shared()
        let commands: [(String, MPRemoteCommand)] = [
            ("play", center.playCommand),
            ("pause", center.pauseCommand),
            ("togglePlayPause", center.togglePlayPauseCommand),
            ("nextTrack", center.nextTrackCommand),
            ("previousTrack", center.previousTrackCommand)
        ]
        var targets: [(MPRemoteCommand, Any)] = []
        for (name, command) in commands {
            command.isEnabled = true
            let token = command.addTarget { [weak self] _ in
                guard let self else { return .commandFailed }
                self.log("[+\(self.elapsedMilliseconds())ms] remote-command: \(name)")
                return .success
            }
            targets.append((command, token))
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "QCYCTL Media Probe"
        ]
        MPNowPlayingInfoCenter.default().playbackState = .playing

        log("[+\(elapsedMilliseconds())ms] ouvindo eventos de midia por \(Int(seconds))s…")

        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            if let monitor { NSEvent.removeMonitor(monitor) }
            for (command, token) in targets {
                command.removeTarget(token)
                command.isEnabled = false
            }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState = .stopped
            app.stop(nil)
            if let wakeup = NSEvent.otherEvent(
                with: .applicationDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 0,
                data1: 0,
                data2: 0
            ) {
                app.postEvent(wakeup, atStart: true)
            }
        }

        app.run()
    }

    private func elapsedMilliseconds() -> Int {
        Int(((ProcessInfo.processInfo.systemUptime - startUptime) * 1000).rounded())
    }

    private static func describe(_ state: QCYState) -> String {
        var parts: [String] = []
        if let left = state.left, let right = state.right {
            parts.append("bateria L=\(left.percent)%\(left.isCharging ? "+" : "") "
                         + "R=\(right.percent)%\(right.isCharging ? "+" : "") "
                         + "estojo=\(state.caseBattery.map { "\($0.percent)%\($0.isCharging ? "+" : "")" } ?? "-")")
        }
        if let firmware = state.firmware {
            parts.append("firmware \(firmware.left)\(firmware.right.map { " / \($0)" } ?? "")")
        }
        if let mode = state.noiseCancelMode { parts.append("anc \(mode.name)") }
        if let scene = state.ancScene { parts.append("cena \(scene.name)") }
        if let lowLatency = state.isLowLatencyEnabled { parts.append("jogo \(lowLatency ? "on" : "off")") }
        if let ldac = state.isLDACEnabled { parts.append("ldac \(ldac ? "on" : "off")") }
        if let inEar = state.isInEarDetectionEnabled { parts.append("deteccao de ouvido \(inEar ? "on" : "off")") }
        return parts.isEmpty ? "estado sem blocos conhecidos" : parts.joined(separator: " · ")
    }

    private func log(_ text: String) {
        logLock.lock()
        defer { logLock.unlock() }
        print(text)
        guard let logURL, let data = (text + "\n").data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        }
    }
}

Tool(arguments: Array(CommandLine.arguments.dropFirst())).run()
