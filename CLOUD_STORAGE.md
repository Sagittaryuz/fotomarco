# Armazenamento e Google Fotos · avaliação 16/11/2026

## Base publicada · 0.4.0

Backend publicado após aprovação específica: Worker `68d51eb4`, fonte `593ba2f2`, com Photos opcional habilitado. Library API e cinco escopos mínimos configurados no projeto dedicado; nenhum billing/custo ativado. `/health`200 confirma version2/photos:true; `/privacy`200 com no-store/no-referrer/CSP. Conferência independente do coordenador confirmou os dois endpoints públicos.

Produção aceita authorize de identidade e de Photos com os conjuntos exatos. Regressão sintética de identidade chegou ao callback com state correto e código falso foi rejeitado400. Não houve novo consentimento Photos, upload real ou teste nativo nesta etapa. O teste real de identidade anterior permanece evidência histórica, não prova de upload/retorno iPhone. Envio pessoal requer consentimento na conta e confirmação da foto no app; nada é automático. Somente nuvem e mapa Google incorporado seguem explicitamente não concluídos.

## Base confirmada · 0.3.7 (histórico)

Login Google de identidade implementado, com backend dedicado publicado no Cloudflare Workers (`https://momentra-auth.mrpires72.workers.dev`). Escopos somente `openid email profile`; sem Photos, Maps, refresh token, upload ou exclusão. Credenciais servidor protegidas como secrets e tokens do app no Keychain. Câmera funciona sem login. Fluxo real do backend confirmado no PC: consentimento Google, callback HTTPS200 com state correspondente, troca de token pelo Worker200, identidade verificada200, ausência de refresh token e replay rejeitado400. A página exige tocar Voltar ao Momentra para retornar ao aplicativo. Retorno ao Scripting e Keychain no iPhone permanecem sem teste físico. As avaliações históricas abaixo descrevem o estado das versões anteriores, não ausência atual de infraestrutura.

## Consolidação 0.4.0

Integração pessoal Google Fotos opcional: escopos `photoslibrary.appendonly` e `photoslibrary.readonly.appcreateddata`, consentimento separado, token em Keychain por conta. Não usa escopo de edição nem acesso geral à biblioteca. Envio manual da foto escolhida, JPEG até 20 MB, sem vídeos, sem upload de histórico/automático. O nome do perfil não prova a finalidade; a interface exige declaração explícita de uso pessoal para cada envio. Usos internos empresariais não devem ser enviados.

O módulo confirma upload dos bytes, criação individual e consulta pelo ID remoto. Persistência anterior à criação impede repetir operação ambígua após falha/reinício. Sem confirmação não apaga arquivos. IDs são mantidos, URLs temporárias de imagem não; listagem pagina somente itens criados pelo app. Todas as cópias locais continuam preservadas: **não é armazenamento somente nuvem**.

A API usa espaço disponível da conta Google; não adiciona armazenamento grátis nem compra Google One. Limites/quota podem bloquear operações. Aplicação OAuth em Testing permanece limitada a usuários de teste autorizados, sem equivalência a verificação pública. Esta preparação foi exercitada com mocks, sem enviar nenhuma foto real.

