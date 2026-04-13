import Flutter
import ImageIO
import UIKit
import Vision

/// iOS OCR implementation based on Apple Vision.
///
/// This avoids CocoaPods downloading MLKit language models from `dl.google.com`,
/// which may fail on some networks. It also exposes per-line layout data so the
/// Flutter scan reader can place a transparent selectable text layer over the
/// original image.
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
    case "recognizeTextLayout":
      guard
        let args = call.arguments as? [String: Any],
        let path = args["path"] as? String,
        !path.isEmpty
      else {
        result(FlutterError(code: "bad_args", message: "Missing image path", details: nil))
        return
      }
      recognizeTextLayout(atPath: path, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func recognizeText(atPath path: String, result: @escaping FlutterResult) {
    performRecognition(atPath: path) { payload, error in
      if let error {
        result(error)
      } else if let payload {
        let lines = payload["lines"] as? [[String: Any]] ?? []
        let text = lines
          .compactMap { $0["text"] as? String }
          .joined(separator: "\n")
        result(text)
      }
    }
  }

  private func recognizeTextLayout(atPath path: String, result: @escaping FlutterResult) {
    performRecognition(atPath: path) { payload, error in
      if let error {
        result(error)
      } else if let payload {
        result(payload)
      }
    }
  }

  private func performRecognition(
    atPath path: String,
    completion: @escaping ([String: Any]?, FlutterError?) -> Void
  ) {
    DispatchQueue.global(qos: .userInitiated).async {
      guard let image = UIImage(contentsOfFile: path) else {
        DispatchQueue.main.async {
          completion(
            nil,
            FlutterError(code: "no_image", message: "Cannot load image", details: path)
          )
        }
        return
      }
      guard let cgImage = image.cgImage else {
        DispatchQueue.main.async {
          completion(
            nil,
            FlutterError(code: "no_cgimage", message: "Unsupported image", details: nil)
          )
        }
        return
      }

      let imageWidth = CGFloat(cgImage.width)
      let imageHeight = CGFloat(cgImage.height)
      let orientation = Self.cgImageOrientation(for: image.imageOrientation)

      let request = VNRecognizeTextRequest { request, error in
        if let error = error {
          DispatchQueue.main.async {
            completion(
              nil,
              FlutterError(
                code: "vision_error",
                message: error.localizedDescription,
                details: nil
              )
            )
          }
          return
        }

        let observations = request.results as? [VNRecognizedTextObservation] ?? []
        var linesPayload: [[String: Any]] = []
        linesPayload.reserveCapacity(observations.count)

        for observation in observations {
          guard let candidate = observation.topCandidates(1).first else { continue }

          let rawLines = candidate.string
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

          let lineCount = max(rawLines.count, 1)
          let normalizedBox = observation.boundingBox
          let lineHeight = normalizedBox.height / CGFloat(lineCount)
          let topFromTop = 1.0 - normalizedBox.minY - normalizedBox.height

          for (index, lineText) in rawLines.enumerated() {
            let lineTop = topFromTop + (CGFloat(index) * lineHeight)
            linesPayload.append([
              "text": lineText,
              "left": normalizedBox.minX * imageWidth,
              "top": lineTop * imageHeight,
              "width": normalizedBox.width * imageWidth,
              "height": lineHeight * imageHeight,
            ])
          }
        }

        let payload: [String: Any] = [
          "text": linesPayload
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n"),
          "imageWidth": Double(imageWidth),
          "imageHeight": Double(imageHeight),
          "lines": linesPayload,
        ]

        DispatchQueue.main.async {
          completion(payload, nil)
        }
      }

      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      request.recognitionLanguages = ["zh-Hans", "en-US"]

      let handler = VNImageRequestHandler(
        cgImage: cgImage,
        orientation: orientation,
        options: [:]
      )
      do {
        try handler.perform([request])
      } catch {
        DispatchQueue.main.async {
          completion(
            nil,
            FlutterError(
              code: "perform_error",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    }
  }

  private static func cgImageOrientation(for orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
    switch orientation {
    case .up:
      return .up
    case .down:
      return .down
    case .left:
      return .left
    case .right:
      return .right
    case .upMirrored:
      return .upMirrored
    case .downMirrored:
      return .downMirrored
    case .leftMirrored:
      return .leftMirrored
    case .rightMirrored:
      return .rightMirrored
    @unknown default:
      return .up
    }
  }
}
