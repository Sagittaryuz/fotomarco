# Momentra · 0.3.0

Câmera para **Scripting PRO no iPhone**, com controles laterais, padrões editáveis e carimbo gravado na foto.

## Instalar ou atualizar

No Scripting, use **Importar Scripts Remotos** com:

```
https://github.com/Sagittaryuz/momentra/tree/camera-mvp
```

A branch de distribuição não contém `/` no nome e a raiz contém `script.json` e `index.tsx`. O repositório é público, conforme solicitado. Requer **iOS 26 ou posterior** para Liquid Glass. Use uma versão atual do Scripting PRO com AVCaptureSession, Canvas, ImageRenderer e MapSnapshotter. **O código foi validado localmente; a importação e as APIs nativas ainda precisam ser verificadas no iPhone.**

Após a importação, abra Momentra. Permita acesso à câmera quando o iOS solicitar. Não substitua sua configuração funcional do botão de câmera antes de testar abrir, fotografar e salvar. Depois da validação, selecione Momentra em **Scripting → Mais → Scripts padrão → Camera Control**; a seleção do app no botão físico continua nos Ajustes do iOS.

## Usar

- **Esquerda:** escolher HAMOA / PIRESCO / PESSOAL; editar o padrão; ligar/desligar o carimbo.
- **Padrão:** título, observação/serviço, logotipo escolhido em Arquivos e tamanho compacto/normal. Cada perfil preserva seu próprio título, observação e logotipo.
- **Direita:** GPS/mapa, lanterna e fotos recentes.
- **Seletor inferior:** Vídeo à esquerda, Câmera à direita, em controle segmentado nativo. Acima, apenas o obturador circular.
- **Fotografar:** o círculo branco dispara na tela. O evento físico usa a mesma proteção contra disparos duplicados.
- **Prévia:** mostra a última foto em um painel, sem desmontar o visor ativo.
- **Salvar:** grava a foto final no Fotos. Não salva automaticamente e evita repetição de um salvamento confirmado.
- **Exportar:** foto final, original sem carimbo ou registro JSON para Arquivos.

O título e a observação se referem às próximas fotos, não alteram registros antigos. Textos longos são limitados com reticências para não invadir o mapa; o registro mantém os dados de captura. Logotipos não são incluídos de terceiros: selecione o arquivo que deseja usar. A proporção da marca é preservada.

## Controles superiores e configurações

- **Flash:** Ligado, Automático ou Desligado, com a opção atual marcada no popup. Amarelo indica modo armado (ligado/automático), não confirmação de que o LED disparou. O resultado depende do hardware e da decisão do iPhone no automático.
- **Temporizador:** desligado, 3 ou 10 segundos. Toque novamente no obturador durante a contagem para cancelar. Hora/GPS são registrados no disparo real, após a contagem.
- **Proporção:** 4:3 ou 16:9 (invertidas em retrato). Recorte central da foto final, inclusive sem carimbo; original inteiro preservado. O visor ao vivo ainda exibe o enquadramento da câmera, portanto a foto final 16:9 pode conter menos área.
- **Configurações:** página própria com fonte Sistema/Serifada/Monoespaçada; data/hora numéricas ou data com mês por extenso e hora h/min/s; timestamp nos quatro cantos. Data, hora e localização permanecem no mesmo conjunto. GPS desligado/indisponível aparece como texto, sem coordenadas falsas.
- Na mesma página: GPS e mapa opcionais; tamanho do mapa pequeno/médio/grande (14/22/30% do menor eixo da foto), canto do mapa e canto da imagem/logotipo independentes. Elementos que colidem são empilhados para dentro, preservando legibilidade. Tamanho do mapa é tamanho visual, não zoom geográfico.

## Interface Liquid Glass e vídeo

Dois painéis laterais usam o material **Liquid Glass nativo regular**, gerenciado por `GlassEffectContainer`. Cada painel tem uma única superfície de vidro, com botões independentes dentro: não é blur simulado nem vidro sobre vidro. Ações de foto (Prévia, Salvar, Exportar) ficam acima do obturador; os dois modos são os últimos elementos da tela. Painéis laterais rolam em telas baixas. Estados também têm texto e descrições para VoiceOver, não apenas cor.

