# Dados — QCYKit

Status: aprovado em 2026-11-25

Sem persistência. O pacote não grava arquivo, banco nem preferência; o estado vive em memória no `QCYState` de quem consome.

- Dado pessoal: o MAC do fone passa pelo `QCYClient` em memória e não vai para log.
- Fixtures de teste (`Tests/QCYKitTests/Fixtures/qcy`) são frames medidos, sem identificador do usuário.
- Migração e retenção: N/A.
