# Design — QCYKit

Status: aprovado em 2026-11-25

Pacote sem UI. Tokens visuais e telas vivem nos apps: [LogiBattery](https://github.com/LucasStop/LogiBattery/blob/main/DESIGN.md) e [QCYBattery](https://github.com/LucasStop/QCYBattery/blob/main/DESIGN.md).

## Convenções da API pública
- Prefixo `QCY` em todo tipo público.
- Valor ausente é `nil`, nunca 0 (bateria sem leitura não vira 0%).
- Tipos de valor `Sendable` e `Equatable`; callbacks do cliente `@Sendable`.
