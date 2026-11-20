# Plano de desempenho do Momentra iOS

## Objetivo e método

Manter a câmera e a galeria responsivas sem prejudicar captura, qualidade, segurança dos dados ou autonomia. Cada alteração deve partir de um gargalo observado, comparar a versão instalada e a candidata nas mesmas condições e registrar aparelho, iOS, versão, quantidade de mídias, condições térmicas e procedimento. Não há medições físicas de FPS, latência, energia ou memória neste estudo inicial.

## Diagnóstico inicial do código

- A câmera inicializa e chama `startRunning()` em fila serial própria. A prévia usa `AVCaptureVideoPreviewLayer`, sem conversão de cada quadro na interface. A sessão configura foto, vídeo e reconhecimento antes de iniciar; o custo relativo de cada saída ainda não foi medido.
- O reconhecimento usa fila de utilidade, descarta quadros atrasados e analisa no máximo uma vez por segundo quando habilitado. O efeito em CPU, temperatura e consumo com texto e QR ativados ainda precisa de medição.
- A galeria carrega catálogos e miniaturas em segundo plano e possui limites separados para miniaturas e prévias; originais e arquivos necessários à fila de envio não são caches descartáveis. A revisão 0.1.26 remove a releitura incondicional ao fechar o visualizador e conserva resultados já carregados quando a tarefa é recriada.
- O projeto não define `CADisableMinimumFrameDurationOnPhone`. Isso é uma oportunidade de teste para animações ProMotion, não comprovação de taxa atual ou de ganho. A taxa da tela, a da prévia capturada e a do vídeo gravado são grandezas diferentes.

## Sequência de trabalho

1. **Estabelecer linha de base no iPhone**: medir início frio, retomada, tempo até primeiro quadro da câmera, tempo até obturador disponível, interação ao voltar de fotos, abertura com cache frio/quente, quadros perdidos, memória, uso de CPU e temperatura. Repetir com mesmo cenário e conjunto de mídias; registrar mediana e distribuição, sem incluir dados pessoais.
2. **ProMotion**: verificar taxas efetivas de animações e rolagem em aparelho compatível e testar a chave do sistema em compilação isolada. Comparar fluidez, energia e temperatura. A tela do iPhone 17 Pro suporta até 120 Hz adaptativos, mas isso não fixa a frequência de exibição nem a taxa da câmera.
3. **Primeiro quadro**: medir a configuração das saídas de foto, vídeo e reconhecimento. Avaliar inicialização adiada das saídas, com verificações de disponibilidade das APIs, preservando captura imediata, botão físico, permissões, interrupções e gravação. Não ativar antes de testar em dispositivo real.
4. **Carga sustentada**: comparar prévia com reconhecimento desligado e ligado, em ambientes claros e escuros, após uso prolongado. Observar quadros descartados, pressão do sistema, temperatura e consumo. Ajustar frequência ou demanda somente se medições indicarem ganho sem perda funcional.
5. **Galeria e armazenamento**: medir retorno e abertura consecutiva, rolagem e crescimento do cache em bibliotecas pequenas e grandes, com nuvens conectadas e sem rede. Verificar invalidação por edição, exclusão, retorno do segundo plano e atualização externa; preservar conteúdo já exibido em falhas de rede.
6. **Aceite de cada versão**: comparar resultados antes/depois no mesmo aparelho; executar testes nativos e de interface, confirmar dados e assinatura, validar atualização sobre a versão instalada e registrar regressões, limitações e evidências antes da publicação estável.

## Investigação complementar — 0.1.26 (commit 99937dc)

