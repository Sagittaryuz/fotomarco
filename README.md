# Momentra · 0.4.0

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

## Formato da câmera 0.3.2

Layout ajustado à referência visual fornecida: fundo preto, visor retangular grande sem cantos arredondados, ícones superiores, miniatura e botão salvar ao lado do obturador circular branco. A geometria acompanha 4:3/16:9 e orientação em foto; vídeo usa visor 16:9, sem promessa de campo de visão idêntico ao arquivo gravado. A prévia da foto usa um painel central, mantendo parte da câmera ao vivo visível para Camera Control. Os quatro controles superiores e os controles laterais anteriores foram preservados; o seletor continua abaixo do obturador conforme o pedido específico anterior.

Não foram inventados zoom/lentes 0.5×/4×/8×, filtros ou modos Square da imagem. Mapa/timestamp/logotipo agora aparecem também ao vivo no modo Câmera, conforme as posições configuradas. A referência pessoal não integra os arquivos públicos. `node tools/preview-layout.cjs` gera diagramas geométricos sintéticos, não screenshots nativos nem prova da aparência Liquid Glass.

## Sobreposição ao vivo 0.3.3

No modo Câmera, com Carimbo ligado, o visor desenha o mesmo conjunto de data/hora/localização, mapa e logotipo usado na foto final, respeitando fonte, escala e cantos. O relógio atualiza a cada segundo; logo usa o arquivo escolhido no perfil. Sem logo/mapa configurados, nenhum substituto é inventado.

GPS continua opt-in, com atualização a cada 30 segundos enquanto a câmera está ativa e não ocupada. Dados com mais de 60 segundos saem do visor; GPS desligado/indisponível aparece como texto. Mapa e endereço só aparecem associados ao mesmo fix válido, e respostas atrasadas de configurações/localizações anteriores são descartadas. Sem rede/mapa, timestamp e captura continuam funcionando.

O mapa disponível e correspondente é reaproveitado no disparo. A foto congela hora, GPS e preferências no instante real da captura (depois do temporizador). A sobreposição some ao revisar uma foto e no modo Vídeo, que não recebe carimbo. A prévia de tela e a foto compartilham o desenho, mas paridade exata de pixels/campo de visão requer teste físico.

**Provedor de mapas atual: Apple.** Login Google opcional foi integrado na 0.3.4, somente para identidade. Google Maps continua indisponível: envolve billing e restrições de incorporação da imagem. Não foi ativada cobrança. Veja [condições Google](CLOUD_STORAGE.md).

## Configurações · 0.3.6

Página clara com cartões brancos, ícones circulares coloridos de 44 pt e botão Voltar à câmera. Interruptores controlam carimbo, GPS, mapa e permissão de salvamento manual na galeria, sem representar o estado das permissões do iOS. Fontes, formatos, cantos e escala continuam selecionáveis. Conta Google foi preservada; Google Fotos e somente nuvem aparecem apenas como aviso de indisponibilidade, sem botão inoperante. A câmera permanece escura.

## Controles superiores e configurações

- **Flash:** Ligado, Automático ou Desligado, com a opção atual marcada no popup. Amarelo indica modo armado (ligado/automático), não confirmação de que o LED disparou. O resultado depende do hardware e da decisão do iPhone no automático.
- **Temporizador:** desligado, 3 ou 10 segundos. Toque novamente no obturador durante a contagem para cancelar. Hora/GPS são registrados no disparo real, após a contagem.
- **Proporção:** 4:3 ou 16:9 (invertidas em retrato). Recorte central da foto final, inclusive sem carimbo; original inteiro preservado. O visor acompanha a proporção selecionada com preenchimento central; correspondência exata do campo de visão com a captura ainda requer teste físico.
- **Configurações:** página própria com fonte Sistema/Serifada/Monoespaçada; data/hora numéricas ou data com mês por extenso e hora h/min/s; timestamp nos quatro cantos. Data, hora e localização permanecem no mesmo conjunto. GPS desligado/indisponível aparece como texto, sem coordenadas falsas.
- Na mesma página: GPS e mapa opcionais; tamanho do mapa pequeno/médio/grande (14/22/30% do menor eixo da foto), canto do mapa e canto da imagem/logotipo independentes. Elementos que colidem são empilhados para dentro, preservando legibilidade. Tamanho do mapa é tamanho visual, não zoom geográfico.

## Interface Liquid Glass e vídeo

