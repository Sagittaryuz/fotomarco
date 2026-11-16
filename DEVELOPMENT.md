# Desenvolvimento e continuidade

## Pedido e origem

Marcos pediu uma interface para tirar fotos no Scripting PRO, com botões à esquerda e à direita para editar padrões; escolheu o nome Momentra. Em 16/11/2026 pediu concluir o desenvolvimento. A conversa anterior criou HAMOA/PIRESCO/PESSOAL e planejou carimbo, GPS, mapa e logotipo. O usuário pediu explicitamente deixar o repositório aberto; a orientação antiga de mantê-lo privado foi superada. Não criar outro repositório nem trocar a plataforma.

Fonte de requisitos: conversa “Encontrar aplicativo timestamp fotos”, de 16/11/2026, e pedido de retomada na dot às 09h50 UTC. Git é a fonte de verdade. Referência de processo: `Sagittaryuz/development-standards/GIT-FIRST.md`, blob `601e918eef9a89578fd6f55148c6594304d86ac2`.

## Versão 0.2.0

Implementados câmera, controles laterais, padrões persistentes/editáveis, carimbo real via Canvas/ImageRenderer, GPS no instante do disparo, endereço/mapa Apple com fallback, logotipo local, original preservado, prévia, salvamento manual no Fotos, histórico e exportação. Eventos físicos, fechamento e entrega nativa usam guards; lotes são idempotentes por captura/asset. GPS é opt-in. Não há captura de vídeo customizada nesta versão.

Distribuição: branch `camera-mvp`. A branch `feat/camera-mvp` do PR #1 recebe o mesmo commit para manter revisão e importação alinhadas. `main` permanece preservada e PR permanece rascunho até validação nativa. Nenhuma credencial ou mudança de acesso é necessária.

## Erros corrigidos e orientação reutilizável

- O protótipo importava FileManager/Photos como exports: são globais do Scripting.
- `shouldMoveFile` não é opção documentada de `Photos.savePhoto`; usar `fileName`.
- Parar câmera antes de dispensar o visor; manter visor montado durante prévia para Camera Control.
- Snapshot das preferências, hora e GPS antes de await; GPS obtido depois não pertence à foto anterior.
- Encoded dimensions + orientação EXIF 5–8 trocam os eixos na composição; não assumir paisagem por dimensões brutas.
- Logotipo deve usar aspect-fit, não quadrado deformado.
- JSON e original são persistidos antes da renderização. Exceção no mapa/carimbo não apaga foto.
- Atualização deve usar o importador nativo e fonte Git; não inventar hash remoto no manifesto.

## Verificado em 16/11/2026

`npm run check`: manifesto, TypeScript estrito no núcleo, bundle sintático completo. `npm test`: 26 verificações puras/de layout/pixels sintéticos e 9 fluxos com host simulado. Revisão visual dos carimbos sintéticos em retrato/paisagem; revisão das APIs pela documentação oficial. Nenhum desses resultados é prova de execução nativa no iPhone.

As declarações completas do host são sincronizadas pelo Scripting CLI a partir do aparelho, não vêm no pacote CLI. Portanto não afirmar typecheck completo sem os arquivos reais nem usar um stub como prova de compatibilidade.

## Próximo passo nativo, sem apagar dados

1. Importar a URL `camera-mvp`, conferir Momentra 0.2.0.
2. Abrir sem GPS; permitir câmera, fotografar, conferir original/carimbo e salvar no Fotos uma vez.
3. Alterar título/observação, cancelar edição, reabrir e conferir persistência por perfil.
4. Testar paisagem/retrato, logo largo/alto, carimbo topo/rodapé e texto longo.
5. Ativar GPS, negar e permitir; testar offline sem perder a captura; conferir data/fuso/coordenadas.
6. Disparar pelo botão físico, voltar da prévia, fechar/reabrir e retomar; testar lote da Tela Bloqueada e repetir o mesmo lote sem duplicação.
7. Conferir exportação final/original/JSON e recuperação após negar acesso ao Fotos.
8. Se houver erro, registrar texto e versão do Scripting. Não reinstalar/apagar antes de preservar fotos.

## Fontes oficiais consultadas

- https://scriptingapp.github.io/guide/Device%20Capabilities/AVCaptureSession%20%26%20Camera%20Control/Quick%20Start/
- https://scriptingapp.github.io/llms.txt
- https://github.com/scriptingapp/scriptingapp.github.io (documentação App Store, consultada em 16/11/2026)
- https://github.com/ScriptingApp/scripting-app-development

