import SwiftUI
import AVFoundation

/// A full-screen camera view that scans EAN-13 / ISBN barcodes and
/// returns the decoded string via a callback.
struct BarcodeScannerView: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.onCodeScanned = { code in
            onCodeScanned(code)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    // MARK: - UIKit controller that drives AVCaptureSession

    class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onCodeScanned: ((String) -> Void)?

        private let captureSession = AVCaptureSession()
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private var hasScanned = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            setupCamera()
            addOverlay()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer?.frame = view.bounds
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            if !captureSession.isRunning {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    self?.captureSession.startRunning()
                }
            }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
        }

        private func setupCamera() {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device) else {
                showNoCameraAlert()
                return
            }

            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }

            let metadataOutput = AVCaptureMetadataOutput()
            if captureSession.canAddOutput(metadataOutput) {
                captureSession.addOutput(metadataOutput)
                metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
                metadataOutput.metadataObjectTypes = [.ean13, .ean8]
            }

            let layer = AVCaptureVideoPreviewLayer(session: captureSession)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            previewLayer = layer
        }

        private func addOverlay() {
            // Semi-transparent overlay with a clear cut-out rectangle
            let overlay = ScannerOverlayView()
            overlay.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(overlay)
            NSLayoutConstraint.activate([
                overlay.topAnchor.constraint(equalTo: view.topAnchor),
                overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])

            // Instruction label
            let label = UILabel()
            label.text = "Point camera at a book's barcode"
            label.textColor = .white
            label.font = .systemFont(ofSize: 16, weight: .medium)
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -60),
            ])
        }

        private func showNoCameraAlert() {
            let label = UILabel()
            label.text = "Camera not available"
            label.textColor = .white
            label.font = .systemFont(ofSize: 18, weight: .medium)
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])
        }

        // MARK: - AVCaptureMetadataOutputObjectsDelegate

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !hasScanned,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let code = object.stringValue else { return }

            hasScanned = true
            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            captureSession.stopRunning()
            onCodeScanned?(code)
        }
    }
}

// MARK: - Overlay with scan-window cut-out

private class ScannerOverlayView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        // Fill entire view with semi-transparent black
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.55).cgColor)
        ctx.fill(rect)

        // Cut out a rectangle in the center
        let cutWidth = min(rect.width * 0.75, 300)
        let cutHeight: CGFloat = 160
        let cutRect = CGRect(
            x: (rect.width - cutWidth) / 2,
            y: (rect.height - cutHeight) / 2 - 30,
            width: cutWidth,
            height: cutHeight
        )
        ctx.setBlendMode(.clear)
        ctx.fill(cutRect)

        // Draw corner brackets
        ctx.setBlendMode(.normal)
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(3)
        let bracketLen: CGFloat = 24
        let r = cutRect

        // Top-left
        ctx.move(to: CGPoint(x: r.minX, y: r.minY + bracketLen))
        ctx.addLine(to: CGPoint(x: r.minX, y: r.minY))
        ctx.addLine(to: CGPoint(x: r.minX + bracketLen, y: r.minY))

        // Top-right
        ctx.move(to: CGPoint(x: r.maxX - bracketLen, y: r.minY))
        ctx.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        ctx.addLine(to: CGPoint(x: r.maxX, y: r.minY + bracketLen))

        // Bottom-left
        ctx.move(to: CGPoint(x: r.minX, y: r.maxY - bracketLen))
        ctx.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        ctx.addLine(to: CGPoint(x: r.minX + bracketLen, y: r.maxY))

        // Bottom-right
        ctx.move(to: CGPoint(x: r.maxX - bracketLen, y: r.maxY))
        ctx.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        ctx.addLine(to: CGPoint(x: r.maxX, y: r.maxY - bracketLen))

        ctx.strokePath()
    }
}
