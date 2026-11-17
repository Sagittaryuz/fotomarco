# Momentra nativo — desenvolvimento

Este diretório é uma migração em andamento para SwiftUI. O projeto Scripting permanece separado e não é substituído automaticamente. A versão nativa ainda não está pronta para uso, compilação distribuível ou instalação.

## Construção planejada

Em um Mac com Xcode e XcodeGen: `cd native-ios`, `xcodegen generate`, abra `Momentra.xcodeproj` e configure assinatura conforme a equipe/certificado autorizado. O identificador `br.com.momentra.camera` é provisório e precisa ser validado no processo de assinatura. Gerar um IPA e assiná-lo no Signulous são etapas distintas; nenhum certificado ou credencial deve ser salvo no repositório.

As preferências do Scripting ficam na área privada de outro aplicativo e não podem ser presumidas acessíveis pelo app nativo. A migração de dados e a compatibilidade da assinatura precisam ser implementadas e testadas. A localização é opcional e não deve ser inventada. Nenhuma integração em nuvem, envio de fotos ou leitura real do iPhone foi validada nesta migração.

O carimbo inicial é experimental: usa data e localização válida obtida antes do disparo, com precisão e altitude apenas quando informadas pelo sistema. Mapa e endereço são opções independentes, dependem de GPS habilitado e utilizam serviços da Apple; se alguma consulta falhar ou exceder oito segundos, a foto é salva com as demais informações. Três perfis nativos têm títulos e observações independentes; logos, importação das preferências anteriores e o carimbo completo ainda não foram migrados. A gravação de vídeo com áudio está em desenvolvimento e não recebe carimbo. A foto original e os vídeos são guardados na área privada do app; a cópia JPEG processada preserva apenas uma lista de metadados de câmera e adiciona GPS somente quando há leitura válida habilitada. Ela não preserva todos os metadados EXIF. A tela Originais oferece compartilhamento e nova tentativa de salvar no Fotos, mas ainda não foi testada em aparelho. Desinstalar o app pode remover os originais guardados nele.

A prévia em tela cheia e o carimbo ao vivo são experimentais: a proporção da prévia não garante que o enquadramento corresponda ao arquivo capturado. A proporção 4:3 ou 16:9 usa recorte central da foto; o original integral continua guardado. O endereço é obtido após o disparo. Tamanho, orientação, recorte e posição finais precisam de validação no iPhone antes de distribuição.
