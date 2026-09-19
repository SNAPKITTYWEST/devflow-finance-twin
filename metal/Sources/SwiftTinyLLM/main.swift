import Foundation

let args = CommandLine.arguments
var port: UInt16 = 8080
var checkpoint: URL? = nil
var i = 1
while i < args.count {
    switch args[i] {
    case "--port" where i + 1 < args.count:
        port = UInt16(args[i+1]) ?? 8080; i += 2
    case "--checkpoint" where i + 1 < args.count:
        checkpoint = URL(fileURLWithPath: args[i+1]); i += 2
    default: i += 1
    }
}

let model: TinyTransformer
if let checkpoint, FileManager.default.fileExists(atPath: checkpoint.path) {
    model = try TinyTransformer.load(from: checkpoint)
    print("Loaded checkpoint: \(checkpoint.path)")
} else {
    model = TinyTransformer()
    if let checkpoint {
        try model.save(to: checkpoint)
        print("Initialized and saved checkpoint: \(checkpoint.path)")
    }
}
print("Parameters: \(model.parameterCount)")
let engine = ModelEngine(model: model)
try TinyHTTPServer(port: port, engine: engine).run()
