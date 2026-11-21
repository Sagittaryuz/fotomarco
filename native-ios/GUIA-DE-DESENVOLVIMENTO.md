# Fotomarco iOS · Guia de desenvolvimento

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

No macOS, gere o projeto Fotomarco a partir da definição versionada. A mudança de nome não altera o esquema interno Momentra, o produto Momentra.app, o bundle ID, os callbacks ou o contrato de distribuição do instalador privado.

```sh
cd native-ios
xcodegen generate
xcodebuild -project Fotomarco.xcodeproj -scheme Momentra -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO test
```

O nome do simulador pode variar. Consulte `xcrun simctl list devices available` e use a mesma configuração ao comparar versões.

## Padrões de interface

- Use a identidade do Momentra. Fundo preto na galeria e no visualizador, amarelo como destaque, ícones já disponíveis e rótulos em português. Preserve as marcas de Google Drive e OneDrive.
- Reuse `GalleryControlSurface(rounded: true)` nas ações da galeria. Ícones ficam em superfícies redondas de pelo menos 44 pt. Ações de texto e grupos de botões usam cápsulas. Use Liquid Glass nativo onde estiver disponível e material padrão nas versões anteriores.
- Sobreponha os controles inferiores à grade para que o Liquid Glass refrate as miniaturas atrás deles. Reserve a altura dos controles como margem de rolagem para deixar a última fileira acessível.
- Preserve miniaturas quadradas e a foto inteira no visualizador inicial. Toque simples alterna os controles. Dois toques alternam a aproximação com controles ocultos. Pinça ajusta o zoom. O X da busca retorna à aba e aos filtros de origem.
- Escreva as datas das seções por extenso, seguidas de ` · ` e do dia da semana. No dia atual, mantenha também o prefixo `Hoje · `.
- Deslizar para baixo no visualizador fecha a mídia e volta à grade na mesma aba. Para voltar à câmera, feche a galeria pela própria grade.
- Tocar em Capturas, Favoritos ou Lixeira leva à fileira mais recente da aba, inclusive ao tocar novamente na aba ativa. Preserve os filtros aplicados.
- Na grade, arraste para a esquerda sobre as fotos ou para baixo pelo cabeçalho para voltar à câmera. Anime a passagem com desfoque progressivo e respeite Reduzir Movimento.
- O painel de compartilhamento do iOS informa a conclusão da ação. Após conclusão sem erro, restaure a superfície de origem. No visualizador, mantenha a foto aberta e feche os painéis de compartilhamento. Na grade, encerre a seleção em lote e preserve a aba. Preserve o visualizador e a seleção em caso de cancelamento ou erro. Use a ação Copiar para verificar o retorno no simulador e teste extensões externas no iPhone.
- Em Editar vídeo, use o perfil associado à gravação e a mesma composição da exportação na prévia. Se o carimbo já estiver gravado em uma cópia local, reproduza essa cópia. Para aplicar um carimbo novo, preserve o original e exporte uma cópia interna.
- Na câmera, o toque simples na miniatura abre Capturas. O toque prolongado abre o painel do iOS com apenas o arquivo integral da foto exibida. A miniatura conserva a identidade do arquivo local ou da entrega verificada na nuvem.
- O seletor Foto/Vídeo usa a mesma folga nos quatro lados da cápsula. A pinça no visor ajusta o zoom de Foto e Vídeo sem abrir o leque. Mostre o zoom selecionado em amarelo, inclusive valores intermediários.
- Centralize o valor de zoom escolhido no eixo do obturador. Entre dois presets, o valor ocupa o slot do preset inferior e mantém os demais botões na ordem.
- Ao abrir o app ou voltar ao primeiro plano, consulte a versão publicada no instalador privado quando houver ativação. O botão do aviso e o botão em Sobre usam o mesmo fluxo autorizado de instalação do iOS.
- Em Capturas, mostre arquivos do Momentra e cópias do Fotos com vínculo confirmado pelo índice do aplicativo. Os filtros mudam a projeção da galeria. Itens com envio pendente mantêm as proteções do arquivo e da fila.
- Reúna as cópias com a mesma identidade de captura e a mesma versão em uma miniatura. Use selos de origem no canto superior direito, com um por conta remota e selos distintos para arquivos do Momentra e do Fotos quando ambos estiverem presentes. Preserve a distinção entre original e cópia processada e limite a exclusão à cópia exibida.
- Reúna o armazenamento em uma faixa compacta acima da grade. Mostre cada origem em uma cápsula com ícone, trilho e percentual real. Para várias contas, use rolagem horizontal de altura fixa. A lixeira local conserva o item por 30 dias. Use os dados reais do provedor para indicar a expiração de itens remotos.
- Mostre a última capacidade válida de cada conta e do iPhone em Capturas, Favoritos e Lixeira enquanto consulta os valores em segundo plano. A linha fina sob a faixa aparece durante a sincronização e some quando as consultas terminam.
- Em Capturas, arrastar para além da última fileira pede uma nova consulta de catálogo e capacidade. Limite a um pedido por gesto e preserve a grade durante a atualização.

## Processamento e validação

- Siga o [plano de otimização](PLANO-DE-OTIMIZACAO.md) para medir o gargalo, comparar revisões e priorizar câmera, galeria, memória e uso sustentado.
- Mantenha captura e ajustes de lente na fila da sessão AVFoundation. Converta o ponto do toque pela camada de prévia. Mostre o marcador depois que foco ou exposição aceitar o ponto. Teste câmera frontal, traseira, troca de lente e o modo de captura bloqueada no iPhone.
- Descarregue codificação, mapa, miniaturas e persistência da interface. Reuse miniaturas por conta e revisão. Pesquise no Fotos pelos identificadores do Momentra quando a aba é Capturas. Evite percorrer o armazenamento inteiro para calcular o uso do volume.
- Use `GalleryThumbnailCache` para miniaturas. O cache usa o diretório Caches do iOS, com alvo de 12 MiB de memória e limites de 32 MiB e 400 arquivos no disco. As chaves locais incluem tamanho e modificação. As chaves remotas incluem conta, arquivo e revisão. O cache é descartável e separado das prévias offline que a fila de envio preserva.
- Use `CloudGalleryCatalog` para hidratar a grade com a última lista completa do Google Drive e do OneDrive, separada por conta, em Application Support. Consulte a rede em segundo plano quando a lista tiver pelo menos cinco minutos ou quando houver alteração confirmada. Preserve a última lista completa se uma das páginas falhar. Guarde apenas metadados e mantenha essa pasta fora dos backups do iOS.
- Guarde as prévias de visualização em cache privado excluído do backup. O visualizador pode mostrar a miniatura em cache enquanto carrega a imagem maior. Limite o cache de visualização a 128 MiB, 128 arquivos e 4 MiB por arquivo. Separe as imagens de nuvem por conta e revisão. Compartilhamento e edição continuam usando o arquivo integral.
- Ao voltar de uma foto sem alterações, conserve a grade e a posição; não volte a ler o catálogo nem recrie as células. Mudanças reais continuam a solicitar atualização em segundo plano. Sobreponha a tira de miniaturas e a ação de texto ao visualizador, sem reservar altura adicional para elas.
- Ao alternar entre Foto e Vídeo, aplique uma transição breve no visor e uma expansão e retração no seletor, sem bloquear toques e respeitando Reduzir Movimento.
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
