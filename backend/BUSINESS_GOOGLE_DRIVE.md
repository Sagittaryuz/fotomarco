# Armazenamento compartilhado Google Drive

Escopo pendente: o seletor no aplicativo ainda não conecta o Google Drive Business. Não ativar esta opção como funcional antes de concluir e validar os itens abaixo.

## Privacidade

- Usar uma pasta Photomark privada para a organização e conceder acesso somente à pasta individual do membro, nunca à pasta ancestral inteira. Verificar a lista completa de permissões e a identidade de cada destinatário antes e depois de conceder acesso. Se não for possível verificar, recusar a operação.
- Permissões de pastas se propagam para os descendentes. Pastas com acesso limitado podem desativar herança apenas quando o recurso e as capacidades da conta permitirem; não presumir que estejam disponíveis. Não modificar permissões ou pastas preexistentes do usuário para forçar a operação.
- Revogação deve retirar o acesso do membro e ser confirmada antes de declarar a operação concluída. Serializar modificações de permissões da mesma pasta, pois a API não suporta alterações simultâneas confiáveis.
- Não incluir tokens, nomes de arquivos, e-mails ou respostas brutas do provedor em logs. Não enviar convites em testes sem instrução explícita.

## Integração a implementar e validar

1. Autorizar separadamente a conta Google da organização para os arquivos utilizados pelo aplicativo. Conferir o escopo `drive.file`, a identidade do proprietário e se pastas existentes foram explicitamente disponibilizadas ao aplicativo; esse escopo não dá acesso automático a todo o Drive.
2. Criar e verificar a hierarquia sem renomear ou mover fotos existentes. Identificar cada pasta por ID persistido e marcador de criação para evitar colisões. A pasta pessoal anterior permanece intacta.
3. Provisionar uma pasta por membro com acesso apenas do proprietário e do próprio membro, verificando permissões herdadas, diretas e paginação. Testar membros estrangeiros, revogação, falhas e respostas incertas.
4. Integrar envio, verificação de integridade, listagem, miniaturas e download no serviço Business com autorização por membro a cada operação. Não declarar upload concluído apenas pelo início da transferência.
5. Conectar a opção do aplicativo somente após testes de servidor, regras e dispositivos. O armazenamento atual em OneDrive deve permanecer acessível, inclusive durante eventual troca futura de conta.

A rotina experimental de hierarquia exige a ID de uma pasta de imagens explicitamente selecionada e verifica seu vínculo com a raiz e suas permissões. Ela usa marcadores persistidos para retomar as subpastas criadas pelo app; ainda falta integrar a seleção e o salvamento desses marcadores no servidor e no aplicativo. Como `drive.file` pode ocultar pastas já existentes, a rotina não comprova ausência de uma pasta Photomark não selecionada: não a ativar antes de definir como o usuário escolhe ou confirma o destino e validar a conta real.

Fontes oficiais: [propagação e gerenciamento de permissões](https://developers.google.com/workspace/drive/api/guides/manage-sharing), [pastas com acesso limitado](https://developers.google.com/workspace/drive/api/guides/limited-expansive-access), [escopos do Drive](https://developers.google.com/workspace/drive/api/guides/api-specific-auth) e [criação de permissões](https://developers.google.com/workspace/drive/api/reference/rest/v3/permissions/create).
