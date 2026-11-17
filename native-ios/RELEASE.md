# Atualizações do Momentra nativo

O app consulta as releases públicas do repositório GitHub. Ele só considera versões estáveis cuja tag siga `native-ios-vMAJOR.MINOR.PATCH` e seja maior que `CFBundleShortVersionString` do aplicativo instalado. Releases em rascunho ou marcadas como pré-lançamento não geram aviso. A versão e o número de compilação são definidos em `project.yml`.

Quando uma versão estiver pronta e houver autorização para disponibilizá-la:

1. Concluir os testes da revisão exata, gerar o IPA para iPhone e verificar o identificador, a versão e a integridade do arquivo.
2. Guardar o IPA no Drive com acesso restrito e confirmar suas permissões. O link de um arquivo privado não muda suas permissões; só quem tiver acesso poderá baixá-lo.
3. Depois da validação no iPhone, criar a release GitHub pública com uma tag estável compatível, apontando para o commit correspondente. O texto deve identificar a versão e indicar como obter o IPA privado e assiná-lo no Signulous. Não publicar credenciais, dados pessoais ou o IPA em um repositório público por padrão.
4. No app já instalado, conferir que o aviso aparece, que as instruções abrem e que a atualização sobre a versão anterior mantém os dados. A instalação requer a ação do usuário no Signulous; o verificador não instala nem assina o app.

A release estável `native-ios-v0.1.4` foi publicada em 17/11/2026, vinculada à revisão `9faa225`; o IPA está no Drive privado e requer assinatura pelo Signulous. A compilação para iPhone e os testes automatizados dessa revisão passaram. O aviso com essa release real, o acesso ao arquivo privado e a atualização da 0.1.4 ainda precisam de validação no iPhone. A instalação manual de uma versão anterior sobre outra, com preservação das fotos, foi confirmada pelo usuário em 17/11/2026.
