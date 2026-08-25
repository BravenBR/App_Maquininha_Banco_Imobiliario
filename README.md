# Banco de Mesa

Aplicativo híbrido para partidas de Banco Imobiliário:

- somente o anfitrião instala o aplicativo Android;
- o celular do anfitrião hospeda a partida e a página na rede Wi-Fi;
- participantes Android e iPhone entram pelo navegador, sem instalar nada;
- o QR Code abre uma URL HTTP normal e já informa o código da sala.

## Como jogar

1. Instale o APK no celular Android que será o anfitrião.
2. Conecte todos os aparelhos à mesma rede Wi-Fi.
3. No aplicativo Android, toque em **Criar partida**, informe nome e saldo e inicie.
4. Mantenha o aplicativo aberto. A tela do anfitrião fica ligada durante a partida.
5. Os participantes escaneiam o QR Code com a câmera normal do celular.
6. O link abre no Chrome, Safari ou outro navegador. Basta informar o nome e entrar.

O APK compilado está em:

`build/app/outputs/flutter-apk/app-release.apk`

## Requisitos e limites

- O anfitrião precisa usar Android; os convidados podem usar Android ou iOS.
- Todos devem estar na mesma rede Wi-Fi ou no ponto de acesso do anfitrião.
- A partida não depende de internet nem de servidor externo.
- O aplicativo do anfitrião precisa permanecer aberto. Se ele for encerrado, a sala termina.
- Alguns roteadores ativam “isolamento de clientes”, que impede aparelhos da mesma rede de se enxergarem. Essa opção deve ficar desativada.
- A sala aceita até 20 conexões de navegador.

## Compilar novamente

No Windows, execute `compilar_host_android.bat`. O processo:

1. compila a página web dos participantes;
2. incorpora essa página ao aplicativo do anfitrião;
3. gera o APK Android em modo release.

Também é possível executar diretamente:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\compilar_host_android.ps1
```

Não execute apenas `flutter build apk`: a página web precisa ser compilada e incorporada antes. O script faz as etapas na ordem correta.

## Arquitetura

O aplicativo Android abre um servidor HTTP/WebSocket na porta `8080`. O QR Code aponta para `http://IP-DO-ANFITRIAO:8080/?room=CODIGO`. O navegador baixa a interface web do próprio celular anfitrião e mantém os saldos sincronizados por WebSocket. As regras e o estado oficial da partida permanecem no aplicativo Android.

Os detalhes da revisão técnica estão em [AUDITORIA_WEB.md](AUDITORIA_WEB.md).

<img width="720" height="1600" alt="maquinha_banco" src="https://github.com/user-attachments/assets/a2bb4e7a-3fcb-4fe3-bdb9-05bc68cc6200" />
<img width="720" height="1600" alt="maquinha_banco_inside" src="https://github.com/user-attachments/assets/73e66e1c-63e6-4f0e-ad8a-a3ee28665658" />


