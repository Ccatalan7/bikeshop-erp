// Cuts a product out of its photo with Apple Vision and saves it as a PNG with
// a transparent background, cropped to the product. Used to place catalog
// products on a colored slide or block (site previews, hero compositions).
//
//   swift scripts/dev/cut_out_product.swift <photo> <out.png> [<photo> <out.png>]...
//
// Clean catalog photos cut well; an infographic keeps its arrows and labels,
// and a product inside a plastic bag keeps the bag. Look at every result before
// using it. The first run compiles for ~10 s; pass all photos in one call.
import CoreImage
import Foundation
import Vision

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2, args.count % 2 == 0 else {
    FileHandle.standardError.write("usage: cut_out_product.swift <photo> <out.png> [<photo> <out.png>]...\n".data(using: .utf8)!)
    exit(2)
}

var failed = false
for pair in stride(from: 0, to: args.count, by: 2) {
    let source = args[pair]
    guard let input = CIImage(contentsOf: URL(fileURLWithPath: source)) else {
        print("\(source): cannot read"); failed = true; continue
    }
    let handler = VNImageRequestHandler(ciImage: input)
    let request = VNGenerateForegroundInstanceMaskRequest()
    do {
        try handler.perform([request])
        guard let result = request.results?.first else {
            print("\(source): no subject found"); failed = true; continue
        }
        let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: true)
        let output = CIImage(cvPixelBuffer: buffer)
        try CIContext().writePNGRepresentation(of: output, to: URL(fileURLWithPath: args[pair + 1]), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        print("\(source): \(Int(output.extent.width))x\(Int(output.extent.height)), \(result.allInstances.count) instance(s)")
    } catch {
        print("\(source): \(error)"); failed = true
    }
}
exit(failed ? 1 : 0)
