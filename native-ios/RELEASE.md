# Atualizações do Momentra nativo

> Para a construção, os componentes e o fluxo de produção vigentes, veja o [Guia de desenvolvimento](GUIA-DE-DESENVOLVIMENTO.md). O conteúdo abaixo registra etapas anteriores do projeto.

O app consulta as releases públicas do repositório GitHub. Ele só considera versões estáveis cuja tag siga `native-ios-vMAJOR.MINOR.PATCH` e seja maior que `CFBundleShortVersionString` do aplicativo instalado. Releases em rascunho ou marcadas como pré-lançamento não geram aviso. A versão e o número de compilação são definidos em `project.yml`.

Quando uma versão estiver pronta e houver autorização para disponibilizá-la:

1. Concluir os testes da revisão exata, gerar o IPA para iPhone e verificar o identificador, a versão e a integridade do arquivo.
2. Guardar o IPA no Drive com acesso restrito e confirmar suas permissões. O link de um arquivo privado não muda suas permissões; só quem tiver acesso poderá baixá-lo.
3. Depois da validação no iPhone, criar a release GitHub pública com uma tag estável compatível, apontando para o commit correspondente. O texto deve identificar a versão e indicar como obter o IPA privado e assiná-lo no Signulous. Não publicar credenciais, dados pessoais ou o IPA em um repositório público por padrão.
4. No app já instalado, conferir que o aviso aparece, que as instruções abrem e que a atualização sobre a versão anterior mantém os dados. A instalação requer a ação do usuário no Signulous; o verificador não instala nem assina o app.

A release pública mais recente conferida em 18/11/2026 é a 0.1.11. Para preparar a candidata 0.1.12, execute o workflow `Validate native iOS draft` na revisão da candidata com `signing_candidate=true`. Confira o cliente Google iOS e o cliente público Microsoft no pacote antes de assinar. O artefato do workflow está sem assinatura.

## Aceite da candidata 0.1.12

- No iPhone, confirme a versão instalada, registre uma captura de referência e instale a candidata assinada sobre ela. Verifique se a captura, os perfis, a conta e o acesso de atualização direta continuam disponíveis.
- Confira o visor de foto em 4:3, 16:9 e 1:1, em retrato e paisagem. Faça disparos por toque, temporizador e botão físico. Confira o quadro inteiro chegando à miniatura e repita com Reduzir Movimento. Inicie, pare e reinicie vídeo, inclusive com interrupção e falta de permissão.
- Use imagens de teste com contas autorizadas. Ative mais de uma conta Google Drive e OneDrive, desligue a rede e fotografe. Altere a seleção antes de religar a rede. Confira a versão original e a processada em cada destino selecionado durante a captura, a retenção local até verificar ambos os arquivos e a galeria agrupada por data e perfil.
- A fila antiga em `CloudPending` mantém os destinos Google Fotos já registrados. O app apresenta sua contagem nos Ajustes e conserva a galeria anterior. A fila nova em `CloudArchivePending` recebe apenas novas capturas direcionadas a Google Drive ou OneDrive.
- Faça o teste de atualização direta com o pacote assinado e o backend de instalação já estabelecido. Publique a tag estável somente após esses testes e confira a oferta da versão no app.
