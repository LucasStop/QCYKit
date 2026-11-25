# QCYKit

Contexto do repo para a CLI de IA. Regras globais em `~/.claude/CLAUDE.md` valem; aqui só o específico. `CLAUDE.md`, `AGENTS.md` e `GEMINI.md` são o mesmo arquivo (symlinks).

## O que é
Pacote Swift (SwiftPM, macOS 14+) com o protocolo BLE proprietário do fone QCY MeloBuds Pro: advertising `0x521C`, framing do canal `A001`, estado acumulado e cliente CoreBluetooth. Consumido por [LogiBattery](https://github.com/LucasStop/LogiBattery) (só leitura de L/R) e [QCYBattery](https://github.com/LucasStop/QCYBattery) (leitura e escrita de ANC, LDAC e modo jogo). Referência medida: [docs/QCY.md](docs/QCY.md).

## Comandos
- Testes: `swift test` (sem hardware; fixtures de bytes reais em `Tests/QCYKitTests/Fixtures/qcy/`)
- Lint: `swiftlint --strict`
- Sonda no fone: `tools/qcyctl/run.sh --seconds 12` (somente leitura por padrão; roda num `.app` ad-hoc porque o TCC aborta binário de CLI). Gravação de fixture: ver `docs/QCY.md`.

## Convenções
- Swift 6, sem dependências além de Foundation e CoreBluetooth. Nada de `Device` nem UI aqui: o adaptador para o domínio de cada app mora no app.
- API pública mínima: só fica `public` o que algum app usa.
- Parser novo ou byte novo entra com fixture gravada pelo `qcyctl` e teste em `QCYProtocolTests`.
- Escrita no fone não roda em teste nem em CI; só à mão, com o Lucas presente e o estado restaurado.

## Versão
Tag semver (`vX.Y.Z`) na `main` depois do merge; os apps dependem com `from:`. Mudança que quebra API pública sobe MAJOR (ou MINOR enquanto `0.x`). Sem script de release: `git tag vX.Y.Z && git push origin vX.Y.Z` e `gh release create vX.Y.Z --generate-notes`.
