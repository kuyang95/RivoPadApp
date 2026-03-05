//
//  SpeechToTextManager.swift
//  shortcuts_example
//
//  Created by meee on 2/27/26.
//

import Foundation
import Speech
import AVFoundation
import Combine

final class SpeechToTextManager: NSObject, ObservableObject {
    
    static let shared = SpeechToTextManager()
    
    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
    
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    @Published var isRecording = false
    
    // MARK: - Permission
    
    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
    
    // MARK: - Start Recording
    
    func startRecording(onResult: @escaping (String) -> Void) throws {
        
        stopRecording()
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        
        recognitionRequest.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        isRecording = true
        
        recognitionTask = recognizer?.recognitionTask(with: recognitionRequest) { result, error in
            
            if let result = result {
                let text = result.bestTranscription.formattedString
                
                if result.isFinal {
                    onResult(text)
                    self.stopRecording()
                }
            }
            
            if error != nil {
                self.stopRecording()
            }
        }
    }
    
    // MARK: - Stop
    
    func stopRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        recognitionTask = nil
        recognitionRequest = nil
        
        isRecording = false
    }
}
