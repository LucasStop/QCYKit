# API — QCYKit

Status: aprovado em 2026-11-25

Sem API de rede. O contrato é a API pública Swift do pacote, consumida pelo LogiBattery (só leitura) e pelo QCYBattery (leitura e escrita).

## Superfície pública
| Tipo | Uso |
|---|---|
| `QCYClient` | `start()`, `stop()`, `refresh()`, `send(_:)`, `refreshKeyMap()`, `setKeyFunction(_:for:)`; callbacks `onAdvertisement`, `onState`, `onReady`, `onDisconnect`, `onPacket`, `onFailure` |
| `QCYAdvertisement`, `QCYBatteryLevel` | bateria por lado no advertising (`percent`, carregando) |
| `QCYState` | estado acumulado (`left`, `right`, `caseBattery`, `firmware`, `noiseCancelMode`, `ancScene`, toggles, `balance`, `powerOff`, `toneVolume`, `wearDetection`, `soundEffect`, `keyMap`); `apply(_:)`, `applyKeyMap(_:)` |
| `QCYPacket`, `QCYCommand` | pacotes (`inEarDetection`, `lowLatency`, `noiseCancelMode`, `powerOff`, `balance`, `ancSetting`, `toneVolume`, `equalizer`, `ldac`, `wearDetection`, `battery`, `version`, `requestData`); fábricas `request`, `noiseCancelMode`, `ancSetting`, `ancNormal`, `ancAdaptive`, `ancIndoor`, `ancCommuting`, `transparencyVocal`, `transparency(level:)`, `setLDAC`, `setLowLatency`, `setInEarDetection`, `setBalance`, `setPowerOff`, `setToneVolume`, `setWearDetection`, `setSoundEffect` |
| `QCYNoiseCancelMode`, `QCYANScene`, `QCYFirmware` | modos, cenas nomeadas (`.normal`, `.ancAdaptive`, `.ancIndoor`, `.ancCommuting`, `.transparencyVocal`, `.transparency(level:)`) e versão |
| `QCYGesture`, `QCYKeyFunction` | gestos (`side`, `tap`, `keyID`) e funções da característica `000D` |
| `QCYSoundEffect`, `QCYToneVolume`, `QCYPowerOff`, `QCYWearDetection` | efeitos de EQ (4 medidos + `.unknown(UInt8)`), volume do bipe, desligamento automático e detecção de uso |

## Versionamento
- Tag semver. Remover ou mudar assinatura pública sobe MAJOR; tipo ou membro novo sobe MINOR; correção de parsing sobe PATCH.
- Bytes e offsets documentados em [QCY.md](QCY.md); mudança de protocolo atualiza os dois no mesmo PR.
