import SwiftUI

// MARK: - Véu

/// Escurece a arte o suficiente para o texto viver em cima dela e a dissolve no
/// fundo da tela. As paradas seguem uma curva suave em vez de uma rampa linear:
/// com poucas paradas lineares aparece uma faixa horizontal de sujeira onde o
/// preto translúcido encontra os tons médios da foto.
struct HeroScrim: View {
  /// Onde o escurecimento começa, em fração da altura do banner.
  var start: CGFloat = 0.34

  var body: some View {
    ZStack {
      // Faixa curta no topo: só o bastante para relógio e indicadores ficarem
      // legíveis sobre uma foto clara.
      LinearGradient(
        stops: [
          .init(color: .black.opacity(0.38), location: 0),
          .init(color: .black.opacity(0.16), location: 0.06),
          .init(color: .clear, location: 0.16),
        ],
        startPoint: .top,
        endPoint: .bottom
      )

      LinearGradient(stops: bottomStops, startPoint: .top, endPoint: .bottom)
    }
    .allowsHitTesting(false)
  }

  /// Amostra uma curva suave (smoothstep) para não haver emenda visível.
  private var bottomStops: [Gradient.Stop] {
    let samples = 12
    return (0...samples).map { index in
      let t = CGFloat(index) / CGFloat(samples)
      let location = start + (1 - start) * t
      let eased = t * t * (3 - 2 * t)
      return .init(color: Color.ozBackground.opacity(Double(eased)), location: location)
    }
  }
}

// MARK: - Metadados

/// A linha acima do título: `FILME · 2026 · 2 h`. Substitui a pílula de vidro —
/// a HIG diz para não usar Liquid Glass na camada de conteúdo, e a pílula era
/// decoração, não controle.
struct HeroMetadataLine: View {
  let parts: [String]

  var body: some View {
    // Sem `.textCase(.uppercase)` na linha inteira: ela transformaria "2 h" em
    // "2 H". Quem chama maiusculiza só o que deve — o tipo da mídia.
    Text(parts.joined(separator: " · "))
      .font(.caption.weight(.semibold))
      .tracking(0.7)
      .foregroundStyle(.white.opacity(0.78))
      .lineLimit(1)
      .minimumScaleFactor(0.8)
  }
}

// MARK: - Título

struct HeroTitle: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.system(.largeTitle, design: .default, weight: .bold))
      .foregroundStyle(.white)
      .lineLimit(2)
      .minimumScaleFactor(0.72)
      .fixedSize(horizontal: false, vertical: true)
  }
}

// MARK: - Botões

/// Ação primária: cápsula dimensionada pelo conteúdo. A HIG é explícita —
/// "Avoid full-width buttons" — e o `.frame(maxWidth: .infinity)` anterior dava
/// a ela cara de CTA de página web.
struct HeroPlayButton: View {
  var title: String
  var systemImage: String = "play.fill"
  var isBusy = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        if isBusy {
          ProgressView().controlSize(.small).tint(.black)
        } else {
          Image(systemName: systemImage).font(.subheadline.weight(.bold))
        }
        Text(title).font(.subheadline.weight(.semibold))
      }
      .padding(.horizontal, 6)
      .frame(minWidth: 122, minHeight: 26)
    }
    .buttonStyle(.glassProminent)
    .buttonBorderShape(.capsule)
    // Neutro em vez do âmbar da marca: a HIG pede cor com parcimônia sobre
    // conteúdo colorido, e é assim que a ação primária aparece sobre pôsteres.
    .tint(.white)
    .foregroundStyle(.black)
    .controlSize(.large)
    .contentShape(.capsule)
    .disabled(isBusy)
  }
}

extension View {
  /// Estilo da ação secundária circular do banner. É um modificador e não uma
  /// view porque `NavigationLink` também é um botão e precisa do mesmo visual.
  func heroIconButtonStyle() -> some View {
    buttonStyle(.glass)
      .buttonBorderShape(.circle)
      .tint(.white)
      // O vidro só registra toque no conteúdo, não na área da cápsula.
      .contentShape(.circle)
  }
}

/// Ícone da ação secundária. 44 pt é o mínimo de área de toque da HIG, e
/// mantém a fila do detalhe (1 cápsula + 3 círculos) dentro da largura.
struct HeroIconLabel: View {
  let systemImage: String

  var body: some View {
    Image(systemName: systemImage)
      .font(.system(size: 17, weight: .semibold))
      .frame(width: 44, height: 44)
  }
}

/// Fila de ações do banner. O `GlassEffectContainer` não é enfeite: vidro não
/// consegue amostrar outro vidro, e elementos de vidro vizinhos em containers
/// diferentes renderizam de forma inconsistente (WWDC25 323).
struct HeroActionRow<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    GlassEffectContainer(spacing: 10) {
      HStack(spacing: 10) { content }
    }
  }
}

// MARK: - Banner

/// Banner de largura total que passa por trás da status bar e da Dynamic
/// Island. O conteúdo fica ancorado embaixo, longe da ilha, e respeita a safe
/// area horizontal.
struct HeroBanner<Background: View, Content: View>: View {
  /// Largura disponível. A altura sai de uma proporção dela, e não da altura da
  /// tela: assim o banner acompanha o tamanho do iPhone sem depender de quanto
  /// a safe area ou a tab bar comeram do container.
  var containerWidth: CGFloat
  /// Deslocamento vertical do scroll; negativo quando o usuário puxa para baixo.
  var scrollOffset: CGFloat = 0
  var aspectRatio: CGFloat = 1.16
  var minimumHeight: CGFloat = 380
  var maximumHeight: CGFloat = 640
  @ViewBuilder var background: Background
  @ViewBuilder var content: Content

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var pull: CGFloat { reduceMotion ? 0 : max(-scrollOffset, 0) }

  private var height: CGFloat {
    min(max(containerWidth * aspectRatio, minimumHeight), maximumHeight)
  }

  var body: some View {
    // Véu e conteúdo entram como `overlay`, não como irmãos de um ZStack: um
    // ZStack adota a largura do maior filho, então uma fila de botões larga
    // demais esticava a caixa e deixava a arte — presa ao leading — com uma
    // faixa vazia na direita.
    background
      .frame(width: containerWidth, height: height)
      // Acompanha o dedo 1:1: animar aqui deixaria a borracha atrasada.
      .scaleEffect(1 + min(pull, 260) / 900, anchor: .bottom)
      .clipped()
      .overlay { HeroScrim() }
      .overlay(alignment: .bottomLeading) {
        content
          .padding(.horizontal, 20)
          .padding(.bottom, 22)
      }
      .frame(width: containerWidth, height: height)
      .clipped()
    // A safe area do topo é ignorada por quem hospeda o banner (ver
    // `HomeView`), então aqui a altura já vale a partir de y = 0.
  }
}

// MARK: - Rastreio do scroll

extension View {
  /// Publica o quanto o scroll passou do topo, para o banner esticar junto.
  func heroScrollOffset(_ offset: Binding<CGFloat>) -> some View {
    onScrollGeometryChange(for: CGFloat.self) { geometry in
      min(geometry.contentOffset.y + geometry.contentInsets.top, 0)
    } action: { _, value in
      offset.wrappedValue = value
    }
  }
}
