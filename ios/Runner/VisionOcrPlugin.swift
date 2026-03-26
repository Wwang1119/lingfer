import Flutter
import UIKit
import Vision

/// iOS OCR implementation based on Apple Vision.
///
/// This avoids CocoaPods downloading MLKit language models from `dl.google.com`,
/// which may fail on some networks.
public final class VisionOcrPlugin: NSObject, FlutterPlugin {
  private static let channelName = "lingfer/vision_ocr"

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    let instance = VisionOcrPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "recognizeText":
      guard
        let args = call.arguments as? [String: Any],
        let path = args["path"] as? String,
        !path.isEmpty
      else {
        result(FlutterError(code: "bad_args", message: "Missing image path", details: nil))
        return
      }
      recognizeText(atPath: path, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func recognizeText(atPath path: String, result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
      guard let image = UIImage(contentsOfFile: path) else {
        DispatchQueue.main.async {
          result(FlutterError(code: "no_image", message: "Cannot load image", details: path))
        }
        return
      }
      guard let cgImage = image.cgImage else {
        DispatchQueue.main.async {
          result(FlutterError(code: "no_cgimage", message: "Unsupported image", details: nil))
        }
        return
      }

      let request = VNRecognizeTextRequest { request, error in
        if let error = error {
          DispatchQueue.main.async {
            result(FlutterError(code: "vision_error", message: error.localizedDescription, details: nil))
          }
          return
        }

        let observations = request.results as? [VNRecognizedTextObservation] ?? []
        var lines: [String] = []
        lines.reserveCapacity(observations.count)
        for obs in observations {
          if let candidate = obs.topCandidates(1).first {
            lines.append(candidate.string)
          }
        }
        let text = lines.joined(separator: "\n")
        DispatchQueue.main.async { result(text) }
      }

      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      // Prefer Simplified Chinese + English for homework scenes.
      request.recognitionLanguages = ["zh-Hans", "en-US"]

      let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
      do {
        try handler.perform([request])
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "perform_error", message: error.localizedDescription, details: nil))
        }
      }
    }
  }
}

