# Momentra · 0.2.0

Câmera para **Scripting PRO no iPhone**, com controles laterais, padrões editáveis e carimbo gravado na foto.

## Instalar ou atualizar

No Scripting, use **Importar Scripts Remotos** com:

```
https://github.com/Sagittaryuz/momentra/tree/camera-mvp
```

A branch de distribuição não contém `/` no nome e a raiz contém `script.json` e `index.tsx`. O repositório é público, conforme solicitado. Use uma versão atual do Scripting PRO com AVCaptureSession, Canvas, ImageRenderer e MapSnapshotter. **O código foi validado localmente; a importação e as APIs nativas ainda precisam ser verificadas no iPhone.**

Após a importação, abra Momentra. Permita acesso à câmera quando o iOS solicitar. Não substitua sua configuração funcional do botão de câmera antes de testar abrir, fotografar e salvar. Depois da validação, selecione Momentra em **Scripting → Mais → Scripts padrão → Camera Control**; a seleção do app no botão físico continua nos Ajustes do iOS.

## Usar

- **Esquerda:** alternar HAMOA / PIRESCO / PESSOAL; editar o padrão; ligar/desligar o carimbo.
- **Padrão:** título, observação/serviço, logotipo escolhido em Arquivos, posição no topo/rodapé e tamanho compacto/normal. Cada perfil preserva seu próprio título, observação e logotipo. Posição/tamanho são preferências gerais.
- **Direita:** GPS/mapa, lanterna e fotos recentes.
- **Fotografar:** dispara na tela. O evento físico usa a mesma proteção contra disparos duplicados.
- **Prévia:** mostra a última foto em um painel, sem desmontar o visor ativo.
- **Salvar:** grava a foto final no Fotos. Não salva automaticamente e evita repetição de um salvamento confirmado.
- **Exportar:** foto final, original sem carimbo ou registro JSON para Arquivos.

O título e a observação se referem às próximas fotos, não alteram registros antigos. Textos longos são limitados com reticências para não invadir o mapa; o registro mantém os dados de captura. Logotipos não são incluídos de terceiros: selecione o arquivo que deseja usar. A proporção da marca é preservada.

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
- 26 verificações de núcleo/layout/renderização sintética.
- 9 fluxos do aplicativo com APIs nativas simuladas, incluindo erros, cancelamento, eventos físicos repetidos, encerramento, orientação e entrega de fotos da câmera nativa.
- As imagens geradas em `.validation` são **sintéticas**, não screenshots do iOS.
- **Não executado aqui:** importação no iPhone, tipagem integral contra os arquivos `.d.ts` sincronizados pelo aparelho, captura real, permissões iOS, Liquid Glass real, mapa Apple e salvamento real no Fotos.

Ver [DEVELOPMENT.md](DEVELOPMENT.md) para decisões e checklist de homologação.