Os controles usam **Liquid Glass nativo regular**, com ícones em superfícies circulares de 44 pt e grupos laterais gerenciados por `GlassEffectContainer`. A versão 0.3.5 sobrepõe toolbar e status ao visor para maximizar sua área, preservando a proporção escolhida e os controles inferiores. O obturador permanece maior. A miniatura/prévia fica à esquerda do obturador e Salvar à direita; Exportar e Fechar ficam na faixa de status. Os dois modos são os últimos elementos da tela. Painéis laterais compactos de ícones rolam em telas baixas. Estados também têm texto e descrições para VoiceOver, não apenas cor.

No modo Vídeo, toque no círculo vermelho para iniciar e no quadrado para parar. Câmera e microfone são solicitados pelo iOS. A sessão de fotos é encerrada antes da sessão de vídeo, evitando duas câmeras concorrentes. O arquivo `.mov` fica no Momentra; **Salvar vídeo** envia ao Fotos apenas quando solicitado. O último vídeo fica acessível após reabrir e voltar ao modo Vídeo; os últimos 50 vídeos ficam selecionáveis em Recentes no modo Vídeo, e todos os arquivos permanecem na pasta local. **Vídeo não recebe carimbo, GPS ou mapa.** Os controles exclusivos de foto ficam desativados nesse modo.

O código usa `AVCaptureMovieFileOutput` e `Photos.saveVideo` documentados, com testes de fluxo simulados. **Gravação, áudio, material de vidro, animação do seletor, contraste e acessibilidade precisam de homologação física no iPhone.** Não há alegação de equivalência visual exata ao app Câmera nem fallback Liquid Glass documentado para iOS anterior a 26.

## GPS, mapa e privacidade

GPS começa **desligado**. Ative no botão GPS quando quiser localizacão no carimbo. O aplicativo solicita acesso no iPhone e usa o fix disponível no instante do disparo, com idade máxima de 60 segundos. Nunca usa a localização da conversa nem substitui um GPS ausente por coordenadas inventadas.

Endereço e mapa de satélite são opcionais e dependem dos serviços Apple/rede. A foto não é enviada ao serviço de mapas. Consultas têm tempo limite e geocodificação é limitada a uma por minuto. Sem mapa/endereço, a foto continua disponível com coordenadas quando existentes. GPS ausente fica identificado no carimbo.

O JPEG com carimbo tem até **3072 px no maior lado**, qualidade 94%, sem ampliar imagens menores. É uma composição visual, **não uma promessa de EXIF GPS preservado**. O original permanece intacto, com os metadados que a câmera efetivamente produziu. A data do carimbo inclui o fuso local do aparelho.

## Botão físico e Tela Bloqueada

O script inicia uma câmera customizada quando aberto normalmente. A Tela Bloqueada pode usar a câmera nativa do Scripting e entregar arquivos depois. Momentra processa fotos recebidas, conserva a hora fornecida pelo lote e não usa o GPS atual para simular a localização daquela captura. Lotes repetidos são deduplicados por lote/arquivo. Vídeos permanecem nos Arquivos Capturados do Scripting e não recebem carimbo nesta versão.

## Galeria e nuvem

Em Configurações, **Cópia na galeria Fotos → Não salvar na galeria** bloqueia o salvamento de fotos e vídeos no Fotos. Arquivos continuam guardados **localmente no Momentra**; cópias anteriores não são apagadas. Isso não equivale a somente nuvem.

O login Google opcional identifica a conta. Google Fotos pessoal é uma integração separada, com consulta de disponibilidade, consentimento e envio manual. A API permite listar apenas conteúdo criado pelo próprio aplicativo e não é destinada a dados internos empresariais. Sem ativação do serviço ou sessão válida, os controles informam a indisponibilidade. Consulte [avaliação e próximos passos](CLOUD_STORAGE.md).

## Conta Google · 0.3.4

Configurações oferece Entrar com Google, reconexão e desconexão local. Na primeira abertura há um acesso opcional às configurações: não inicia consentimento automaticamente nem bloqueia a câmera. A integração solicita somente `openid email profile`; nenhuma foto ou localização é enviada ao Google por este login.

Backend dedicado publicado em `https://momentra-auth.mrpires72.workers.dev`, com retorno HTTPS fixo e ponte para o Scripting. O segredo Google fica no servidor; PKCE S256, state e envelopes autenticados com validade limitada vinculam a troca. Tokens ficam no Keychain local por script, não no Storage ou no repositório. Não há renovação automática: sessão expirada requer novo login. Desconectar remove a sessão local, mas não revoga a autorização na conta Google.

