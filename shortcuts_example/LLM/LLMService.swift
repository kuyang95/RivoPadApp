//
//  LLMService.swift
//  shortcuts_example
//
//  Created by meee on 2/5/26.
//

import Foundation
import MLXLMCommon
import MLX  // cacheLimit
import MLXLLM
import MLXVLM
import Combine
import CoreImage


enum LoadedModel: Equatable {
    case none
    case qwen3_8b_4bit
    case qwen3_vl_8b_4bit
    
    var displayName: String {
        switch self {
        case .none: return "None"
        case .qwen3_8b_4bit: return "Qwen3-8B-4bit"
        case .qwen3_vl_8b_4bit: return "Qwen3-VL-8B-Instruct-4bit"
        }
    }
}

@MainActor
final class LLMService: ObservableObject {
    
    static let shared = LLMService()
    
    @Published var isLoading = false
    @Published var isGenerating = false
    @Published private(set) var loadedModel: LoadedModel = .none

    var isReady: Bool {
        session != nil && loadedModel != .none && isLoading == false
    }

    private var session: ChatSession?

    
    
    @MainActor
    func loadLocalModelFromBundle() async throws -> ChatSession {
        // 예: 앱 번들에 Resources/Models/Qwen3-8B-4bit/ ... 형태로 넣었다고 가정
        let modelDir = Bundle.main.resourceURL!
            .appendingPathComponent("Models")
            .appendingPathComponent("Qwen3-8B-4bit")

        // let hub = HubApi() // 예제에서도 로컬 디렉터리 로드여도 HubApi를 전달
        let cfg = ModelConfiguration(directory: modelDir)

        let container = try await LLMModelFactory.shared.loadContainer(
            configuration: cfg
        )

        return ChatSession(container)
    }
    
    func configureForIPadProM4_8GB() {
        let gb = 1024 * 1024 * 1024

        // ✅ 8GB 기기 권장 스타팅 포인트
        // - memoryLimit: 5GB (안정성 우선)
        // - cacheLimit : 384MB (속도/안정 밸런스)
        MLX.Memory.memoryLimit = 5 * gb
        MLX.Memory.cacheLimit  = 512 * 1024 * 1024
    }

    /// 앱 시작 시 1번만 호출 추천
    func configureMemory() {
        // LLMEval 권장값: 20MB 캐시 제한
        MLX.Memory.cacheLimit = 20 * 1024 * 1024
    }

    func loadQwen3_8B() async throws {
        if isLoading { return }
        if loadedModel == .qwen3_8b_4bit, session != nil { return } // ✅ 이미 로드됨
        
        isLoading = true
        defer { isLoading = false }
        
        let model = try await loadModel(id: "mlx-community/Qwen3-8B-4bit")
        self.session = ChatSession(model)
        self.loadedModel = .qwen3_8b_4bit
    }

    func loadQwen3_VL_8B() async throws {
        if isLoading { return }
        if loadedModel == .qwen3_vl_8b_4bit, session != nil { return } // ✅ 이미 로드됨
        
        isLoading = true
        defer { isLoading = false }
        
        let model = try await loadModel(id: "mlx-community/Qwen3-VL-8B-Instruct-4bit")
        self.session = ChatSession(model)
        self.loadedModel = .qwen3_vl_8b_4bit
    }
    
    func ensureLoaded(_ target: LoadedModel) async throws {
        switch target {
        case .none:
            return
        case .qwen3_8b_4bit:
            try await loadQwen3_8B()
        case .qwen3_vl_8b_4bit:
            try await loadQwen3_VL_8B()
        }
    }

    /// 단발(완성된 문자열) 응답
    func respond(_ prompt: String) async throws -> String {
        guard let session else { throw NSError(domain: "LLM", code: 1) }
        isGenerating = true
        defer { isGenerating = false }
        return try await session.respond(to: prompt)
    }

    /// 스트리밍(토큰/조각) 응답
    func stream(_ prompt: String) async throws -> AsyncThrowingStream<String, Error> {
     
        // 선 지시문 여기다 넣기
         session?.instructions = "너는 한국어로 답해주는 챗봇이야. 유저가 \"Document:\" 뒤에오는 내용은 참고할 문서고, 후에 \"Quesiton:\" 뒤에 오는것은 질문이야. 그거에 답변해주면돼"
       // session?.generateParameters
        guard let session else { throw NSError(domain: "LLM", code: 1) }
        // MLXLMCommon에서 respond(to:) / streamResponse(to:) 둘 다 지원
        return session.streamResponse(to: prompt)
    }
    
    // MARK: - Streaming (Text Only)

     /// ✅ 텍스트 전용 스트리밍
     /// - Parameters:
     ///   - system: 선 지시문(시스템 프롬프트)
     ///   - prompt: 유저 프롬프트(문서 포함 prompt를 만들면 여기에 넣기)
     func streamText(system: String, prompt: String) async throws -> AsyncThrowingStream<String, Error> {
         guard let session else { throw NSError(domain: "LLM", code: 1) }

         session.instructions = system

         // (옵션) 여기서 generateParameters 조정 가능
         // var gp = session.generateParameters
         // gp.maxTokens = 512
         // gp.temperature = 0.2
         // session.generateParameters = gp

         return session.streamResponse(to: prompt)
     }

     // MARK: - Streaming (Vision)

     /// ✅ 이미지 포함(VLM) 스트리밍
     /// - Parameters:
     ///   - system: 선 지시문(시스템 프롬프트)
     ///   - prompt: 유저 프롬프트
     ///   - images: CIImage 배열(고정 이미지면 1장만 넣어도 됨)
     func streamVision(system: String, prompt: String, images: [CIImage]) async throws -> AsyncThrowingStream<String, Error> {
         guard let session else { throw NSError(domain: "LLM", code: 1) }

         session.instructions = system

         // (옵션) VLM은 리사이즈를 낮추는 게 iPad에서 안정적일 때가 많음
         // session.processing = .init(resize: CGSize(width: 448, height: 448))  // 세션 생성 시 넣는게 더 깔끔

         let uiImages: [UserInput.Image] = images.map { .ciImage($0) }

         // ✅ ChatSession 오버로드: images/videos 지원
         return session.streamResponse(to: prompt, images: uiImages, videos: [])
     }
}
