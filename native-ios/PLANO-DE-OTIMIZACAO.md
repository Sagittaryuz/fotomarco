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

## Referências Apple

- [Especificações do iPhone 17 Pro](https://support.apple.com/en-us/125090)
- [ProMotion em iPhone e iPad](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays)
- [Chave de frequência de quadros no iPhone](https://developer.apple.com/documentation/bundleresources/information-property-list/cadisableminimumframedurationonphone)
- [Inicialização e prévia responsiva da câmera](https://developer.apple.com/documentation/avfoundation/building-a-responsive-camera-app-that-launches-quickly)
- [Frequências suportadas pelo formato ativo](https://developer.apple.com/documentation/avfoundation/avcapturedevice/activevideominframeduration)
- [Medição do tempo de abertura](https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time)
