# Instaladores Windows PrimeYou

Dois instaladores independentes, com UAC somente durante a instalacao:

- **Instalar-PrimeYouConnection.bat**: politicas de pagina inicial e inicializacao do Edge/Chrome para o portal PrimeYou Connection. Pacote inicial 1.0.0.
- **Instalar-Configuracao-Energia.bat**: configuracoes de energia e barra de tarefas. Pacote inicial 1.2.0, baseado nos arquivos fornecidos da versao 1.1.0.

Baixe o BAT correspondente pela opcao **Download raw file** do GitHub (ou baixe o ZIP de distribuicao), salve no computador e execute. Cada BAT e autonomo; a primeira instalacao precisa de internet. Nao e necessario Git, GitHub CLI ou token no computador de destino. Requer Windows 11 e permissao de administrador. Nao execute a pagina HTML salva como BAT.

## Funcionamento

O instalador salva o atualizador em `%ProgramData%\PrimeYouManaged`, com gravacao permitida somente a administradores e SYSTEM. Usuarios autenticados possuem leitura para permitir que o Explorer leia o layout da barra.

Para cada produto, registra duas tarefas como SYSTEM:

| Tarefa | Gatilho | Comportamento |
| --- | --- | --- |
| PrimeYou-connection-Atualizar / PrimeYou-energia-Atualizar | Inicializacao | Consulta manifesto no GitHub, atualiza somente se a versao remota for maior e aplica configuracoes |
| PrimeYouConnection-VerificarHomepage / ConfiguracaoEnergiaCorporativa | Logon de qualquer usuario | Aplica somente a versao local, sem consultar o GitHub |

As tarefas de logon substituem as tarefas dos instaladores antigos. Nao pedem UAC nem senha; atendem usuarios existentes e novos, incluindo Entra ID. Se boot e logon coincidirem, um bloqueio impede execucao simultanea do mesmo produto.

Mesma versao (ou versao remota inferior): baixa apenas o pequeno manifesto; nao baixa nem substitui os scripts. As configuracoes locais continuam sendo aplicadas. Sem rede, hash invalido ou falha na atualizacao: conserva o apontamento para a ultima versao valida e tenta aplica-la. Sem nenhuma versao local valida, a instalacao falha com log. Versoes antigas e candidatos incompletos permanecem isolados para diagnostico, sem serem escolhidos automaticamente.

Arquivos sao baixados para uma pasta separada, conferidos por SHA256 e sintaxe, e executados antes de promover a versao. A promocao do estado e atomica; uma falha na aplicacao pode ter alterado parte das politicas antes da reaplicacao da versao anterior. Nao ha promessa de rollback transacional das configuracoes do Windows.

## Energia e barra de tarefas

| Configuracao | Tomada | Bateria |
| --- | --- | --- |
| Modo | Melhor desempenho | Melhor eficiencia |
| Tela | 15 minutos | 15 minutos |
| Suspensao | Nunca | 1 hora |
| Hibernacao | Nunca | 1 hora (3600 segundos) |
| Economia de energia | — | 20% |

Adiciona Outlook classico, Teams atual (MSIX) e Chrome, preservando os demais fixados. Requer aplicativos instalados para o usuario. Saia da conta e entre novamente apos instalar. O instalador configura a politica local Start Layout; politicas Intune/GPO podem prevalecer. Nao instala Office, Teams ou Chrome. Nao altera o papel de parede existente no repositorio.

## Publicar uma atualizacao

1. Copie a pasta da versao anterior em `connection/versions` ou `energia/versions` para uma nova pasta numerada (`MAJOR.MINOR.PATCH`). Nao altere versoes ja publicadas.
2. Edite os scripts da nova versao. `Apply.ps1` e o ponto de entrada. Connection deve continuar usando `-Aplicar` no script fornecido, para nao criar tarefas antigas novamente.
3. Atualize a versao correspondente no inicio de `Build-Packages.ps1` e execute-o no PowerShell. Ele recalcula hashes, manifestos e instaladores.
4. Revise e publique todos os arquivos da versao junto com o manifesto na branch `main`. Cada produto tem sua propria versao.

Mudar o conteudo sem aumentar a versao nao atualiza as maquinas. Versoes de quatro componentes e pre-releases nao sao aceitas. O atualizador/instalador em `runtime` nao se autoatualiza: mudancas nesse mecanismo exigem gerar e executar novamente o BAT. Os scripts de configuracao dos produtos se atualizam automaticamente.

## Seguranca e operacao

O repositorio e publico: nao publique senhas, tokens ou dados pessoais. SHA256 detecta download corrompido, mas nao autentica o autor: quem puder alterar a branch `main` podera publicar codigo que executara como SYSTEM. Proteja a conta com MFA e restrinja escrita na branch. Nao sao usadas credenciais GitHub nas maquinas.

Logs: `%ProgramData%\PrimeYouManaged\connection\Ultima-Execucao.log` e `%ProgramData%\PrimeYouManaged\energia\Ultima-Execucao.log`. O log e substituido a cada execucao. Estado/versionamento local: `installed.json` na mesma pasta do produto. Internet deve estar disponivel para SYSTEM; autenticacao de proxy por usuario pode impedir download no boot.

Para testes sem modificar politicas da maquina: execute `Test-Updater.ps1`. Os testes simulam mesma versao, versao inferior, nova versao, hash incorreto, falta de rede, falha ao aplicar e logon sem rede. A instalacao real e a barra de tarefas precisam ser validadas no dispositivo de destino.

Referencia: [configuracao de aplicativos fixados no Windows](https://learn.microsoft.com/en-us/windows/configuration/taskbar/pinned-apps).
