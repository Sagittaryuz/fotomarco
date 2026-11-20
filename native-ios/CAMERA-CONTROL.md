# Integração com Controle da Câmera

## Configuração no iPhone

O projeto inclui a extensão LockedCameraCapture, a intenção compartilhada e o
controle do WidgetKit. No iPhone compatível, abra **Ajustes → Câmera → Controle
da Câmera** e selecione **Momentra** se o sistema mostrar o app na lista. A escolha
é feita pelo usuário. A instalação e a presença na lista precisam ser conferidas
no aparelho físico, com a tela bloqueada e desbloqueada.

O disparo físico usa os eventos de captura do AVKit. Já o painel que o iOS
mostra com um toque leve no botão é configurado na sessão do AVFoundation.
Para acrescentar zoom ou exposição nesse painel, verifique `supportsControls`
e `canAddControl` antes de registrar os controles de sistema correspondentes.
Para uma escolha discreta do Momentra, como perfil de carimbo, a API oferece
`AVCaptureIndexPicker`. A integração desse painel é uma etapa futura.

- [Manual do iPhone](https://support.apple.com/guide/iphone/iph3940f00d2/ios)
- [Integração com o Controle da Câmera](https://developer.apple.com/documentation/avfoundation/enhancing-your-app-experience-with-the-camera-control)
- [Controles de captura na WWDC25](https://developer.apple.com/videos/play/wwdc2025/253/)

## Diagnóstico inicial do projeto

O Momentra ainda não aparece na lista de apps para abrir pelo Controle da Câmera. Ter acesso à câmera não é suficiente: a Apple exige uma extensão `LockedCameraCapture` para essa integração. A extensão e o app devem compartilhar um `CameraCaptureIntent`; o sistema decide se abre o app ou a extensão conforme o estado do aparelho. Para tratar o botão como disparador, a Apple indica `AVCaptureEventInteraction` do AVKit.

## Trabalho necessário

- Implementar a extensão de captura da Apple, com interface de câmera funcional e intenção de captura compartilhada com o app e com o controle de sistema apropriado.
- Adaptar a captura para as restrições da extensão e guardar o conteúdo da sessão em `sessionContentURL`. Importar o conteúdo pelo mecanismo da Apple no app principal e somente descartar dados depois de confirmar a importação; preservar as fotos existentes.
- Definir como aplicar o carimbo quando localização, mapa, endereço, internet ou preferências não estiverem acessíveis. Não inventar dados e não prometer paridade antes de verificar as restrições reais.
- Incluir a extensão no IPA, verificar identificadores e assinatura de todos os componentes e testar a instalação via Signulous. A compatibilidade desse serviço com essa extensão e seus eventuais requisitos de assinatura ainda não foi confirmada.
- Testar no iPhone físico a seleção em Ajustes, abertura com aparelho bloqueado e desbloqueado, disparo, salvamento e importação, bem como preservação das capturas anteriores. Testes no simulador não comprovam o funcionamento do botão físico.

Fontes: [integração com o Controle da Câmera](https://developer.apple.com/documentation/avfoundation/enhancing-your-app-experience-with-the-camera-control), [experiência de captura na tela bloqueada](https://developer.apple.com/videos/play/wwdc2024/10204/), [conteúdo da sessão](https://developer.apple.com/documentation/lockedcameracapture/lockedcameracapturesession/sessioncontenturl).


## Estado do candidato em desenvolvimento

O candidato contém a intenção compartilhada, o controle WidgetKit e a extensão de captura. A câmera bloqueada registra o identificador do perfil e, quando aplicável, a conta escolhida para a nuvem, sem imprimir o nome do perfil no carimbo. O app principal importa os arquivos da sessão, compara as cópias e só pede ao sistema para invalidar uma sessão integralmente reconhecida e preservada. Se a verificação falhar, mantém a sessão.

A extensão ainda não oferece a mesma interface completa, gravação de vídeo, mapa ou logotipo do app principal. A Apple restringe o acesso à rede e ao contêiner compartilhado durante a captura bloqueada; é necessário resolver esses recursos antes de afirmar paridade. A presença da extensão no IPA não assinado foi verificada, mas sua assinatura pelo Signulous, a aparição na lista e o uso do botão físico ainda não foram comprovados no iPhone.

## Verificação do IPA instalado 0.1.27

O IPA assinado contém a extensão de captura, a extensão de controle e metadados da intenção nos três componentes. A inspeção da assinatura encontrou o mesmo `application-identifier` nos três executáveis, embora seus identificadores de pacote sejam distintos. Isso diverge do formato de identificador descrito pela Apple para a assinatura; é uma hipótese a investigar, não uma confirmação da causa da ausência do Momentra na lista do iPhone. Não alterar o identificador nem a equipe do app instalado sem verificar que a atualização preserva os dados.

Ao comparar um novo IPA assinado, verificar cada executável, seu perfil de provisionamento e a elegibilidade da extensão no aparelho; não registrar os valores de credenciais ou identificadores de equipe. O nome `com.apple.developer.locked-camera-capture` não foi encontrado como texto nos executáveis desse IPA. Uma pergunta no fórum de desenvolvedores cita esse possível entitlement, mas não confirma que ele seja necessário ou como obtê-lo; não acrescentá-lo nem alegar solução sem evidência da Apple e do perfil de assinatura.

Fontes: [Camera Control](https://developer.apple.com/design/human-interface-guidelines/camera-control/), [experiência de captura bloqueada](https://developer.apple.com/documentation/lockedcameracapture/creating-a-camera-experience-for-the-lock-screen), [diagnóstico de assinatura](https://developer.apple.com/library/archive/technotes/tn2415/).
