# Privacidade do Codex Reset

O Codex Reset funciona no Mac de quem o instalou e usa o Codex autenticado nesse computador. A distribuição não inclui credenciais, bancos de dados ou configurações de quem desenvolveu o aplicativo.

## Dados locais consultados

- **Franquia e renovação:** consulta somente de leitura ao método `account/rateLimits/read` do Codex App Server local. A autenticação continua sob responsabilidade do Codex instalado. O monitor não exporta nem copia o arquivo de autenticação.
- **Conversas ativas:** acesso de leitura aos bancos `state_5.sqlite` e `thread_history_1.sqlite` na pasta local do Codex. São consultados identificadores, nomes de projetos e conversas, modelo, esforço, total acumulado de tokens e estado da execução. O consumo estimado em tokens por segundo usa a diferença entre esses totais em amostras de cinco segundos. O conteúdo das mensagens não é lido.
- A pasta do Codex é resolvida para o usuário atual, respeitando `CODEX_HOME` quando definido. Nenhum caminho pessoal de outro usuário é necessário.

A franquia e os metadados das conversas ficam em memória. As preferências locais do macOS guardam somente a disposição dos campos, as medidas escolhidas, o horário do último reset observado na conta e quantas vezes o aviso já foi apresentado. Não são salvos nomes de conversas, contagens de tokens, credenciais ou cópias dos bancos. Os bancos consultados não são modificados pelo monitor. Não há envio do histórico, nomes de projetos ou franquia para o GitHub ou para um servidor do projeto.

## Conexões

- O processo local do Codex faz as consultas à OpenAI usando a própria sessão do usuário, conforme o funcionamento do Codex.
- O monitor consulta a API pública de `codex-resets.com` na abertura, a cada duas horas, pelo botão de atualizar e ao detectar uma renovação extraordinária da franquia para obter o histórico de resets. O cálculo usa somente os últimos 30 dias; a contagem regressiva é atualizada localmente, sem consultar a fonte a cada minuto. A renovação observada na conta serve apenas de referência para a próxima janela estimada; não é enviada ao site nem adicionada à amostra pública. Essa consulta não inclui login, chaves, franquia ou conversas do usuário. Como em qualquer conexão HTTPS, o serviço de destino recebe os dados normais da conexão, como o endereço IP.
- Não há telemetria, anúncios ou mecanismo próprio de atualização. Downloads de novas versões são feitos manualmente pelo GitHub Releases.

## Arquivos instalados

O aplicativo fica na pasta Aplicativos escolhida pelo usuário. Na primeira abertura de uma cópia instalada, é criado um LaunchAgent em `~/Library/LaunchAgents/` para acompanhar a abertura e o encerramento do Codex Desktop. Esse arquivo contém apenas o caminho do aplicativo, a versão e as instruções de início automático; não contém credenciais.

Se a leitura da franquia ou do histórico local não estiver disponível, o aplicativo não usa uma conta alternativa ou dados de outra pessoa. Mudanças nas interfaces internas do Codex podem exigir uma atualização do monitor.

## Distribuição

O código-fonte, o ícone e os scripts de compilação são públicos. Credenciais, arquivos `.env`, certificados privados, bancos locais, logs e artefatos de compilação não devem ser adicionados ao repositório. Os DMGs distribuídos contêm apenas o aplicativo, um atalho para Aplicativos e um arquivo com instruções.