Documentação efetivamente lida: AVCaptureSession, Camera Control/capture handoff/events, Photos, Location, MapSnapshotter, Canvas, ImageRenderer, ImageIO, UIImage, DocumentPicker, Storage, Dialog, GeometryReader e Liquid Glass.


## Atualização 0.3.0 · interface amigável e Liquid Glass

Fonte: pedido direto do Marcos, encaminhado pelo coordenador em 16/11/2026; correção específica: parte inferior só seletor deslizável Vídeo à esquerda / Câmera à direita, obturador simples logo acima. Mantidos perfis e controles laterais.

Implementado material nativo regular em dois rails independentes, um vidro por rail, filhos plain, VoiceOver contain/labels/values/hints, seleção explícita de perfil e texto em português. Picker segmented usa seleção nativa e transição do sistema. Não forçamos animação que ignore Reduzir Movimento. A renderização real e redução de transparência precisam de aparelho.

Vídeo usa sessão exclusiva reconstruída com preset high, movie output e entrada de microfone. O botão físico segue o modo ativo. Gravação impede mudança de modo/fechamento normal; segundo toque finaliza. Fechamento externo finaliza movie antes de aguardar promise pendente. Falhas liberam bloqueio e permitem voltar a foto. Não há carimbo no vídeo. Sem exclusão automática. Último vídeo persistido e salvamento manual deduplicado.

Causas evitadas: startRecording só resolve após finalização, portanto stop antes de await pending ao sair; seletor bloqueado durante start/permissão evita duas sessões; controles exclusivos de foto não ficam ativos em vídeo.

Validação: check e 26 testes núcleo/render + 15 fluxos mock. Testes novos verificam rails, ordem e posição dos controles, modo bloqueado na inicialização/gravação, ciclo vídeo/salvar/voltar foto, falha na gravação, fechamento externo e layout compacto estrutural. Não equivale a validação SwiftUI/AVFoundation física.

Checklist nativo adicional: iOS26+, aparência e legibilidade sobre cena clara/escura; fonte ampliada/VoiceOver/Reduzir Transparência/Reduzir Movimento; seletor Vídeo/Câmera em retrato/paisagem; permissão de microfone negada e retorno à foto; gravar áudio/vídeo, parar pelo toque e botão físico; finalizar interrupção; salvar uma vez e reabrir; manter carimbos/fotos anteriores intactos.

Fontes oficiais consultadas:
- https://scriptingapp.github.io/guide/View%20Modifiers/Liquid%20Glass/Liquid%20Glass%20Effect/
- https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- Documentação Scripting App Store: Picker, Button, Accessibility, Preferred Color Scheme, AVCaptureSession Quick Start e Session Control, Photos.saveVideo.


### Complementos finais da especificação 0.3.0

Pedidos diretos adicionais encaminhados em 16/11: topo com flash, timer, proporção e configurações; popup marca opção atual. Nova página timestamp agrupa data/hora/localização; fontes, formatos e quatro cantos. Página também contém GPS, mapa opcional, escala visual/canto do mapa e canto de logo/arte. O nome do modo longo explicita data por extenso com hora h/min/s, não números de hora escritos por palavras.

Implementado recorte central 4:3/16:9 após orientação EXIF, com original preservado; grava composição inclusive sem carimbo. Visor segue enquadramento nativo e não simula máscara exata de crop. Flash usa flashMode documentado no capturePhoto; amarelo representa opção armada, hardware não foi verificado. Temporizador cancelável de 3/10s, snapshot de hora/GPS após a contagem. Configurações migradas com defaults; data/hora/localização nunca têm chaves de visibilidade independentes.

Mapa/logo separados do bloco timestamp e posicionados com resolução de colisão. 44 testes núcleo/render (inclui 576 combinações de overlays) + 19 testes de fluxo mock; não são homologação de APIs/vidro/fonte/permissões em iPhone. Último checklist nativo deve incluir flash auto/on/off em aparelho com/sem suporte, timer/cancelar, proporção/crop, configuração/persistência, quatro cantos, mapa/logo, texto longo e telas pequenas.


## 0.3.1 · armazenamento sem galeria e avaliação Google Fotos

Fonte: pedido Marcos encaminhado em 16/11 para opção somente nuvem, login Google inicial e acessar fotos capturadas pelo app. Pesquisa oficial documentada em CLOUD_STORAGE.md. A parte completa depende de cliente OAuth, callback compatível, consentimento e adequação da política Google, especialmente uso empresarial. Não configurados nem contornados.

