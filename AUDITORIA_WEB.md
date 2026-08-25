# Auditoria técnica — conversão híbrida Android + navegador

Data: 23/08/2026

## Resultado

Um único Android instala o aplicativo e funciona como anfitrião/servidor local; os demais aparelhos entram pela página servida por ele, usando navegador Android ou iOS.

## Problemas encontrados e correções

### Bloqueadores

- **O código de rede usava `dart:io` diretamente na interface compartilhada.** Isso impedia a compilação web. A rede agora usa implementações condicionais: servidor HTTP/WebSocket no Android e cliente WebSocket no navegador.
- **Uma aba de navegador era tratada como servidor.** Navegadores não podem abrir uma porta TCP para receber os outros aparelhos. A responsabilidade de hospedagem foi movida para o aplicativo Android do anfitrião.
- **O QR Code continha uma URL `ws://`.** Câmeras comuns não tratam WebSocket como página navegável. Agora o QR contém uma URL `http://` completa, que abre diretamente a tela de entrada.
- **O scanner dentro do app dependia de câmera em uma origem HTTP local.** Android e iOS normalmente bloqueiam câmera de páginas não HTTPS. O fluxo foi simplificado: o participante usa a câmera nativa para abrir o QR; a dependência de scanner foi removida.

### Confiabilidade e segurança local

- A espera fixa de 300 ms para conexão foi substituída por confirmação real do servidor e timeout.
- Comandos de clientes agora são vinculados ao jogador daquela conexão antes de chegarem ao anfitrião.
- Valores negativos, zero, `NaN`, infinitos, auto-transferências, status inválidos, jogadores duplicados e nomes inválidos são rejeitados.
- Desconexões atualizam o status do jogador automaticamente.
- A sala possui código aleatório de seis caracteres e limite de 20 navegadores.
- O caminho dos arquivos servidos é validado contra travessia de diretórios.
- O Android mantém a tela ligada enquanto o aplicativo está aberto, reduzindo interrupções do servidor durante a partida.

### Interface e projeto

- A entrada foi refeita com layout responsivo para celular e telas maiores.
- No Android aparecem as ações de anfitrião e partidas salvas; no navegador aparece apenas a entrada de participante.
- O link do QR Code preenche e conecta automaticamente à sala.
- Título, descrição, cores e manifesto web deixaram de usar os valores genéricos do projeto Flutter.
- Dependências sem uso (`shelf`, `shelf_router`, `mobile_scanner` e `cupertino_icons`) foram removidas.
- O teste de exemplo quebrado, que ainda procurava `MyApp`, foi substituído por testes do produto.

## Validações executadas

- `flutter analyze`: sem problemas.
- Testes de interface e regras financeiras: aprovados.
- Teste de integração WebSocket entre anfitrião e convidado: aprovado.
- Build web release: aprovado.
- Build Android release: aprovado.
- Verificação do APK: `index.html`, `flutter_bootstrap.js` e `main.dart.js` dos convidados estão incorporados.

APK gerado: `build/app/outputs/flutter-apk/app-release.apk`  
Tamanho: 50.433.815 bytes (48,1 MB)  
SHA-256: `EE8DE62C3ADD036DABDA30A935A717BDA6EAC0D2F70E1438B5F8EC181600C79C`

## Limitações conhecidas

- A comunicação é HTTP/WebSocket sem TLS, adequada somente à rede local confiável da partida.
- Recuperar um jogador desconectado ainda é uma seleção por nome, sem senha. Isso é aceitável para uma mesa entre conhecidos, mas não para uma rede pública.
- O APK release atual usa a chave de desenvolvimento configurada no projeto. Ele pode ser instalado manualmente, mas uma publicação em loja exige assinatura de produção própria.
- Se o Android encerrar o aplicativo por ação do usuário ou política agressiva de bateria, a sala termina.
- Redes Wi-Fi com isolamento entre clientes bloqueiam o acesso mesmo quando todos parecem conectados ao mesmo roteador.
