# Momentra iOS · Guia de desenvolvimento

Este guia descreve a versão nativa em SwiftUI. O código de produção do app fica em `feat/storage-integration`, o código do instalador em `fix/ota-download-recovery` e os testes de interface em `qa/momentra-016-gallery`. O site institucional tem repositório próprio em `Sagittaryuz/momentra-site`. Comece pelo estado do Git, pelo diff local e pela última tag estável. Preserve revisões em andamento usando um worktree quando necessário.

## Construção e componentes

A câmera inicial e as opções gerais são as referências aprovadas. Nos painéis
internos, use a superfície arredondada de `GalleryControlSurface`, com Liquid
Glass no iOS 26 e material do sistema nas versões anteriores. Preserve as
funções, os gestos e a semântica acessível de cada controle ao reaplicar o estilo.

| Área | Código e recursos |
| --- | --- |
| Projeto Xcode | `project.yml` define fontes, dependências, versão e builds. `Configuration/` mantém identificadores e configurações declarativas. |
| Câmera | `CameraScreen.swift`, `CameraService.swift`, `CameraPreview.swift` e `MomentraCaptureExtension/` compartilham a prévia nativa. |
| Galeria | `UnifiedGallery.swift`, `GalleryItem.swift` e `GalleryGrid.swift` mantêm origens, filtros, quadrados, ordem, seleção e miniaturas. |
| Visualizador e editor | `MomentraGalleryDetail.swift`, `GalleryPhotoViewport.swift`, `GalleryDetailControls.swift` e `MomentraPhotoEditor.swift`. |
| Busca e compartilhamento | `GalleryContentSearch.swift`, `GallerySelectionControls.swift` e `GalleryQuickShare.swift`. |
| Contas, filas e arquivos | `CloudArchiveAccounts.swift`, `CloudArchiveJournal.swift`, `CloudArchiveDelivery.swift`, `GoogleDriveArchive.swift` e `OneDriveArchive.swift`. |
| Carimbo e perfis | `StampProfilesStore.swift`, `StampLayoutEditor.swift`, `PhotoProfileIndex.swift` e arquivos de renderização do carimbo em `Momentra/`. |
| Elementos visuais | `Momentra/Assets.xcassets` mantém ícones, marcas dos provedores, cores e imagens locais. O repositório do site mantém ilustrações, logos e estilos da landing page. |

No macOS, gere o projeto a partir da definição versionada.

```sh
cd native-ios
xcodegen generate
xcodebuild -project Momentra.xcodeproj -scheme Momentra -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO test
```

O nome do simulador pode variar. Consulte `xcrun simctl list devices available` e use a mesma configuração ao comparar versões.

## Padrões de interface

- Use a identidade do Momentra. Fundo preto na galeria e no visualizador, amarelo como destaque, ícones já disponíveis e rótulos em português. Preserve as marcas de Google Drive e OneDrive.
- Reuse `GalleryControlSurface(rounded: true)` nas ações da galeria. Ícones ficam em superfícies redondas de pelo menos 44 pt. Ações de texto e grupos de botões usam cápsulas. Use Liquid Glass nativo onde estiver disponível e material padrão nas versões anteriores.
- Preserve miniaturas quadradas e a foto inteira no visualizador inicial. Toque simples alterna os controles. Dois toques alternam a aproximação com controles ocultos. Pinça ajusta o zoom. O X da busca retorna à aba e aos filtros de origem.
- Deslizar para baixo no visualizador fecha a mídia e volta à grade na mesma aba. Para voltar à câmera, feche a galeria pela própria grade.
- O compartilhamento usa o painel do iOS. Só abra o app de destino após a confirmação de conclusão sem erro e quando houver um link de abertura conhecido. O WhatsApp usa `whatsapp://app` e recebe apenas o link de abertura nesse passo.
- Em Capturas, mostre arquivos do Momentra e cópias do Fotos com vínculo confirmado pelo índice do aplicativo. Os filtros mudam a projeção da galeria. Itens com envio pendente mantêm as proteções do arquivo e da fila.
- Reúna o armazenamento em uma faixa compacta acima da grade. Mostre cada origem em uma cápsula com ícone, trilho e percentual real. Para várias contas, use rolagem horizontal de altura fixa. A lixeira local conserva o item por 30 dias. Use os dados reais do provedor para indicar a expiração de itens remotos.

## Processamento e validação

- Mantenha captura e ajustes de lente na fila da sessão AVFoundation. Converta o ponto do toque pela camada de prévia. Mostre o marcador depois que foco ou exposição aceitar o ponto. Teste câmera frontal, traseira, troca de lente e o modo de captura bloqueada no iPhone.
- Descarregue codificação, mapa, miniaturas e persistência da interface. Reuse miniaturas por conta e revisão. Pesquise no Fotos pelos identificadores do Momentra quando a aba é Capturas. Evite percorrer o armazenamento inteiro para calcular o uso do volume.
- Use `GalleryThumbnailCache` para miniaturas. O cache usa o diretório Caches do iOS, com alvo de 12 MiB de memória e limites de 32 MiB e 400 arquivos no disco. As chaves locais incluem tamanho e modificação. As chaves remotas incluem conta, arquivo e revisão. O cache é descartável e separado das prévias offline que a fila de envio preserva.
- Carregue a prévia ampliada somente para a página ativa. Durante edição, permita uma renderização de prévia em curso e retenha apenas o ajuste pendente mais recente. A exportação usa o arquivo integral.
- Pause reconhecimento quando a superfície da câmera estiver oculta ou a gravação estiver em andamento. Ative sensores quando a função que os usa estiver visível e habilitada.
- Compilação para simulador, testes nativos e testes de interface são verificações distintas. Para analisar desempenho, compare a mesma versão de simulador, o mesmo lote de mídias e o mesmo gesto. Use Instruments em aparelho para medir memória, quadros atrasados, CPU e rede. Registre o que foi realmente observado.

## Distribuição e recuperação

1. Gere o IPA no workflow `Validate native iOS draft` com `signing_candidate=true`. Valide a revisão, a versão, o build, o identificador, as extensões e as configurações de provedores.
2. Assine pela sessão autorizada do Signulous. Confira assinatura, identidade do pacote e integridade antes de publicar.
3. Envie os pacotes ao Drive privado e acrescente cada link, com build, commit e situação, em `Momentra - Links dos IPAs.md` na raiz do Meu Drive. Preserve as versões anteriores.
4. Publique pelo instalador privado existente. Confira o manifesto, o tamanho real, a retomada por intervalo, o SHA-256 do pacote entregue e a recusa de acesso anônimo. Só depois crie a tag estável `native-ios-vX.Y.Z` e confira o site em produção.
5. Para cada entrega relevante, atualize este guia e guarde um Git bundle verificável do app e do site no backup privado. O bundle do app deve preservar o desenvolvimento ativo, a revisão da distribuição, os testes de interface e as tags estáveis.

Recupere um Git bundle com `git clone caminho.bundle Momentra` e selecione a branch necessária. Valide o pacote com `git bundle verify` e compare os hashes registrados. Mantenha no repositório os arquivos que podem ser reutilizados. Perfis de assinatura, credenciais, identificadores do aparelho e fotos pessoais ficam fora da documentação e dos backups de desenvolvimento.

O repositório é a origem do código. O Drive conserva documentação, recursos versionados, histórico e pacotes.