Implementado apenas o componente viável independente: allowGallery persistente (default true preserva manual anterior), controles e handlers bloqueiam gravação em Photos quando false, textos deixam claro que arquivos seguem locais e não houve envio. Opção somente nuvem permanece indisponível, sem falso botão de login. Sem remoção de arquivos, criação de credenciais, acesso externo ou custos. Check + 44 testes core + 20 runtime mock passaram.

Próximo passo: resolver destino profissional/pessoal e configuração OAuth aprovada, validar iPhone antes de habilitar uploads ou descarte temporário. Não transformar consentimento de login em autorização para upload de arquivos antigos.


## 0.3.2 · formato conforme referência visual

Fonte: imagem fornecida por Marcos em 16/11 e instrução “A câmera tem que estar nesse formato aqui”. Imagem inspecionada de fato, não publicada. Visor dominante retangular, preto, toolbar de ícones, obturador branco e thumbnail orientaram alteração. Preservados pedidos específicos: apenas Vídeo/Câmera no seletor abaixo do obturador, quatro controles topo e laterais.

camera_layout.ts calcula dimensões comuns à UI e ao diagrama sintético. Visor aspect-fill acompanha proporção selecionada, sem cornerRadius. Thumbnail/prévia e Salvar flanqueiam obturador; exportar/fechar continuam acessíveis na faixa de status. Ícones laterais compactos preservam labels VoiceOver. Não houve mudança em credenciais/armazenamento/captura.

Check + 44 testes core/render e 21 fluxos mock. Diagramas geométricos retrato390×844, pequeno320×568 e paisagem844×390 inspecionados. São simulações de geometria, com símbolos/fontes aproximados, não render SwiftUI/iPhone. Layout real, tamanhos dinâmicos, contraste de vidro e crop/field of view nativo ainda pendentes de aparelho. Não simular zoom/lentes nem representar mapa/timestamp ao vivo: composição permanece na foto final/prévia.

Ajustes da auditoria0.3.2: preview inset72% mantém câmera visível, Exportar/Fechar têm alvos44pt e faixa status44; vídeo usa frame16:9 separado da proporção de foto. Campo de visão real do vídeo segue pendente de hardware. Toolbar mudou a plain+glassEffect com label44 para evitar padding implícito do estilo glass.


## 0.3.3 · sobreposição realmente ao vivo

Fonte: pedido direto Marcos encaminhado em 16/11: mapa, data/hora/localização e logo visíveis na imagem ao vivo, não só na foto. Canvas transparente usa drawStamp compartilhado, relógio1s e mesmas posições/fontes/escalas. Camada decorativa abaixo dos botões e sem handlers. Não foi usado allowsHitTesting por ausência de comprovação no host Scripting.

GPS opt-in atualiza30s somente câmera ativa/desocupada. Fix vence60s, invalida endereço/mapa imediatamente ao desligar/recusar e no tick quando envelhece. Enrich em cache por coordenadas+timestamp+opção mapa; resultado atrasado só entra se chave ainda atual. Captura reutiliza mapa correspondente, snapshot de hora/GPS após temporizador. Mapa/logo não fabricados. Vídeo permanece sem carimbo e sem overlay para não sugerir que o arquivo gravado contém algo que não contém.

44 core/render +24 fluxos mock e check aprovados; testes verificam Canvas live, GPS desligado, mapa/logo reais do mock, reutilização no disparo, desligar GPS e ocultar durante revisão/vídeo. Diagrama sintético do mesmo desenho inspecionado, não iPhone. Nenhuma chamada Google ou faturamento: pesquisa e bloqueios registrados em CLOUD_STORAGE.md.


## 0.3.4 · identidade Google opcional

Fonte: pedidos diretos de Marcos para conectar Google e continuar a infraestrutura necessária gratuita, encaminhados pelo coordenador em 16/11. Infraestrutura dedicada no Cloudflare existente; nenhum projeto alheio alterado. Backend de produção `https://momentra-auth.mrpires72.workers.dev`, Google OAuth Web com callback HTTPS fixo `/callback`. Publicação do app continua pendente da revisão final do coordenador; não integrar main nem retirar rascunho por causa desta nota.

`backend/worker.mjs`: identidade somente (openid/email/profile), PKCE S256, state autenticado/criptografado TTL10min, código opaco TTL2min, callback Scripting fixo, sem tokens na URL, sem armazenamento servidor e sem refresh. Secrets Google/BROKER_SECRET no servidor. Rate binding dedicado20/60s por IP, quota Free compartilhada100k/dia; não é garantia global de capacidade. Logs de invocação desativados pelo coordenador. `google_auth.ts`: Keychain por script e aparelho, secret cliente vazio, status local sem rede, erros sanitizados, login concorrente deduplicado e logout invalida resultados pendentes. `index.tsx` integra login opcional nas configurações e acesso não bloqueante na primeira abertura; token nunca vai para Storage.

