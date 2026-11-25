# Testes — QCYKit

Status: rascunho, aguardando aprovação do Lucas

| Parte | Risco | Nível | Onde | Quando |
|---|---|---|---|---|
| Advertising, pacote, estado | Byte mal lido, comando trocado (regressão `0x0C`/`0x17`) | unitário com frames reais | `Tests/QCYKitTests/QCYProtocolTests.swift`, fixtures em `Tests/QCYKitTests/Fixtures/qcy` | local, PR |
| Cliente BLE | Permissão, GATT, escrita | smoke manual | `tools/qcyctl/run.sh --seconds 12` | à mão, com o Lucas presente |
| Estilo | Código fora do padrão | estático | `swiftlint --strict` | pre-commit, PR |

- Rodar: `xcrun swift test` (o `swift` do swiftly no PATH é 5.6).
- CoreBluetooth não entra no CI.
