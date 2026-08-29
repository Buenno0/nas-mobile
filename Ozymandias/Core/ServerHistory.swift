import Foundation

struct ServerHistory {
  private let defaults: UserDefaults
  private let key = "recentServers"

  init(defaults: UserDefaults) {
    self.defaults = defaults
  }

  func load() -> [String] {
    defaults.stringArray(forKey: key) ?? []
  }

  func remember(_ url: URL) {
    let value = url.absoluteString
    let history = [value] + load().filter { $0 != value }
    defaults.set(Array(history.prefix(3)), forKey: key)
  }
}