Segurança revisada: destinos fixos, allowlists/duplicatas, PKCE antes da troca, limites de corpo, token/scopes filtrados, nenhuma mídia/upload, segredo ausente do app. Código Google de uso único fornece proteção de replay; não há revogação central de envelopes. Cliente público não comprova autenticidade do aplicativo e não deve conceder privilégios backend. Logout é somente local. Google Fotos e Maps continuam indisponíveis; nenhuma cobrança ativada nesta etapa.

Causas reais corrigidas: Google inclui `iss` no callback, aceito apenas exato `https://accounts.google.com` quando presente; duplicado/inválido rejeitado. Cloudflare não suporta redirect:error e falhava antes de enviar rede; usar manual e rejeitar3xx pela condição existente. Não afrouxar state/PKCE para resolver compatibilidade. Fontes e regressões em backend/README.md.

Evidência: backend29 testes e módulo14 testes sintéticos passaram; coordenador relata app44 core+28 runtime e check aprovados antes do incremento do manifesto. Consentimento real e callback302 com state preservado observados pelo coordenador; troca completa via Worker em reteste, não afirmada concluída aqui. Falta validar login/retorno Scripting, cancelamento, expiração, Keychain bloqueado e toda a captura nativa em iPhone. Preservar originais e dados ao atualizar. Próximo passo: conferir teste real do backend, executar check da versão0.3.4 e publicar apenas nos destinos existentes pelo coordenador.

Validação real reportada pelo coordenador: consentimento Google e troca direta no endpoint Google retornaram200 com PKCE; callback Worker retornou302 com state correto. Falha inicial da troca Worker por redirect:error foi corrigida e publicada na revisão Cloudflare b414e20d. Reteste completo via Worker permanece pendente: Google accountchooser passou a ficar em Carregando. Não afirmar fluxo ponta a ponta pronto. Todos os testes locais da versão: check,44 core/render,28 runtime,14 auth,29 backend passaram.
Teste sintético em produção após correção: authorize302, callback302 com iss Google/state correto, código sintético no token400 invalid_grant (não502). Não equivale a troca OAuth real completa. Cloudflare bloqueou User-Agent padrão urllib com1010; User-Agent Momentra/0.3.4 passou no teste do coordenador. Scripting físico segue pendente.

## 0.3.5 · controles circulares e visor ampliado
Pedido direto Marcos16/11: todos ícones circulares de mesmo tamanho, ampliar câmera e4:3 padrão.14 controles icônicos têm44×44pt e raio22, incluindo thumbnail; obturador especial maior e seletor cápsula preservados. Toolbar/status são overlays para liberar altura; câmera mantém aspecto exato3:4 retrato/4:3 paisagem.320×568 passa de237×316 para320×426.67 (cerca82% mais área).390×844 já tinha largura máxima e continua390×520: não esticar imagem para alegar aumento.16:9 salvo explicitamente continua respeitado; nova instalação4:3.
47 core/layout/render+29 runtime e check aprovados. Diagramas sintéticos320×568/390×844/844×390 inspecionados, não SwiftUI/iPhone. Controles sobrepostos podem cobrir parcialmente carimbo de canto durante operação; não são gravados na foto e coordenadas do carimbo continuam iguais. Teste físico permanece pendente. Sem alterações OAuth/Photos/Maps nesta revisão.

## 0.3.6 · configurações conforme referências
Fonte: duas imagens enviadas por Marcos16/11, pedido somente funções implantadas. Página clara inspirada Ajustes: cabeçalho fixo/back circular44, cinco cartões brancos arredondados, ícones coloridos44 e divisores. Câmera permanece escura/0.3.5 preservada. Toggles controlam opções reais carimbo/GPS/mapa/cópia manual na galeria, não fingem gerenciar permissões do iOS. Pickers preservam fontes/formato/cantos/escala. Conta Google preservada. Photos/nuvem agora só aviso, sem botão falso; nenhum item update/rating/idioma/microfone adicionado.
Referências reais e diagrama sintético da árvore de componentes inspecionados; fonte/símbolos aproximados, não screenshot iPhone.47 testes core prévios+30 runtime e check0.3.6 aprovados. Testes de back, opções persistidas, GPS/mapa/galeria e estados Google passaram. Nenhum teste físico. OAuth reteste de navegação separado continua sem mudar scopes/backend nesta revisão.
