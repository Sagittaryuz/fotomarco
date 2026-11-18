# Capturas na nuvem: requisitos e limites

Pesquisa de 17/11/2026. Esta especificação não significa que o envio automático já esteja disponível.

- O Google Fotos recebe arquivos em duas etapas: envio dos bytes e criação de um item. O retorno de cada item deve ser validado; sucesso HTTP por si só não basta. [Guia oficial](https://developers.google.com/photos/library/guides/upload-media)
- Para o modo pessoal, o álbum deve ser criado ou reconhecido como criado por este aplicativo. A resposta de criação de um álbum pode se perder; em caso ambíguo, pesquisar antes de criar outro.
- A API do Fotos é limitada a mídias de natureza pessoal. Fotos empresariais não podem ser encaminhadas por ela; é necessário um destino adequado separado. [Política do Google](https://developers.google.com/photos/support/api-policy)
- Enquanto houver captura pendente, guardar o arquivo completo em diretório protegido e não purgável. Não usar somente Caches ou temporaryDirectory. A miniatura pode ser descartável; ela nunca substitui o arquivo integral.
- Identificar a conta de destino e o perfil associados no momento da captura. Mudança de conta, expiração de autorização, pouco espaço, falta de rede, quota e bloqueios do serviço mantêm o arquivo local e aparecem como pendências.
- A fila deve ser persistente e recuperável após interrupção. Retentativas usam espera exponencial para falhas recuperáveis; resposta incerta não pode ser interpretada como confirmação nem como falha definitiva. Manter operações de criação serializadas por conta.
- Antes de excluir qualquer arquivo local é necessário confirmar cada item da captura que se pretende remover, incluindo original e cópia com carimbo quando ambos forem considerados parte da captura. Verificar conta, identificadores, conteúdo local imutável e pertencimento ao álbum. Persistir recibos antes da limpeza e torná-la recuperável.
- Fotos adicionadas manualmente à biblioteca Fotos do iPhone são separadas dos arquivos do aplicativo; não removê-las sem a ação explícita da pessoa.
- O sistema pode continuar transferências de uma URLSession em segundo plano, mas o iOS cancela transferências quando a pessoa força o encerramento do app e não garante horários imediatos. [Apple](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/background(withidentifier:))
- A API do Fotos não informa isoladamente o uso de armazenamento do Fotos. O Drive fornece quota agregada e parcela do Drive; “outros serviços” não deve ser rotulado como Fotos. [Google](https://developers.google.com/workspace/drive/api/reference/rest/v3/about)

Validação obrigatória antes de habilitar limpeza: testes offline, interrupção entre todas as etapas, respostas ambíguas, expiração de autenticação, troca de conta, arquivo alterado durante o envio, restauração de recibos, pouco espaço, álbum indisponível e verificação em um iPhone com fotos de teste autorizadas. Testar tanto original como cópia, sem usar fotos reais insubstituíveis.


## Estado do desenvolvimento — candidato em teste

Na branch de desenvolvimento, o modo para fotos pessoais prepara o original e a versão processada em diretórios protegidos, cria recibos independentes para as duas versões e preserva os arquivos se uma etapa falhar. A fila é vinculada à conta escolhida. A limpeza no sandbox do app exige verificar novamente os dois itens no álbum e manter uma prévia reduzida; não apaga itens da biblioteca Fotos do iPhone. A retomada da limpeza é registrada no disco.

Esse fluxo ainda não foi validado ponta a ponta com uma conta real, com suspensão do app ou no iPhone do usuário, nem foi publicado como atualização oficial. A implementação atual tenta novamente enquanto o app está ativo, em intervalos de aproximadamente 30 segundos; não implementa transferência em segundo plano garantida nem espera exponencial. Se a criação de um item tiver resposta ambígua, o recibo impede reenviar automaticamente, e o arquivo permanece no aparelho. Esses limites devem ser resolvidos ou apresentados claramente antes de tratar a funcionalidade como concluída.

Os testes usam serviços simulados: sucesso nos testes não comprova autorização, política de conta, quota, entrega ou retenção no Google Fotos. O modo Google Fotos é restrito a fotos pessoais; conteúdo profissional exige outro destino adequado.
