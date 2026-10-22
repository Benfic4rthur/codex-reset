# Codex Reset

## Produto e distribuição

- O repositório é público. Cada instalação precisa usar o login, a franquia e os arquivos locais do próprio usuário.
- Preserve o visual integrado ao recorte nos Macs com notch. A lateral da atividade deve usar a menor largura necessária aos textos e à seta, crescer quando precisar e manter a câmera e o indicador de franquia ancorados. Mesmo com os detalhes abertos, o topo mantém a largura compacta; a largura dos detalhes começa apenas abaixo da barra. O botão de desligar fica centralizado acima da divisória dos resets, com cursor de mão ao passar sobre ele. Em telas sem notch, incluindo MacBooks Intel e M1, mantenha a cápsula compacta inteira dentro da altura da barra de menus, centralizada e com uma pequena margem no topo. Meça a altura disponível pela tela e pelo macOS, sem tabelas fixas por modelo. Use a porcentagem grande com uma barra horizontal de progresso separada, sem anel envolvendo o número. Exiba a atividade em uma linha legível e aproveite a largura da barra, sem invadir as janelas em modo compacto. Detecte o notch pela tela; não limite a cápsula à arquitetura Intel.
- A previsão de reset extra deve usar somente intervalos entre resets dos últimos 30 dias e datas de início e fim estimadas a partir do último reset observado. Consulte a fonte na abertura do aplicativo e a cada duas horas enquanto estiver aberto. Permita estimativa a partir de seis intervalos válidos; entre seis e onze, indique amostra pequena. Abaixo de seis, informe histórico insuficiente, sem ampliar a janela de 30 dias. As contagens devem mostrar dias e horas enquanto faltar pelo menos um dia, e horas e minutos nas últimas 24 horas. A contagem não deve reiniciar a cada consulta com os mesmos dados. Apresente o reset extra como uma janela em linguagem clara, com indicação de estimativa histórica; mantenha o reset semanal identificado como informação da conta. Se a janela passar, mostre que ela terminou e aguarde novos dados. Preserve a indicação de estimativa histórica.
- Não use GitHub Actions, pipelines, serviços ou configurações de CI. O GitHub Actions deve continuar desativado no repositório.
- Compile e confira os artefatos localmente. Publique atualizações funcionais em GitHub Releases com os dois DMGs, Apple Silicon e Intel, usando scripts/publish-release.sh.
- Para cada versão, incremente os dois campos de versão em Info.plist e mantenha as notas em releases/vVERSAO.md. Os links de download no README devem continuar apontando para a última Release.
- A versão atual deve ficar destacada acima dos downloads e nos dois botões do README. Após publicar, scripts/publish-release.sh confirma a última Release e atualiza esse bloco automaticamente com scripts/update-downloads.py, enviando o commit ao GitHub. Preserve os marcadores do bloco e não anuncie uma versão antes de publicar seus dois DMGs.
- Não sobrescreva uma versão publicada; publique uma versão nova.

## Privacidade

- Nunca versione nem distribua chaves, tokens, arquivos .env, autenticação do Codex, bancos locais, logs, certificados privados ou dados de conversas.
- Resolva caminhos de usuário em tempo de execução. Não inclua caminhos pessoais de compilação nos executáveis distribuídos.
- Revise o conteúdo dos DMGs antes da publicação. Eles devem conter apenas o app, um atalho para Aplicativos e instruções públicas.
- Não inclua certificados pessoais na distribuição nem prometa notarização sem que ela tenha sido realizada.

## Limpeza

- Mantenha todos os artefatos de compilação, DMGs e arquivos temporários dentro de .build/, que está ignorada pelo Git.
- Após conferir uma publicação solicitada, remova os artefatos temporários locais. Preserve os fontes, o ícone e os scripts necessários para reproduzir a versão.
