<p align="center">
  <img src="Assets/CodexReset.png" width="112" alt="Ícone do Codex Reset">
</p>

# Codex Reset

Sua franquia do Codex sempre à vista. Um monitor nativo para macOS que mostra a porcentagem semanal restante, as conversas ativas e o tempo até a próxima renovação.

## Downloads

| Apple Silicon · M1, M2, M3 e posteriores | Intel · x86_64 |
| :---: | :---: |
| **[⬇ Baixar para Apple Silicon](https://github.com/Benfic4rthur/codex-reset/releases/latest/download/Codex-Reset-Apple-Silicon.dmg)** | **[⬇ Baixar para Intel](https://github.com/Benfic4rthur/codex-reset/releases/latest/download/Codex-Reset-Intel.dmg)** |
| Com notch: visual integrado ao recorte. Sem notch, incluindo M1: cápsula no topo | Cápsula compacta dentro da barra de menus |

### Depois de instalar: liberar no Terminal

**Após copiar o app para Aplicativos, execute o bloco abaixo no Terminal antes de abrir o Codex Reset.** Esta versão ainda não possui assinatura Developer ID nem notarização da Apple; o macOS pode bloquear a abertura até você autorizar o aplicativo.

O comando encontra o app em **Aplicativos do sistema** ou **Aplicativos do seu usuário** e remove somente a marca de quarentena do Codex Reset:

```sh
if [ -d "/Applications/Codex Reset.app" ]; then
  xattr -dr com.apple.quarantine "/Applications/Codex Reset.app"
elif [ -d "$HOME/Applications/Codex Reset.app" ]; then
  xattr -dr com.apple.quarantine "$HOME/Applications/Codex Reset.app"
else
  echo "Copie primeiro o Codex Reset.app do DMG para a pasta Aplicativos."
fi
```

Depois, abra o **Codex Reset** e o **Codex Desktop**. Repita essa etapa ao instalar uma nova versão baixada. Se aparecer um erro de permissão, confira se você tem permissão para alterar a cópia instalada. Veja também as [orientações da Apple para autorizar aplicativos](https://support.apple.com/102445).

Os links sempre apontam para a versão mais recente. Veja as novidades e os downloads anteriores em [Releases](https://github.com/Benfic4rthur/codex-reset/releases). Cada versão inclui os hashes SHA-256 dos DMGs.

**Requisitos:** macOS 14 ou mais recente e Codex Desktop instalado e autenticado na conta de quem vai usar o monitor. O Codex Desktop precisa ser compatível com o Mac. O monitor é um projeto independente, sem vínculo oficial com a OpenAI.

### Como instalar

1. Baixe o DMG correspondente ao processador do seu Mac.
2. Abra o DMG e arraste **Codex Reset.app** para **Aplicativos**.
3. Execute no Terminal o [comando de liberação acima](#depois-de-instalar-liberar-no-terminal).
4. Abra o Codex Reset uma vez. Ele configura o início automático para seu usuário.
5. Abra o Codex Desktop. O monitor aparece enquanto ele estiver aberto.

Para atualizar, feche o Codex Reset pelo botão de desligar que aparece ao passar o mouse, substitua o aplicativo e abra a nova versão. As atualizações são baixadas manualmente pelo GitHub.

## Como funciona

- **Franquia:** anel com a porcentagem restante da janela semanal. Atualiza a cada 30 segundos usando uma conexão local reutilizada com o Codex App Server.
- **Atividade:** projeto, modelo e esforço da conversa ativa mais pesada. Sem atividade, aparece apenas a franquia. A seta aparece quando há mais de uma conversa ativa. A lista atualiza a cada 5 segundos.
- **Renovação semanal:** ao passar o mouse, aparece uma contagem regressiva até a renovação informada pela conta. Mostra dias e horas (por exemplo, `6d 18h`); quando falta menos de um dia, mostra horas e minutos (por exemplo, `18h 30m`). A tela atualiza a cada minuto.
- **Reset extra:** janela histórica baseada em [codex-resets.com](https://codex-resets.com/), com datas estimadas de início e fim ancoradas no último reset observado. A faixa aparece em linguagem direta, como “Entre 1d 14h e 3d 19h”, com a indicação “Estimativa histórica”. Abaixo de um dia, usa horas e minutos. Dentro da janela, mostra “Dentro da janela” e o tempo estimado restante; a tela atualiza a cada minuto. O histórico é consultado a cada 5 minutos; consultar os mesmos dados não reinicia o prazo. Quando a janela termina, aparece “Janela encerrada”, aguardando novos dados. Não representa uma promessa nem um aviso antecipado da OpenAI.

Nos MacBooks Intel e nos M1 sem notch, a cápsula compacta fica centralizada e inteira dentro da altura da barra de menus. A porcentagem aparece em texto grande, com uma barra horizontal de progresso separada; não há círculo em volta do número. Com atividade, projeto, modelo e esforço aparecem em uma linha legível. A altura ocupa a barra real da tela, deixando apenas uma pequena margem para manter o contorno arredondado visível. Ela ocupa apenas o espaço da franquia quando não há atividade e cresce na horizontal quando há conversas. Os detalhes se abrem ao passar o mouse. Nos Macs com notch, o visual continua integrado ao recorte; a lateral de projeto, modelo e esforço ajusta a largura ao conteúdo e só reserva espaço para a seta quando ela aparece. O aplicativo detecta o tipo de tela automaticamente. A altura é medida pela área que o macOS reserva no topo da tela, com `NSScreen.frame` e [`NSScreen.visibleFrame`](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe); se a barra estiver oculta, usa `NSStatusBar.system.thickness`. A medida é conferida novamente enquanto o app está aberto. Não depende de uma altura fixa atribuída ao MacBook Pro 2019, ao M1 Air ou a uma arquitetura.

## Privacidade

**Cada instalação usa a conta local de quem instalou o app.** Os DMGs contêm somente o aplicativo, seu ícone e as instruções de instalação.

- Nenhuma chave de API, senha, sessão, conversa ou configuração do desenvolvedor é incluída nos downloads.
- O monitor consulta a franquia pelo Codex instalado no próprio Mac. Não exige uma chave de API separada.
- A lista de conversas usa apenas metadados do histórico local, em modo de leitura. O app não lê o conteúdo das mensagens.
- Não há servidor próprio, telemetria nem envio das conversas para o repositório.

Detalhes sobre os arquivos consultados e as conexões estão em [Privacidade](PRIVACY.md).

## Compilar localmente

Para desenvolvimento, use Xcode ou Xcode Command Line Tools com Swift 5.10 ou mais recente:

```sh
./scripts/build-app.sh
./scripts/install-companion.sh
```

A instalação pelo script usa `~/Applications/Codex Reset.app`. O DMG também permite instalar nessa pasta; ao atualizar, substitua a cópia que já utiliza para evitar duas instalações.

Para compilar uma arquitetura específica:

```sh
./scripts/build-app.sh --arch arm64
./scripts/build-app.sh --arch x86_64
```

## Publicar uma nova versão

A publicação acontece no Mac do desenvolvedor, usando o GitHub CLI autenticado. **Este projeto não usa GitHub Actions nem CI.**

1. Incremente `CFBundleShortVersionString` e `CFBundleVersion` em `Info.plist`.
2. Escreva as novidades em `releases/vVERSAO.md`.
3. Revise os arquivos e faça o commit das mudanças.
4. Execute:

```sh
./scripts/publish-release.sh
```

O comando compila as duas arquiteturas, monta e confere os DMGs, gera os hashes e publica os arquivos em uma nova Release, marcada como a mais recente. Os links de download acima passam a apontar para ela automaticamente. O histórico de versões permanece disponível.

Para gerar somente os DMGs, sem publicar:

```sh
./scripts/create-dmgs.sh
```

Os arquivos locais são gerados em `.build/releases/VERSAO/` e nunca entram no Git. Depois de confirmar a publicação, a pasta `.build/` pode ser removida para limpar os artefatos de compilação.