Fontes reavaliadas: [política de uso pessoal](https://developers.google.com/photos/support/api-policy), [autorização](https://developers.google.com/photos/overview/authorization), [upload](https://developers.google.com/photos/library/guides/upload-media), [acesso e validade de URLs](https://developers.google.com/photos/library/guides/access-media-items), [quota](https://developers.google.com/photos/overview/api-limits-quotas).

### Google Maps: limite preservado

Maps URLs abre localização no aplicativo/navegador gratuitamente sem chave, após gesto e informação explícitos. É separado do mapa Apple no carimbo e **não satisfaz a incorporação Google solicitada**. Embed e SDK têm SKUs gratuitos, mas exigem billing; Static tem franquia seguida de cobrança. Não há garantia de custo zero usando apenas alertas. Não foi confirmada licença para exportar permanentemente o mapa Google em JPEG. Logo não ativar billing nem substituir o carimbo por conteúdo Google sem resolver as duas condições.

Fontes: [Maps URLs](https://developers.google.com/maps/documentation/urls/get-started), [Embed](https://developers.google.com/maps/documentation/embed/quickstart), [Maps iOS](https://developers.google.com/maps/documentation/ios-sdk/usage-and-billing), [Static](https://developers.google.com/maps/documentation/maps-static/usage-and-billing), [termos](https://cloud.google.com/maps-platform/terms).

## Entregue na 0.3.1 (histórico)

Configurações → Cópia na galeria Fotos permite bloquear salvamento na galeria para fotos e vídeos. A preferência persiste; os handlers também bloqueiam a chamada Photos, não apenas os botões. O padrão mantém o comportamento anterior: salvar manualmente. Cópias existentes não são apagadas.

**Isto não é modo somente nuvem:** originais, composição e vídeos continuam no armazenamento local do Momentra. Google Fotos aparece explicitamente não configurado; não há login falso, upload, listagem remota nem exclusão automática. Nenhuma credencial ou infraestrutura foi criada, nenhuma conta foi acessada e nenhum arquivo foi transmitido.

## Viabilidade e condições

A Google Photos Library API suporta upload e listagem de mídia criada pelo próprio aplicativo. Desde a mudança de março de 2025, não permite simplesmente listar toda a biblioteca do usuário. Para outras fotos, existe Picker com seleção explícita, não acesso geral silencioso. Fontes: [introdução](https://developers.google.com/photos/library/guides/get-started-library), [mudanças](https://developers.google.com/photos/support/updates).

O fluxo mínimo requer projeto Google, Library API ativada, cliente OAuth compatível, tela de consentimento e autorização do usuário. Escopos necessários para a funcionalidade proposta: photoslibrary.appendonly e photoslibrary.readonly.appcreateddata. Contas de serviço não servem. Aplicações distribuídas podem exigir verificação OAuth e política de privacidade; configurar/testar pessoalmente não equivale a aprovação pública. [Autorização](https://developers.google.com/photos/overview/authorization).

Scripting tem OAuth2 com PKCE/state/renovação e Keychain por script. Porém seu callback padrão scripting://oauth_callback/... não prova compatibilidade com os redirects/clientes Google. Não inventar client ID, usar client secret em código público, copiar credenciais de outro app, desativar state nem recorrer ao antigo fluxo copiar/colar. É necessário validar uma rota admitida pelo Google e pelo host: integração nativa apropriada, ou serviço HTTPS sob controle do projeto, com tokens protegidos e retorno vinculado à sessão. Isso depende de configuração e, potencialmente, infraestrutura adicional ainda não estabelecida. Fontes: [Scripting OAuth2](https://scriptingapp.github.io/guide/Utilities/OAuth2), [Google iOS](https://developers.google.com/identity/sign-in/ios/start-integrating), [migração OOB](https://developers.google.com/identity/protocols/oauth2/resources/oob-migration).

**Restrição importante para perfis de trabalho:** a política Google Photos proíbe guardar dados internos empresariais e criar substituto de galeria geral. A integração pessoal que acrescenta câmera/carimbo pode ser viável, mas fotos profissionais devem usar um destino apropriado de arquivos/objetos, após definição e autorização. Não encaminhar automaticamente imagens de trabalho para Google Fotos. [Política](https://developers.google.com/photos/support/api-policy).

## Critérios antes de habilitar “somente nuvem”

1. Definir destino compatível com uso pessoal/profissional e aprovar configurações, permissões e eventuais custos.
2. Validar OAuth no iPhone, armazenamento de tokens seguro, cancelamento, revogação e troca de conta sem misturar mídias.
3. Exibir consentimento/privacidade antes do primeiro envio. Autenticar não autoriza upload oculto de arquivos antigos.
4. Capturar/processar em espaço temporário privado, sem chamar Photos.savePhoto/saveVideo. Mesmo modo nuvem precisa de bytes temporários no aparelho.
5. Persistir fila e estado; preservar arquivo se offline, sem espaço remoto, token expirado ou falha. Não chamar arquivo “na nuvem” só porque houve login.
6. Upload dos bytes + mediaItems.batchCreate, conferir sucesso individual e salvar ID remoto. Respostas ambíguas não permitem apagar fonte nem repetir criação sem reconciliação.
7. Liberar apenas arquivos temporários do próprio Momentra após comprovação de cópia equivalente recuperável e dentro da autorização aplicável. Nunca apagar galeria/arquivos anteriores implicitamente. Descrever retenção offline ao usuário.
8. Listar itens criados pela mesma integração; respeitar paginação, expiração de URLs, indisponibilidade, desconexão e exclusão. Sem thumbnail cache permanente se o modo prometer apenas retenção temporária.
9. Testar fluxo real capturar→enviar→abrir remoto→limpar temporário, sem salvar na galeria; falhas, interrupções e duplicidade.

A API faz upload em duas fases e consome armazenamento da conta Google (não significa espaço ilimitado); recomenda upload retomável em dispositivos móveis. [Upload oficial](https://developers.google.com/photos/library/guides/upload-media).

## Verificação da entrega 0.3.1 (histórico)

44 testes núcleo/render + 20 fluxos simulados e check de manifesto/TypeScript/bundle. Teste novo confirma bloqueio de Photos para foto/vídeo mesmo invocando handlers, persistência da preferência e preservação local. Sem autenticação/envio/teste Google real ou teste físico no iPhone. A função completa somente nuvem está pendente, não concluída.


## Avaliação anterior à implementação OAuth (histórico de 16/11/2026)

Autorização direta para conectar foi recebida; pesquisa no projeto não encontrou chave, cliente OAuth, backend ou projeto Cloud configurado. Catálogo de conectores não oferece gerenciamento Google Cloud/Maps/IAM neste trabalho. Não usar credenciais de outro aplicativo nem assumir que uma sessão Google concede acesso ao projeto correto.

Maps Static exige API habilitada, credencial e billing no projeto. Não foi habilitado faturamento nem criada credencial: não há orçamento/destino estabelecido. Chaves devem ser restritas e não colocadas no repositório público. [Configuração oficial](https://developers.google.com/maps/documentation/maps-static/get-api-key), [uso/cobrança](https://developers.google.com/maps/documentation/maps-static/usage-and-billing).

Incorporar permanentemente mapa Google ao JPEG é distinto de exibir mapa: termos limitam armazenamento/exportação e exigem atribuição. Confirmar licença aplicável antes de implementar esse uso; não basta uma chave válida. [Termos Google Maps, seção 3.2](https://cloud.google.com/maps-platform/terms).

Para Google authentication, identificar projeto autorizado e callback admitido no host Scripting. O caminho alternativo é backend HTTPS do projeto e OAuth web seguro, com segredo no servidor, sessão vinculada e retorno autenticado; o destino/backend ainda não existe no projeto. [OAuth web oficial](https://developers.google.com/identity/protocols/oauth2/web-server). Não substitui consentimento nem habilita automaticamente Google Photos/Maps. O mapa ativo continua Apple e Google permanece explicitamente pendente.

## Bloqueio anterior da preparação0.4.0 (resolvido para publicação do backend)

Library API ativada e cinco escopos mínimos salvos no projeto dedicado sem billing. Publicação do Worker/gate bloqueada pela revisão de autorização; rascunho mantido. Logo Photos segue indisponível no serviço atual, e `/privacy` só ficará acessível após publicação. Nenhum consentimento Photos nem upload real foi executado. O script0.4.0 permanece local aguardando essa publicação para evitar entrega fragmentada; versão distribuída continua0.3.7.


## Evolução0.5.0 · retenção condicionada à equivalência

Usuário confirmou “Mapa da Apple. Ok”, substituindo Google Maps no objetivo do carimbo. Google Maps incorporado deixa de ser pendência desse objetivo; abertura externa continua opcional e distinta.

Implementado modo Local/default e Somente nuvem após verificar para novas capturas próprias. Sem galeria, sem vídeos ou migração automática. Confirmação pessoal por captura envia dois itens (original/final), mantém journals separados e reusa IDs em falhas. Download `=d` fresco, domínio permitido sem Bearer/redirect, timeout e limite de tamanho; SHA256+tamanho devem coincidir integralmente para ambos. Manifesto/IDs persistidos e relidos antes de remover JPEGs próprios, nova validação dos arquivos/conta antes de cada remoção; falha parcial pode ser retomada por IDs, sem reupload. JSON/cache podem ficar no aparelho; histórico abre a foto remota.

O Google remove EXIF de localização no download. Por isso equivalência NÃO é presumida, e o modo pode permanecer pendente conservando dados. Não remover por comparação de dimensões. Nenhum upload real ou limpeza de arquivo do usuário ocorreu nesta implementação. [Download oficial](https://developers.google.com/photos/library/guides/access-media-items).
