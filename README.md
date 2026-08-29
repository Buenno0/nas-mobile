# Ozymandias para iOS

Cliente SwiftUI do servidor de mídia Ozymandias. Este primeiro marco inclui descoberta manual do servidor, validação por `/healthz`, login Bearer, sessão no Keychain, restauração e logout.

## Requisitos

- macOS 27
- Xcode 27 beta em `/Applications/Xcode-beta.app`
- simulador iOS 27 (o deployment target do app é iOS 26)

Selecione o Xcode uma vez no terminal:

```sh
sudo xcode-select --switch /Applications/Xcode-beta.app/Contents/Developer
```

## Executar

Inicie o servidor:

```sh
nas serve --local
```

Abra `Ozymandias.xcodeproj`, selecione um simulador de iPhone e execute. No simulador, o endereço padrão é `http://localhost:8787`. Em um iPhone físico, use o endereço de rede local exibido pelo comando `nas`.

## Testes

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild test \
  -project Ozymandias.xcodeproj \
  -scheme Ozymandias \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Os testes de interface usam respostas locais determinísticas quando o app recebe `--ui-testing`; o app normal sempre usa `URLSession` e o Keychain reais.
