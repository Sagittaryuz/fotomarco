# Integração com Controle da Câmera

O Momentra ainda não aparece na lista de apps para abrir pelo Controle da Câmera. Ter acesso à câmera não é suficiente: a Apple exige uma extensão `LockedCameraCapture` para essa integração. A extensão e o app devem compartilhar um `CameraCaptureIntent`; o sistema decide se abre o app ou a extensão conforme o estado do aparelho. Para tratar o botão como disparador, a Apple indica `AVCaptureEventInteraction` do AVKit.

## Trabalho necessário

- Implementar a extensão de captura da Apple, com interface de câmera funcional e intenção de captura compartilhada com o app e com o controle de sistema apropriado.
- Adaptar a captura para as restrições da extensão e guardar o conteúdo da sessão em `sessionContentURL`. Importar o conteúdo pelo mecanismo da Apple no app principal e somente descartar dados depois de confirmar a importação; preservar as fotos existentes.
- Definir como aplicar o carimbo quando localização, mapa, endereço, internet ou preferências não estiverem acessíveis. Não inventar dados e não prometer paridade antes de verificar as restrições reais.
- Incluir a extensão no IPA, verificar identificadores e assinatura de todos os componentes e testar a instalação via Signulous. A compatibilidade desse serviço com essa extensão e seus eventuais requisitos de assinatura ainda não foi confirmada.
- Testar no iPhone físico a seleção em Ajustes, abertura com aparelho bloqueado e desbloqueado, disparo, salvamento e importação, bem como preservação das capturas anteriores. Testes no simulador não comprovam o funcionamento do botão físico.

Fontes: [integração com o Controle da Câmera](https://developer.apple.com/documentation/avfoundation/enhancing-your-app-experience-with-the-camera-control), [experiência de captura na tela bloqueada](https://developer.apple.com/videos/play/wwdc2024/10204/), [conteúdo da sessão](https://developer.apple.com/documentation/lockedcameracapture/lockedcameracapturesession/sessioncontenturl).
