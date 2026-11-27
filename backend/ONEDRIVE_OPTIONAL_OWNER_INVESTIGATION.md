# Investigação: identificação do OneDrive da organização

O conector verifica que `drive.owner.user.id` coincide com o ID obtido em `/me`.
A Microsoft documenta o campo `owner` do recurso `drive` como opcional. Uma
resposta válida sem esse campo será rejeitada em `business-microsoft-oauth.mjs`
e também nas verificações de pasta `business-onedrive-folders.mjs` e
`business-onedrive-verify.mjs`. Isso é uma hipótese para a falha observada,
não a causa comprovada: ainda não foi capturada a categoria de erro do fluxo
real do aplicativo após a implantação dos diagnósticos.

Fontes oficiais: [recurso drive](https://learn.microsoft.com/en-us/graph/api/resources/drive?view=graph-rest-1.0)
e [obter o OneDrive do usuário autenticado](https://learn.microsoft.com/en-us/graph/api/drive-get?view=graph-rest-1.0).
O endpoint `/me/drive` retorna o drive do usuário do token delegado, mas uma
mudança deve assegurar que `/me`, `/me/drive`, as credenciais persistidas e o
destino das pastas usem a mesma identidade. Não basta remover a comparação em
um dos três pontos: o provisionamento e a verificação posterior devem concordar.

Uma correção experimental, ainda não implantada, confirma `/me` com o mesmo
token sempre que `owner` está ausente. Quando `owner` está presente, uma
identidade divergente continua sendo rejeitada. A pasta ainda passa pelas
verificações de permissões anteriores. Os testes simulam respostas ausentes,
compatíveis e divergentes; ainda é necessário obter a categoria sanitizada do
erro real e verificar uma conta pessoal real antes da publicação. Não registrar
IDs, tokens, e-mails, fotos ou respostas completas do provedor. Não modificar
permissões existentes nem transferir fotos para testar.

Em uma verificação somente de leitura, o conector Microsoft confirmou a conta
solicitada e um drive pessoal; a listagem da raiz funcionou. A leitura de
permissões de uma pasta existente retornou `FORBIDDEN` e `serviceReadOnly`.
Esse conector usa credenciais distintas das usadas pelo Photomark: o resultado
não identifica o erro do aplicativo nem comprova que suas permissões são iguais.
Nenhuma pasta ou permissão foi modificada.

A [documentação das permissões](https://learn.microsoft.com/en-us/graph/api/driveitem-list-permissions?view=graph-rest-1.0)
informa que o proprietário recebe todas as permissões, mas outros chamadores
podem receber apenas as próprias. Portanto uma listagem parcial ou negada não
comprova que a pasta é privada; o serviço deve continuar recusando a operação
quando não conseguir verificar as permissões efetivas.
