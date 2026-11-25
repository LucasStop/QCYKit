# Arquitetura — QCYKit

Status: rascunho, aguardando aprovação do Lucas

Pacote SwiftPM (`swift-tools-version` 6.0, macOS 14), uma library `QCYKit`, sem dependência externa. Protocolo medido em [QCY.md](QCY.md).

| Parte | Faz | Código |
|---|---|---|
| Advertising | Lê bateria L/R/estojo do manufacturer data `0x521C` | `Sources/QCYKit/QCYAdvertisement.swift` |
| Pacote | Codifica e decodifica blocos `comando + parâmetros` | `Sources/QCYKit/QCYPacket.swift` |
| Estado | Acumula o que os pacotes dizem (`QCYState.apply`) | `Sources/QCYKit/QCYState.swift` |
| Cliente BLE | CoreBluetooth: varre, conecta, assina `A001`, envia e repassa por callbacks | `Sources/QCYKit/QCYClient.swift` |

## Decisões
- Repo próprio desde 2026-11-25 (ADR 0008 do LogiBattery): SwiftPM remoto exige `Package.swift` na raiz.
- Parsing puro (advertising, pacote, estado) separado do `QCYClient`: testável sem hardware.
- Versão só por tag semver; consumidores usam `from:`. Mudança que quebra API pública sobe MAJOR.
- ADRs em [adr/](adr/).
