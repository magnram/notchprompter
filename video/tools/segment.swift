// Person matte with Apple Vision (VNGeneratePersonSegmentationRequest, .accurate).
// Usage: swift segment.swift <input.mp4> <W> <H> [ema]  -> raw gray8 frames on stdout
import Foundation
import AVFoundation
import Vision
import CoreImage

let args = CommandLine.arguments
let url = URL(fileURLWithPath: args[1])
let W = Int(args[2])!, H = Int(args[3])!
let ema = args.count > 4 ? Float(args[4])! : 0.6
let asset = AVURLAsset(url: url)
let track = asset.tracks(withMediaType: .video)[0]
let reader = try! AVAssetReader(asset: asset)
let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
output.alwaysCopiesSampleData = false
reader.add(output)
reader.startReading()
let req = VNGeneratePersonSegmentationRequest()
req.qualityLevel = .accurate
req.outputPixelFormat = kCVPixelFormatType_OneComponent8
let ctx = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
var prev = [Float](repeating: 0, count: W * H)
var first = true
var n = 0
let out = FileHandle.standardOutput
while let sb = output.copyNextSampleBuffer() {
  guard let pb = CMSampleBufferGetImageBuffer(sb) else { continue }
  try! VNImageRequestHandler(cvPixelBuffer: pb, options: [:]).perform([req])
  let mask = req.results!.first!.pixelBuffer
  let ci = CIImage(cvPixelBuffer: mask)
  let scaled = ci.transformed(by: CGAffineTransform(scaleX: CGFloat(W) / ci.extent.width, y: CGFloat(H) / ci.extent.height))
  var buf = [UInt8](repeating: 0, count: W * H)
  ctx.render(scaled, toBitmap: &buf, rowBytes: W, bounds: CGRect(x: 0, y: 0, width: W, height: H), format: .L8, colorSpace: nil)
  var o = [UInt8](repeating: 0, count: W * H)
  for i in 0..<(W * H) {
    let v = Float(buf[i])
    let m = first ? v : ema * v + (1 - ema) * prev[i]
    prev[i] = m
    o[i] = UInt8(max(0, min(255, m)))
  }
  first = false
  out.write(Data(o))
  n += 1
  if n % 100 == 0 { FileHandle.standardError.write("frames \(n)\n".data(using: .utf8)!) }
}
FileHandle.standardError.write("done \(n) frames\n".data(using: .utf8)!)
