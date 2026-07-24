import CryptoKit
import Foundation
import OnnxRuntimeBindings

nonisolated enum ScannerModelError: Error, Equatable, Sendable {
    case modelMissing(String)
    case modelSizeMismatch(fileName: String, expected: Int, actual: Int)
    case modelChecksumMismatch(
        fileName: String,
        expected: String,
        actual: String
    )
    case modelInputMissing(expected: String, actual: [String])
    case modelOutputMissing(expected: String, actual: [String])
    case tensorElementCountMismatch(expected: Int, actual: Int)
    case outputMissing(String)
    case outputShapeMismatch(expected: [Int], actual: [Int])
}

extension ScannerModelError: LocalizedError {
    nonisolated var errorDescription: String? {
        switch self {
        case .modelMissing(let fileName):
            return "Scanner model is missing: \(fileName)"
        case .modelSizeMismatch(let fileName, let expected, let actual):
            return "\(fileName) has \(actual) bytes; expected \(expected)."
        case .modelChecksumMismatch(let fileName, let expected, let actual):
            return "\(fileName) SHA-256 is \(actual); expected \(expected)."
        case .modelInputMissing(let expected, let actual):
            return "Model input \(expected) is missing. Found: \(actual)"
        case .modelOutputMissing(let expected, let actual):
            return "Model output \(expected) is missing. Found: \(actual)"
        case .tensorElementCountMismatch(let expected, let actual):
            return "Tensor has \(actual) values; expected \(expected)."
        case .outputMissing(let name):
            return "ONNX Runtime did not return output \(name)."
        case .outputShapeMismatch(let expected, let actual):
            return "Output shape \(actual) does not match \(expected)."
        }
    }
}

nonisolated enum ScannerModelStore {
    static func locatedURL(
        for descriptor: ScannerModelDescriptor,
        bundle: Bundle = .main
    ) throws -> URL {
        guard let fileURL = locate(descriptor.fileName, in: bundle) else {
            throw ScannerModelError.modelMissing(descriptor.fileName)
        }
        return fileURL
    }

    static func verifiedURL(
        for descriptor: ScannerModelDescriptor,
        bundle: Bundle = .main
    ) throws -> URL {
        let fileURL = try locatedURL(for: descriptor, bundle: bundle)
        try verify(fileURL, descriptor: descriptor)
        return fileURL
    }

    static func verify(
        _ url: URL,
        descriptor: ScannerModelDescriptor
    ) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let actualByteCount = values.fileSize ?? 0
        guard actualByteCount == descriptor.byteCount else {
            throw ScannerModelError.modelSizeMismatch(
                fileName: descriptor.fileName,
                expected: descriptor.byteCount,
                actual: actualByteCount
            )
        }

        let modelData = try Data(contentsOf: url, options: .mappedIfSafe)
        let digest = SHA256.hash(data: modelData)
        let actualHash = digest.map {
            String(format: "%02x", $0)
        }.joined()
        guard actualHash == descriptor.sha256 else {
            throw ScannerModelError.modelChecksumMismatch(
                fileName: descriptor.fileName,
                expected: descriptor.sha256,
                actual: actualHash
            )
        }
    }

    private static func locate(
        _ fileName: String,
        in bundle: Bundle
    ) -> URL? {
        let fileURL = URL(fileURLWithPath: fileName)
        let name = fileURL.deletingPathExtension().lastPathComponent
        let fileExtension = fileURL.pathExtension

        if let direct = bundle.url(
            forResource: name,
            withExtension: fileExtension
        ) {
            return direct
        }

        if let nested = bundle.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "DocumentScan/CustomScanner/Models"
        ) {
            return nested
        }

        return bundle.urls(
            forResourcesWithExtension: fileExtension,
            subdirectory: nil
        )?.first(where: { $0.lastPathComponent == fileName })
    }
}

