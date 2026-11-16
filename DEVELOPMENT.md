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
