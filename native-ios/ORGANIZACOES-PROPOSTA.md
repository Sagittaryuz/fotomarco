# Organizações Photomark — proposta de implementação

Estado: desenho em andamento; não ativado em produção. Base inspecionada: branch feat/stamp-models, commit 4e58a37, versão 0.1.48 (69).

## Objetivo
Uma pessoa cria uma organização, administra seus integrantes e publica perfis de carimbo. Membros usam o carimbo sem editar a versão da organização. O responsável vê as fotos de todos os membros e cada membro vê apenas as suas, com autorização aplicada no servidor e no provedor. Contas pessoais, fotos e perfis existentes devem permanecer intactos.

## Estado existente
- StampProfilesStore guarda os perfis em UserDefaults no dispositivo; nomes de logotipos referem-se a arquivos locais. Não existe sincronização de perfis entre usuários.
- O app autoriza contas de nuvem individualmente por OAuth e protege credenciais no Keychain. Google Drive usa drive.file; OneDrive usa Files.ReadWrite.AppFolder e /me/drive/special/approot.
- CloudArchiveJournal e CloudArchiveDelivery mantêm recebimentos, retomada e preservação das capturas pendentes. Não transferir fotos nem alterar contas existentes automaticamente.
- O Worker existente é uma ponte OAuth, não é serviço de organizações nem banco de dados de integrantes.

## Decisões de produto informadas
- Conta inicial: o proprietário indicado pelo responsável será atribuído por identidade autenticada, nunca por endereço gravado no aplicativo ou por uma alegação não verificada do cliente.
- Plano comum e plano Business: R$ 500 por organização por ano, com até 500 usuários. Cobrança real e conformidade com as regras aplicáveis de distribuição precisam de implementação e validação antes da comercialização; não ativar pagamentos fictícios.
- Primeira organização: OneDrive do proprietário. Novas capturas profissionais devem seguir Imagens / Photomark / Nome (e-mail), respeitando as restrições do provedor. Não mover ou renomear pastas e arquivos antigos automaticamente.
- O integrante pode selecionar o perfil pessoal ou o perfil da organização; só responsáveis podem alterar a versão organizacional.
- Infraestrutura de organizações: necessário serviço isolado de autenticação, banco persistente e aplicação de permissões no servidor. Nenhum projeto de outro aplicativo deve ser reutilizado implicitamente.

## Modelo proposto
- Usuário autenticado: ID estável do serviço de autenticação; nome e sobrenome de exibição.
- Organização: ID, nome, proprietário, estado e datas. Proprietário e membros são relações no servidor, não propriedades editáveis pelo cliente.
- Integrante: organização, usuário, papel (proprietário, administrador ou integrante), estado e data de revogação. Operações sensíveis verificam membership atual no servidor.
- Convite: organização, destinatário autenticado, papel, validade, aceite e revogação. Convites não concedem acesso a terceiros nem enviam mensagens automaticamente sem ação autorizada.
- Perfil publicado: organização, ID de perfil, versão imutável, conteúdo validado, referências a logotipos e autor. Apenas responsáveis autorizados podem publicar. Integrantes recebem versão somente leitura; a captura guarda a versão utilizada.
- Foto compartilhada: ID da captura, autor, organização, perfil e versão usados, provedor, referência e estado verificado de entrega. A leitura de metadados não dispensa a permissão efetiva do provedor sobre o arquivo.

## Fluxo
1. Cadastro/entrada com e-mail e senha ou provedor Google/Microsoft, preservando o acesso e os dados atuais e sem transportar credenciais existentes. A política de transição precisa impedir bloqueio dos usuários atuais.
2. Criar organização; escolher perfil existente para publicar sem modificar o original local.
3. Criar e aceitar convite explicitamente; conceder acesso apenas ao membro correspondente.
4. O proprietário autoriza a pasta OneDrive de destino. Cada integrante autentica sua conta do Photomark; se o desenho exigir autenticação no provedor de nuvem, cada um autoriza sua própria conta, com consentimento para escopos adicionais. O acesso de escrita deve impedir leitura das pastas dos demais.
5. Capturas feitas sob perfil da organização entram na fila existente e são expostas aos membros somente após confirmação no provedor. Falha ou permissão ausente mantém arquivo local e mostra pendência.
6. Remover integrante bloqueia imediatamente novas consultas no serviço; revogação no Google/Microsoft deve ser feita e confirmada separadamente. Downloads já feitos, capturas de tela e cópias existentes não podem ser recolhidos tecnicamente.

## Segurança e privacidade
- Autorizar no servidor cada leitura e alteração por usuário, organização, papel e recurso; ocultar botão de edição não é controle de acesso.
- Não guardar senhas de Google/Microsoft nem tokens de acesso de um integrante no dispositivo ou conta de outro. Usar o fluxo oficial do provedor e mínimo escopo possível.
- Perfis e logos podem conter dados privados. Não expor URLs públicas ou incluir tokens em logs, repositórios, métricas ou notificações.
- No modo offline, registrar a versão de perfil em cache e não prometer revogação instantânea quando o dispositivo estiver desconectado.
- Confirmar separadamente as ACLs do provedor. Pasta compartilhada pode conceder escrita/exclusão dependendo das permissões do provedor; a interface do app sozinha não impede exclusão direta no Drive/OneDrive.
- Atualizar documentação de privacidade e retenção antes de liberar; se houver distribuição pela App Store, revisar os requisitos de login da Apple.

## Plano de validação
1. Testes automatizados de autenticação, autorização no servidor e isolamento: proprietário, administrador, membro, não membro, convite expirado e acesso após revogação.
2. Testar perfil somente leitura, versionamento, logos, falta de rede, alteração concorrente e preservação dos perfis locais.
3. Usar duas contas de teste por provedor para concessão, leitura, falta de permissão, remoção, reconexão e integridade das fotos. Não usar fotografias pessoais insubstituíveis.
4. Testar interrupção, respostas ambíguas, reenvio idempotente, exclusão, integridade e armazenamento cheio; nunca limpar cópia local antes da confirmação adequada.
5. Compilar e testar iOS; instalar sobre a versão existente no iPhone e confirmar perfis, fotos e sessões. Publicar somente após os testes de isolamento e o caminho real de dois usuários funcionarem.

## Referências
- https://learn.microsoft.com/en-us/graph/permissions-reference
- https://learn.microsoft.com/en-us/graph/api/driveitem-invite?view=graph-rest-1.0
- https://developers.google.com/workspace/drive/api/guides/manage-sharing
- https://developer.apple.com/app-store/review/guidelines/
