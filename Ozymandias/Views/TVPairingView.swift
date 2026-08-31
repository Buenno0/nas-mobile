@preconcurrency import AVFoundation
import SwiftUI
import UIKit

struct TVPairingView: View {
  @Bindable var store: SessionStore
  let session: AuthenticatedSession

  @State private var manualCode = ""
  @State private var isScanning = false
  @State private var isApproving = false
  @State private var approvedDevice: String?
  @State private var errorMessage: String?

  var body: some View {
    ScrollView {
      VStack(spacing: 22) {
        Image(systemName: "tv.and.mediabox")
          .font(.system(size: 54, weight: .medium))
          .foregroundStyle(Color.ozAccent)
        Text("Conectar uma TV").font(.title.bold())
        Text("Na TV, escolha este servidor. Depois escaneie o QR Code que aparecer na tela.")
          .foregroundStyle(Color.ozMuted)
          .multilineTextAlignment(.center)

        if let approvedDevice {
          VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
              .font(.largeTitle)
              .foregroundStyle(Color.ozOkay)
            Text("TV conectada").font(.headline)
            Text(approvedDevice).foregroundStyle(Color.ozMuted)
          }
          .frame(maxWidth: .infinity)
          .padding(22)
          .background(Color.ozOkay.opacity(0.1), in: .rect(cornerRadius: 16))
        } else {
          Button { requestCameraAndScan() } label: {
            Label("Escanear QR Code", systemImage: "qrcode.viewfinder")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .disabled(isApproving)

          HStack {
            Divider()
            Text("ou digite o código").font(.caption).foregroundStyle(Color.ozMuted)
            Divider()
          }

          TextField("ABCD-EFGH", text: $manualCode)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .font(.system(.title2, design: .monospaced))
            .multilineTextAlignment(.center)
            .padding(14)
            .background(Color.ozSurface, in: .rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.ozLine) }

          Button(isApproving ? "Conectando…" : "Autorizar TV") { approve(manualCode) }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isApproving || TVPairingCode.extract(from: manualCode) == nil)
        }

        if let errorMessage {
          Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline)
            .foregroundStyle(Color.ozWarning)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ozWarning.opacity(0.1), in: .rect(cornerRadius: 12))
        }
      }
      .frame(maxWidth: 520)
      .padding(24)
    }
    .background(Color.ozBackground)
    .navigationTitle("Conectar TV")
    .fullScreenCover(isPresented: $isScanning) {
      QRCodeScannerView { value in
        isScanning = false
        approve(value)
      } cancel: {
        isScanning = false
      }
      .ignoresSafeArea()
    }
  }

  private func requestCameraAndScan() {
    errorMessage = nil
    Task {
      if await AVCaptureDevice.requestAccess(for: .video) {
        isScanning = true
      } else {
        errorMessage = "Permita o acesso à câmera nos Ajustes para escanear a TV."
      }
    }
  }

  private func approve(_ value: String) {
    guard !isApproving else { return }
    isApproving = true
    errorMessage = nil
    Task {
      defer { isApproving = false }
      do {
        approvedDevice = try await store.approveTV(code: value, for: session)
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }
}

private struct QRCodeScannerView: UIViewControllerRepresentable {
  let code: (String) -> Void
  let cancel: () -> Void

  func makeUIViewController(context: Context) -> QRScannerViewController {
    QRScannerViewController(code: code, cancel: cancel)
  }

  func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

private final class QRScannerViewController: UIViewController,
  @preconcurrency AVCaptureMetadataOutputObjectsDelegate
{
  private let captureSession = AVCaptureSession()
  private let code: (String) -> Void
  private let cancel: () -> Void
  private var delivered = false

  init(code: @escaping (String) -> Void, cancel: @escaping () -> Void) {
    self.code = code
    self.cancel = cancel
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    guard let camera = AVCaptureDevice.default(for: .video),
      let input = try? AVCaptureDeviceInput(device: camera), captureSession.canAddInput(input)
    else {
      showUnavailable()
      return
    }
    captureSession.addInput(input)
    let output = AVCaptureMetadataOutput()
    guard captureSession.canAddOutput(output) else {
      showUnavailable()
      return
    }
    captureSession.addOutput(output)
    output.setMetadataObjectsDelegate(self, queue: .main)
    output.metadataObjectTypes = [.qr]

    let preview = AVCaptureVideoPreviewLayer(session: captureSession)
    preview.videoGravity = .resizeAspectFill
    preview.frame = view.bounds
    view.layer.addSublayer(preview)

    let guide = UIView()
    guide.layer.borderColor = UIColor.systemOrange.cgColor
    guide.layer.borderWidth = 3
    guide.layer.cornerRadius = 22
    guide.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(guide)
    NSLayoutConstraint.activate([
      guide.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      guide.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      guide.widthAnchor.constraint(equalToConstant: 270),
      guide.heightAnchor.constraint(equalTo: guide.widthAnchor),
    ])

    let close = UIButton(type: .system)
    close.setTitle("Cancelar", for: .normal)
    close.titleLabel?.font = .preferredFont(forTextStyle: .headline)
    close.tintColor = .white
    close.backgroundColor = UIColor.black.withAlphaComponent(0.55)
    close.layer.cornerRadius = 18
    close.addTarget(self, action: #selector(cancelScanning), for: .touchUpInside)
    close.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(close)
    NSLayoutConstraint.activate([
      close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
      close.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
      close.widthAnchor.constraint(equalToConstant: 104),
      close.heightAnchor.constraint(equalToConstant: 44),
    ])

    DispatchQueue.global(qos: .userInitiated).async { [captureSession] in
      captureSession.startRunning()
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    (view.layer.sublayers?.first as? AVCaptureVideoPreviewLayer)?.frame = view.bounds
  }

  func metadataOutput(
    _ output: AVCaptureMetadataOutput,
    didOutput metadataObjects: [AVMetadataObject],
    from connection: AVCaptureConnection
  ) {
    guard !delivered,
      let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
      let value = object.stringValue, TVPairingCode.extract(from: value) != nil
    else { return }
    delivered = true
    captureSession.stopRunning()
    code(value)
  }

  @objc private func cancelScanning() {
    captureSession.stopRunning()
    cancel()
  }

  private func showUnavailable() {
    let label = UILabel(frame: view.bounds)
    label.text = "A câmera não está disponível."
    label.textColor = .white
    label.textAlignment = .center
    view.addSubview(label)
  }
}
