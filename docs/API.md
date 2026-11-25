# API — QCYKit

Status: rascunho, aguardando aprovação do Lucas

Sem API de rede. O contrato é a API pública Swift do pacote, consumida pelo LogiBattery (só leitura) e pelo QCYBattery (leitura e escrita).

## Superfície pública
| Tipo | Uso |
|---|---|
| `QCYClient` | `start()`, `stop()`, `refresh()`, `send(_:)`; callbacks `onAdvertisement`, `onState`, `onReady`, `onDisconnect`, `onPacket`, `onFailure` |
| `QCYAdvertisement`, `QCYBatteryLevel` | bateria por lado no advertising (`percent`, carregando) |
| `QCYState` | estado acumulado; `apply(_:)` |
| `QCYPacket`, `QCYCommand` | pacotes; fábricas `request`, `ancSetting`, `noiseCancelMode`, `setLDAC`, `setLowLatency`, `setInEarDetection` |
| `QCYNoiseCancelMode`, `QCYANScene`, `QCYFirmware` | valores do estado |

## Versionamento
- Tag semver. Remover ou mudar assinatura pública sobe MAJOR; tipo ou membro novo sobe MINOR; correção de parsing sobe PATCH.
- Bytes e offsets documentados em [QCY.md](QCY.md); mudança de protocolo atualiza os dois no mesmo PR.
