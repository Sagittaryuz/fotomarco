# Preparação do Google no Momentra nativo

O IPA de teste 0.1.3 não contém um cliente Google configurado. A entrada na conta, a galeria em nuvem, o seletor e o envio ainda não funcionam nessa versão. A câmera e as fotos locais podem ser usadas escolhendo “Continuar por enquanto”.

## Antes de configurar

1. Confirmar se as fotos que serão acessadas ou enviadas são de natureza pessoal. A [política das APIs do Google Fotos](https://developers.google.com/photos/support/api-policy) restringe seu uso com mídias que não sejam pessoais; não presumir que esse serviço seja adequado para arquivos internos de trabalho.
2. Identificar o projeto Google autorizado para o Momentra e verificar suas configurações existentes antes de alterá-lo. O projeto Scripting usa outro fluxo OAuth; não trocar seu cliente ou callback de produção por suposição.
3. Confirmar o identificador efetivo do aplicativo após a assinatura no Signulous. O pacote de teste sem assinatura contém `br.com.momentra.camera`; ainda é necessário verificar se a assinatura preserva esse identificador. O cliente OAuth iOS deve corresponder ao identificador efetivamente usado.

## Configuração no Google

No projeto correto do Google Cloud, criar ou localizar um cliente OAuth do tipo **iOS** com o identificador do aplicativo confirmado e preparar a tela de consentimento e os usuários de teste conforme as opções da conta. Registrar o ID do cliente e seu esquema de URL invertido em um local seguro para a etapa de compilação; não inserir senhas, tokens, segredos ou dados pessoais no Git ou em backups. Um cliente Web existente não deve ser presumido equivalente ao cliente iOS.

Para a galeria em nuvem, habilitar **Google Photos Library API** e **Google Photos Picker API** no mesmo projeto somente após confirmar o uso adequado e verificar a configuração existente. A Picker API do Google Fotos é diferente da Google Picker API genérica. A aplicação pede a autorização de cada recurso no contexto correspondente; entrar na conta não envia fotos.

As APIs podem exigir configuração da tela de consentimento e revisão do Google conforme a distribuição e os escopos. Durante testes, a conta precisa estar autorizada no projeto. Evitar trocar o cliente depois de criar conteúdo: o Google informa que recursos criados por um cliente podem não ficar acessíveis a outro.

## Integração e validação

O aplicativo precisa receber no `Info.plist` do **novo build** o `GIDClientID` iOS e o esquema de retorno invertido, sem colocar segredos no pacote. O projeto atual verifica a presença e a correspondência desses dois valores antes de habilitar a conexão. A configuração ainda não foi aplicada nem testada; é necessário gerar outro IPA e assiná-lo.

No iPhone, testar login, retorno ao app, restauração da sessão, desconexão, concessão e recusa de permissões, envio manual de foto pessoal e sua verificação, listagem de itens criados pelo app e seleção de uma foto existente. Confirmar que o original continua disponível e que nenhum envio acontece sem a ação escolhida. Não afirmar que as fotos ou permissões do Scripting foram migradas automaticamente.

Fontes: [Google Sign-In para iOS](https://developers.google.com/identity/sign-in/ios/start-integrating), [configuração das APIs do Google Fotos](https://developers.google.com/photos/overview/configure-your-app), [seleção de fotos](https://developers.google.com/photos/picker/guides/get-started-picker).