- **Partida da câmera:** `CameraService.configure()` adiciona foto, filme e dados de reconhecimento antes de `startRunning()`, na fila serial da sessão. A saída de reconhecimento é adicionada mesmo quando sua conexão está desabilitada; ainda não sabemos quanto isso custa até o primeiro quadro. Compare o tempo de prévia com reconhecimento desligado e ligado, sem comprometer a disponibilidade imediata do obturador ou do vídeo.
- **Inicialização adiada:** segundo a Apple, um app vinculado ao SDK do iOS 26 ou posterior já pode adiar automaticamente saídas de foto e arquivo quando suportado. O padrão de `AVCaptureVideoDataOutput` é diferente, mesmo quando a prévia usa `AVCaptureVideoPreviewLayer`. Verificar o SDK efetivamente usado e as propriedades em execução no dispositivo antes de propor qualquer alteração; não assumir que adicionar explicitamente os mesmos valores padrão acelera o app. Testar também a prontidão de captura e a troca foto/vídeo.
- **Sincronização da grade:** `applyCloud` chama `updateProjection()` após a resposta; esta agrupa, filtra e ordena os itens, incrementa `projectionVersion`, e `GalleryGrid.updateUIView` invalida o layout e chama `reloadData()`. Isso pode acontecer mesmo quando o catálogo retornado é equivalente. É uma hipótese concreta de trabalho extra, não uma medição de travamento. Medir duração e número de atualizações com biblioteca grande e rede lenta; numa candidata, comparar estado visível completo, incluindo revisão, data, perfil, favoritos e origens agrupadas, antes de evitar uma atualização ou aplicar mudanças incrementais. Preservar seleção, posição de rolagem, edições e exclusões externas.
- **Caches:** a grade usa cache limitado em memória e disco; o visualizador usa outro cache, com limite de 128 MiB e imagens de prévia de até 1.800 pixels. As consultas da mesma chave compartilham a aquisição; leitura, decodificação e escrita do cache são serializadas pelo ator e merecem medição sob rolagem rápida. São prévias limitadas, não garantia de que o original esteja disponível offline. Arquivos originais e itens pendentes de envio não podem ser tratados como cache descartável.
- **Protocolo de comparação:** para abertura fria e quente registrar separadamente tempo até interface, primeiro quadro vivo e captura possível; para galeria, tempo até grade interativa e primeira foto nítida. Comparar mediana e dispersão após várias repetições nas mesmas condições, inclusive rede desligada, cache cheio, foto/vídeo, reconhecimento e temperatura. Medir quadros perdidos, memória e energia em aparelho real; o simulador não mede câmera física nem comprova 120 Hz. Não há resultados físicos registrados até esta revisão.

### Referência inicial no simulador

Em 20/11, o teste `testGalleryCatalogMeasurement` passou na revisão de app `99937dc`, em simulador iPhone 17 Pro, com três capturas de teste visíveis e 24 fotos pessoais fictícias excluídas de Capturas. Os três tempos entre o comando de toque do XCTest e a existência da grade foram 7.562, 1.876 e 1.904 ms (primeira abertura e duas reaberturas). O resultado inclui custo e espera da automação, não mede miniaturas nítidas nem câmera real, não representa bibliotecas grandes ou contas de nuvem, e não demonstra ganho frente a outra versão. Evidência: [execução 44665888313](https://github.com/Sagittaryuz/momentra/actions/runs/44665888313), anexo “Medição da galeria”. A compilação anterior dos testes utilizou Xcode 26.6 e SDK de simulador 26.5; não inferir por isso os padrões efetivos da compilação instalada sem verificar o artefato de dispositivo.

## Referências Apple

- [Especificações do iPhone 17 Pro](https://support.apple.com/en-us/125090)
- [ProMotion em iPhone e iPad](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays)
- [Chave de frequência de quadros no iPhone](https://developer.apple.com/documentation/bundleresources/information-property-list/cadisableminimumframedurationonphone)
- [Inicialização e prévia responsiva da câmera](https://developer.apple.com/documentation/avfoundation/building-a-responsive-camera-app-that-launches-quickly)
- [Inicialização adiada das saídas](https://developer.apple.com/documentation/avfoundation/avcaptureoutput/isdeferredstartenabled)
- [Frequências suportadas pelo formato ativo](https://developer.apple.com/documentation/avfoundation/avcapturedevice/activevideominframeduration)
- [Medição do tempo de abertura](https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time)
