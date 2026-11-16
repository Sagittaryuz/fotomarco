# Momentra — protótipo 0.1.0

Fonte: `Sagittaryuz/momentra` (privado). Branch de desenvolvimento: `feat/camera-mvp`.

## Estado
- Captura JPEG com `AVCaptureSession`, visor ao vivo e `onCameraCaptureEvent`.
- Controles laterais para perfil, chave de carimbo (somente estado), disparo, prévia e salvamento manual em Fotos.
- Carimbo aplicado aos pixels, GPS, endereço, mapa de satélite, logotipo, edição de layouts, atualização automática e carregador autenticado: **não implementados**.
- **Não testado no iPhone.** A presença do código não comprova que o importador de scripts remotos o reconheça.

## Instalação e segurança
O repositório é privado. A tela de importação remota pode não suportar autenticação para esse repositório. Não tornar público e não colocar token em URLs ou no código. Primeiro validar a importação com uma conta autorizada; se necessário, usar exportação local do projeto e um carregador com autenticação segura a ser implementado. Não usar link raw privado como se fosse público.

## Homologação
1. Confirmar versão do Scripting PRO e a forma aceita de projeto remoto.
2. Abrir o script e permitir acesso à câmera.
3. Verificar se a prévia aparece e o disparo físico funciona.
4. Fotografar, conferir arquivo e testar salvar em Fotos.
5. Registrar qualquer erro de TypeScript ou da API; corrigir antes de usar em produção.

## Referências
- https://scriptingapp.github.io/TestFlight/guide/Camera%20Control/Camera%20Control%20Overview/
- https://scriptingapp.github.io/guide/Device%20Capabilities/AVCaptureSession%20%26%20Camera%20Control/Quick%20Start/
- https://github.com/Sagittaryuz/development-standards/blob/main/GIT-FIRST.md
