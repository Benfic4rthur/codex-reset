# Codex Reset

Monitor local para macOS integrado ao notch. À esquerda, um anel mostra a porcentagem restante da franquia semanal do Codex: o círculo começa cheio em 100% e diminui conforme a franquia é usada. À direita, aparecem o projeto, o modelo e o esforço da conversa ativa mais pesada. Sem conversas ativas, esse lado fica vazio. A seta aparece apenas quando há mais de uma conversa ativa e abre a lista das demais.

Ao passar o mouse pelo notch, uma extensão preta desce com uma animação curta e mostra o tempo até a renovação semanal da sua conta e uma estimativa de reset extra. O botão no canto fecha o monitor. Ele não ocupa a barra de menus nem o Dock.

## Instalação

Requisitos: macOS 14 ou mais recente, ChatGPT/Codex Desktop instalado e autenticado, e Xcode Command Line Tools ou Xcode.

```sh
./scripts/build-app.sh
./scripts/install-companion.sh
```

O primeiro script gera `.build/CodexReset.app`. O segundo instala o aplicativo em `~/Applications/Codex Reset.app` e um LaunchAgent que observa o ChatGPT/Codex Desktop: o monitor abre quando ele abre e fecha quando ele fecha. Se o ChatGPT já estiver aberto durante a instalação, o monitor abre na hora. Após usar o botão de desligar, você pode abrir o monitor novamente pelo aplicativo instalado. Ele também volta a abrir na próxima inicialização do ChatGPT.

## Origem dos dados

- **Franquia e renovação semanal:** vêm de `account/rateLimits/read` do Codex App Server. A porcentagem exibida é `100 − usedPercent` da janela semanal, atualizada a cada 30 segundos por uma conexão reutilizada.
- **Conversas ativas:** vêm das tabelas locais do Codex em `~/.codex`, lidas sem alterar o banco. O app mostra o nome do projeto, ou **Recentes** quando a conversa não pertence a um projeto, e atualiza a lista a cada 5 segundos. Ele não lê o conteúdo das mensagens.
- **Reset extra:** a estimativa usa o histórico do [codex-resets.com](https://codex-resets.com/), atualizado a cada 5 minutos. Quando há dados suficientes, mostra uma faixa provável e a frequência histórica de resets nos próximos sete dias. Anúncios verificáveis aparecem separados da estimativa.

O reset extra é uma **estimativa histórica, não uma garantia ou aviso antecipado da OpenAI**. A franquia real e a data de renovação pessoal vêm do Codex App Server. Conversas em outra máquina ou na nuvem não entram na lista local.
