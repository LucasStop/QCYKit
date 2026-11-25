# PRD — QCYKit

## Problema
Dois apps (LogiBattery e QCYBattery) leem o fone QCY MeloBuds Pro por BLE. Com o protocolo copiado em cada um, correção de byte num lado não chega no outro.

## Histórias
| ID | História | Critério de aceite |
|---|---|---|
| US-01 | Como app consumidor, quero a bateria por lado a partir do advertising, sem conectar | Dado um advertising com company id `0x521C`, quando `QCYAdvertisement` lê os bytes 5–7, então devolve L, R e estojo; `0x00` ou fora de faixa vira `nil`, nunca 0% |
| US-02 | Como app consumidor, quero o estado completo pelo canal GATT `A001` | Dado o `QCYClient` conectado, quando chegam pacotes, então `QCYState` acumula bateria, firmware, modo e cena de ANC, LDAC, modo jogo e detecção de ouvido |
| US-03 | Como QCYBattery, quero escrever cena de ANC, LDAC e modo jogo | Dado o `QCYClient` pronto, quando envio `QCYPacket.ancSetting`, `setLDAC` ou `setLowLatency`, então o pacote sai codificado como medido em `docs/QCY.md` |

## Fora de escopo
- Modo simples `0x0C`: não responde no MeloBuds Pro.
- Outros modelos QCY sem medição em hardware.
