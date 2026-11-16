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
