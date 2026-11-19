# Canal privado de atualização do Momentra

O projeto Vercel `momentra-instalacao` usa `ota-install` como raiz. O app instalado usa o mesmo domínio e os mesmos tickets temporários para ler o manifesto e o IPA.

Para publicar um IPA assinado, calcule SHA-256 e o tamanho do arquivo. Use o caminho `ota/Momentra-VERSÃO-BUILD-PRIMEIROS_12_HEX_DO_SHA.ipa` no Blob privado `momentra-ipa-private`. O projeto obtém acesso ao Blob por OIDC. A cópia privada e o índice na raiz do Google Drive continuam sendo o arquivo de referência.

Para enviar pelo instalador, configure `OTA_UPLOAD_FILE`, `OTA_UPLOAD_SIZE`, `OTA_UPLOAD_EXPIRES` (época Unix em milissegundos) e uma credencial temporária de 64 dígitos hexadecimais em `OTA_UPLOAD_TOKEN`. Em um deploy com a janela ativa, faça `POST /api/install?stage=upload` autenticado com essa credencial. Use a URL de envio retornada para um único `PUT` com o IPA, `Content-Type: application/octet-stream` e o tamanho exato. Trate a URL assinada como credencial e mantenha-a fora dos logs. É possível pré-carregar a próxima versão mantendo os metadados da versão atual.

Depois do envio, configure juntos `RELEASE_VERSION`, `RELEASE_BUILD`, `SIGNED_IPA_BLOB` e `SIGNED_IPA_SIZE` do pacote publicado. Encerre a janela de envio e faça o deploy de produção. Confira o manifesto no domínio oficial, `HEAD`, uma retomada `Range`, o SHA-256 do download integral e a rejeição do acesso anônimo. Publique a tag apenas depois dessas verificações.
