# QCYKit

Protocolo BLE do fone QCY MeloBuds Pro em Swift: bateria por lado (advertising e GATT), firmware, cena de ANC, LDAC e modo jogo. Medido em hardware real; detalhes em [docs/QCY.md](docs/QCY.md).

```swift
// Package.swift ou project.yml (XcodeGen)
.package(url: "https://github.com/LucasStop/QCYKit", from: "0.1.0")
```

```swift
import QCYKit

let client = QCYClient()
client.onState = { state in print(state.left?.percent ?? -1, state.right?.percent ?? -1) }
client.start()
```

Usado por [LogiBattery](https://github.com/LucasStop/LogiBattery) e [QCYBattery](https://github.com/LucasStop/QCYBattery).

| Doc | Conteúdo |
|---|---|
| [docs/QCY.md](docs/QCY.md) | Protocolo medido, offsets, comandos e limites |
| [docs/adr/](docs/adr) | Decisões |

`swift test` roda sem hardware. Licença MIT.