No modo Vídeo, toque no círculo vermelho para iniciar e no quadrado para parar. Câmera e microfone são solicitados pelo iOS. A sessão de fotos é encerrada antes da sessão de vídeo, evitando duas câmeras concorrentes. O arquivo `.mov` fica no Momentra; **Salvar vídeo** envia ao Fotos apenas quando solicitado. O último vídeo fica acessível após reabrir e voltar ao modo Vídeo; os últimos 50 vídeos ficam selecionáveis em Recentes no modo Vídeo, e todos os arquivos permanecem na pasta local. **Vídeo não recebe carimbo, GPS ou mapa.** Os controles exclusivos de foto ficam desativados nesse modo.

O código usa `AVCaptureMovieFileOutput` e `Photos.saveVideo` documentados, com testes de fluxo simulados. **Gravação, áudio, material de vidro, animação do seletor, contraste e acessibilidade precisam de homologação física no iPhone.** Não há alegação de equivalência visual exata ao app Câmera nem fallback Liquid Glass documentado para iOS anterior a 26.

## GPS, mapa e privacidade

GPS começa **desligado**. Ative no botão GPS quando quiser localizacão no carimbo. O aplicativo solicita acesso no iPhone e usa o fix disponível no instante do disparo, com idade máxima de 60 segundos. Nunca usa a localização da conversa nem substitui um GPS ausente por coordenadas inventadas.

Endereço e mapa de satélite são opcionais e dependem dos serviços Apple/rede. A foto não é enviada ao serviço de mapas. Consultas têm tempo limite e geocodificação é limitada a uma por minuto. Sem mapa/endereço, a foto continua disponível com coordenadas quando existentes. GPS ausente fica identificado no carimbo.

O JPEG com carimbo tem até **3072 px no maior lado**, qualidade 94%, sem ampliar imagens menores. É uma composição visual, **não uma promessa de EXIF GPS preservado**. O original permanece intacto, com os metadados que a câmera efetivamente produziu. A data do carimbo inclui o fuso local do aparelho.

## Botão físico e Tela Bloqueada

O script inicia uma câmera customizada quando aberto normalmente. A Tela Bloqueada pode usar a câmera nativa do Scripting e entregar arquivos depois. Momentra processa fotos recebidas, conserva a hora fornecida pelo lote e não usa o GPS atual para simular a localização daquela captura. Lotes repetidos são deduplicados por lote/arquivo. Vídeos permanecem nos Arquivos Capturados do Scripting e não recebem carimbo nesta versão.

## Armazenamento e recuperação

- Originais, JPEGs finais e registros JSON ficam na pasta `Momentra` do armazenamento de documentos do Scripting.
- A lista guarda as últimas 50 referências; o menu exibe as 12 mais recentes. Os arquivos não são excluídos automaticamente.
- Falha no carimbo preserva o original e informa que ele está sem carimbo.
- Falha/negativa do Fotos mantém a cópia local e permite tentar salvar novamente.
- Prefira exportar os arquivos importantes antes de remover o script ou o Scripting.

## Atualizações e rollback

A fonte é o GitHub. Use a atualização remota nativa do Scripting na tela do script; aplicação automática depende da opção global do aplicativo, com intervalo mínimo de 30 minutos. Não há token no código nem um atualizador que execute conteúdo baixado por conta própria.

Para voltar ao protótipo anterior, o commit `ecc1c2b` permanece no histórico. Não remova seus arquivos locais para atualizar. O protótipo não aplicava carimbo, GPS nem mapa.

## Validação

```sh
npm ci --ignore-scripts
npm run check
npm test
```

- Sintaxe de todos os módulos TSX, manifesto e TypeScript estrito do núcleo puro.
- 44 verificações de núcleo/layout/renderização sintética.
- 19 fluxos do aplicativo com APIs nativas simuladas, incluindo erros, cancelamento, eventos físicos repetidos, encerramento, orientação e entrega de fotos da câmera nativa.
- As imagens geradas em `.validation` são **sintéticas**, não screenshots do iOS.
- **Não executado aqui:** importação no iPhone, tipagem integral contra os arquivos `.d.ts` sincronizados pelo aparelho, captura real, permissões iOS, Liquid Glass real, mapa Apple e salvamento real no Fotos.

Ver [DEVELOPMENT.md](DEVELOPMENT.md) para decisões e checklist de homologação.
