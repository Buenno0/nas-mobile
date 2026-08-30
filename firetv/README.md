# Ozymandias para Fire TV

Cliente Android TV nativo para Fire OS 6–8 (Android, `minSdk 25`). Vega OS não é
compatível com este projeto. O app usa tema escuro, navegação por D-pad,
descoberta DNS-SD, pareamento pelo celular e Media3.

## Abrir e compilar

Abra a pasta `firetv/` no Android Studio. O projeto usa SDK/target 36 e Java 21;
o bytecode do app continua compatível com Java 17 e Fire OS 6.

Pelo Terminal:

```bash
cd /Users/buenno/Documents/ChatGPT/nas-mobile/firetv
export ANDROID_HOME="$HOME/Library/Android/sdk"
export JAVA_HOME="/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
./gradlew testDebugUnitTest assembleDebug assembleRelease
```

Os APKs ficam em:

- `app/build/outputs/apk/debug/app-debug.apk`
- `app/build/outputs/apk/release/app-release.apk`

O release deste marco usa a assinatura de desenvolvimento local, adequada para
sideload pessoal e atualizações com `adb install -r`. Antes de publicar na
Amazon Appstore, crie e proteja um keystore de produção.

## Preparar o servidor

Na máquina do NAS, compile a versão atual e inicie o modo local:

```bash
cd /Users/buenno/nas
make web
make install
nas serve --local
```

O servidor anuncia `_ozymandias._tcp.local`; a TV deve estar na mesma rede
Wi-Fi/Ethernet e listar o servidor automaticamente. Também é possível digitar
um IP privado, um host `.local` ou uma URL HTTPS do Cloudflare Tunnel. HTTP
público é recusado.

Ao selecionar o servidor, a TV mostra um código e QR Code. Abra o link no
celular, entre na sua conta se necessário e confirme a TV. Usuário e senha na
TV continuam disponíveis como alternativa.

## Sideload no Fire TV Stick

No Fire TV, habilite **Opções do desenvolvedor > Depuração ADB** e **Instalar
apps desconhecidos**. Descubra o IP em **Configurações > Minha Fire TV > Sobre >
Rede**. Com o Mac e o Stick na mesma rede:

```bash
ADB="$HOME/Library/Android/sdk/platform-tools/adb"
"$ADB" connect IP_DO_FIRE_TV:5555
"$ADB" devices -l
"$ADB" install -r app/build/outputs/apk/release/app-release.apk
"$ADB" shell monkey -p com.buenno.ozymandias.firetv 1
```

Aceite a confirmação de depuração exibida na televisão. Para ver erros do app:

```bash
"$ADB" logcat --pid="$("$ADB" shell pidof com.buenno.ozymandias.firetv)"
```

## Player

O player consulta os decodificadores reais do Stick e informa vídeo, áudio,
container e resolução máxima ao servidor. Ele oferece seek de 10 segundos,
áudio, legendas WebVTT, velocidade e próximo episódio. O progresso é salvo a
cada 10 segundos e também em Pause, Back, Home e término. Em Home, ExoPlayer,
MediaCodec e MediaSession são liberados; ao retornar, o player é reconstruído
na posição salva.

Teste codecs e HDR no aparelho físico. O emulador é útil para layout e D-pad,
mas não representa os decodificadores do Fire TV Stick.