Após autorizar no Google, a página HTTPS apresenta **Voltar ao Momentra**. Toque nesse link para retornar ao Scripting no iPhone; ele expira em até dois minutos. Se expirar, reinicie o login.

Na 0.3.7, o backend foi testado com uma conta real no PC: consentimento Google, callback HTTPS200, state correspondente, troca de token pelo Worker200 e identidade verificada200; sem refresh token, e repetição do código rejeitada400. Isso não testa o retorno ao Scripting nem o Keychain no iPhone, que continuam pendentes de validação física. O serviço utiliza quota gratuita compartilhada da conta Cloudflare, sem garantia de disponibilidade, e limita requisições por IP. Login não significa backup, acesso ao Google Fotos ou Google Maps.

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
node --test tests/google_auth.cjs
node --test backend/worker.test.mjs
```

- Sintaxe de todos os módulos TSX, manifesto e TypeScript estrito do núcleo puro.
- 47 verificações de núcleo/layout/renderização sintética.
- 30 fluxos do aplicativo com APIs nativas simuladas, incluindo erros, cancelamento, eventos físicos repetidos, encerramento, orientação e entrega de fotos da câmera nativa.
- 14 testes isolados do módulo Google e 31 do backend OAuth, com dados sintéticos.
- As imagens geradas em `.validation` são **sintéticas**, não screenshots do iOS.
- **Não executado aqui:** importação no iPhone, tipagem integral contra os arquivos `.d.ts` sincronizados pelo aparelho, captura real, permissões iOS, Liquid Glass real, mapa Apple e salvamento real no Fotos.

Ver [DEVELOPMENT.md](DEVELOPMENT.md) para decisões e checklist de homologação.


## 0.4.0 · Google Fotos pessoal e diagnóstico integrado

Configurações → Conta → Google Fotos pessoal permite consultar disponibilidade, autorizar separadamente o acesso mínimo e enviar manualmente a foto selecionada. A declaração de finalidade pessoal é por foto, não pelo nome do perfil. Dados internos empresariais não devem ser enviados. O carimbo, incluindo localização visível, acompanha a imagem final; a confirmação informa a conta destinatária.

A lista mostra apenas JPEGs criados pelo Momentra, com miniaturas, paginação e renovação das URLs pelo ID. Não é acesso à biblioteca inteira. Envio limitado a JPEG20MB; vídeos não são enviados. Upload ambíguo impede reenvio automático; sucesso exige criação individual e consulta do item. Originais permanecem locais. **Não é modo somente nuvem**, e miniaturas podem usar cache do host. A API consome o espaço existente da conta Google, sem comprar armazenamento.

O login de identidade continua independente e a câmera funciona sem ele. Photos usa outro consentimento/token, com escopos mínimos e sessão expirada exigindo reconexão. A aplicação Google em Testing só admite usuários autorizados para teste. O botão de privacidade abre o aviso do serviço. Nada é enviado automaticamente ao abrir o app, fotografar ou entrar na conta.

Menu GPS → Abrir localização no Google Maps é uma opção externa, com confirmação antes de enviar as coordenadas. **Não substitui o mapa Apple no carimbo.** Mapa Google incorporado permanece pendente: exige billing e compatibilidade de licença para exportação permanente, não resolvidos dentro da condição custo zero.

Configurações → Conta → Exibir diagnóstico local reúne versão, disponibilidade de APIs e resultados reais obtidos naquele aparelho. Não transmite relatório, localização, foto, e-mail ou token. “API disponível” não significa recurso testado. Diagnóstico de captura/composição/vídeo/GPS/mapa/OAuth é registrado somente após resultado da operação, com falhas sanitizadas.

### Uma validação consolidada no iPhone

Após a versão integrada estar publicada, importar uma única vez. Exercitar foto4:3/carimbo/mapa/logotipo, temporizador/flash, vídeo com áudio e parada, configuração e retorno Google. Photos deve ser autorizado explicitamente; qualquer envio real será escolhido pelo usuário. Ao final conferir o diagnóstico local. Testes de mocks, CI e backend real no PC não substituem essa verificação nativa. Sem iPhone conectado ao servidor oficial Scripting não existe execução remota comprovada nesta entrega.
