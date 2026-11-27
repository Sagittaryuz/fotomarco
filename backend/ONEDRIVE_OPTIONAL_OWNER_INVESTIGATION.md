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

Antes de alterar a política de segurança, obter a categoria sanitizada de erro
do fluxo real, testar respostas com `owner` ausente, compatível e divergente,
e verificar uma conta pessoal real. Não registrar IDs, tokens, e-mails, fotos
ou respostas completas do provedor. Não modificar permissões existentes nem
transferir fotos para testar.