/// Owns a single ORT environment/session and serializes inference with actor
/// isolation. CPU is the golden parity path; Core ML is the M-series runtime
/// path and retains ORT's CPU fallback for unsupported operators.
actor ScannerONNXSession {
    nonisolated let requestedBackend: ScannerInferenceBackend
    nonisolated let activeBackend: ScannerInferenceBackend
    nonisolated let descriptor: ScannerModelDescriptor

    private let environment: ORTEnv
    private let session: ORTSession

    init(
        descriptor: ScannerModelDescriptor,
        modelURL: URL,
        backend: ScannerInferenceBackend,
        intraOpThreadCount: Int32 = 4
    ) throws {
        try ScannerModelStore.verify(modelURL, descriptor: descriptor)

        let environment = try ORTEnv(loggingLevel: .warning)
        func makeOptions(useCoreML: Bool) throws -> ORTSessionOptions {
            let options = try ORTSessionOptions()
            try options.setIntraOpNumThreads(intraOpThreadCount)
            try options.setGraphOptimizationLevel(.all)
            if useCoreML {
                let coreMLOptions = ORTCoreMLExecutionProviderOptions()
                coreMLOptions.enableOnSubgraphs = true
                coreMLOptions.onlyAllowStaticInputShapes = true
                coreMLOptions.createMLProgram = true
                try options.appendCoreMLExecutionProvider(
                    with: coreMLOptions
                )
            }
            return options
        }

        let shouldTryCoreML =
            backend == .coreML && ORTIsCoreMLExecutionProviderAvailable()
        let session: ORTSession
        let activeBackend: ScannerInferenceBackend
        if shouldTryCoreML {
            do {
                session = try ORTSession(
                    env: environment,
                    modelPath: modelURL.path,
                    sessionOptions: makeOptions(useCoreML: true)
                )
                activeBackend = .coreML
            } catch {
                session = try ORTSession(
                    env: environment,
                    modelPath: modelURL.path,
                    sessionOptions: makeOptions(useCoreML: false)
                )
                activeBackend = .cpuParity
            }
        } else {
            session = try ORTSession(
                env: environment,
                modelPath: modelURL.path,
                sessionOptions: makeOptions(useCoreML: false)
            )
            activeBackend = .cpuParity
        }
        let inputNames = try session.inputNames()
        guard inputNames.contains(descriptor.inputName) else {
            throw ScannerModelError.modelInputMissing(
                expected: descriptor.inputName,
                actual: inputNames
            )
        }
        let outputNames = try session.outputNames()
        guard outputNames.contains(descriptor.outputName) else {
            throw ScannerModelError.modelOutputMissing(
                expected: descriptor.outputName,
                actual: outputNames
            )
        }

        self.requestedBackend = backend
        self.activeBackend = activeBackend
        self.descriptor = descriptor
        self.environment = environment
        self.session = session
    }

    init(
        descriptor: ScannerModelDescriptor,
        bundle: Bundle = .main,
        backend: ScannerInferenceBackend,
        intraOpThreadCount: Int32 = 4
    ) throws {
        let modelURL = try ScannerModelStore.locatedURL(
            for: descriptor,
            bundle: bundle
        )
        try self.init(
            descriptor: descriptor,
            modelURL: modelURL,
            backend: backend,
            intraOpThreadCount: intraOpThreadCount
        )
    }

    func run(_ input: ScannerFloatTensor) throws -> ScannerFloatTensor {
        let expectedElementCount = input.shape.reduce(1, *)
        guard input.values.count == expectedElementCount else {
            throw ScannerModelError.tensorElementCountMismatch(
                expected: expectedElementCount,
                actual: input.values.count
            )
        }

        let inputData = input.values.withUnsafeBufferPointer { values in
            NSMutableData(
                bytes: values.baseAddress!,
                length: values.count * MemoryLayout<Float>.stride
            )
        }
        let inputValue = try ORTValue(
            tensorData: inputData,
            elementType: .float,
            shape: input.shape.map { NSNumber(value: $0) }
        )
        let outputs = try session.run(
            withInputs: [descriptor.inputName: inputValue],
            outputNames: Set([descriptor.outputName]),
            runOptions: nil
        )
        guard let outputValue = outputs[descriptor.outputName] else {
            throw ScannerModelError.outputMissing(descriptor.outputName)
        }

        let shapeInfo = try outputValue.tensorTypeAndShapeInfo()
        let outputShape = shapeInfo.shape.map(\.intValue)
        guard outputShape == descriptor.outputShape else {
            throw ScannerModelError.outputShapeMismatch(
                expected: descriptor.outputShape,
                actual: outputShape
            )
        }

        let outputData = try outputValue.tensorData()
        let data = Data(referencing: outputData)
        let outputValues: [Float] = data.withUnsafeBytes { storage in
            Array(storage.bindMemory(to: Float.self))
        }
        let expectedOutputCount = outputShape.reduce(1, *)
        guard outputValues.count == expectedOutputCount else {
            throw ScannerModelError.tensorElementCountMismatch(
                expected: expectedOutputCount,
                actual: outputValues.count
            )
        }

        return ScannerFloatTensor(
            values: outputValues,
            shape: outputShape
        )
    }
}
