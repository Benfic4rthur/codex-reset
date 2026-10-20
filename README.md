<p align="center">
  <img src="Assets/CodexReset.png" width="112" alt="Ícone do Codex Reset">
</p>

# Codex Reset

Sua franquia do Codex sempre à vista. Um monitor nativo para macOS que mostra a porcentagem semanal restante, as conversas ativas e o tempo até a próxima renovação.

## Downloads

| Apple Silicon · M1, M2, M3 e posteriores | Intel · x86_64 |
| :---: | :---: |
| **[⬇ Baixar para Apple Silicon](https://github.com/Benfic4rthur/codex-reset/releases/latest/download/Codex-Reset-Apple-Silicon.dmg)** | **[⬇ Baixar para Intel](https://github.com/Benfic4rthur/codex-reset/releases/latest/download/Codex-Reset-Intel.dmg)** |
| Visual integrado ao notch | Cápsula centralizada, a 5 pixels do topo da tela |

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
- **Renovação semanal:** ao passar o mouse, aparece o tempo até a renovação informada pela conta.
- **Reset extra:** estimativa histórica baseada em [codex-resets.com](https://codex-resets.com/), atualizada a cada 5 minutos. Não representa uma promessa nem um aviso antecipado da OpenAI.

Na versão Intel, a cápsula fica centralizada, a 5 pixels da borda superior da tela, logo abaixo da câmera. Essa pequena folga mantém o contorno arredondado e o tamanho inteiro visíveis. Ela ocupa apenas o espaço da franquia quando não há atividade e cresce quando há conversas. A versão Apple Silicon mantém o visual junto ao notch.

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
