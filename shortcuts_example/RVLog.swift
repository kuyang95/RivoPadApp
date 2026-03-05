//
//  RVLog.swift
//  FirstLanding
//
//  Created by meee on 4/8/25.
//

import os
import Foundation

enum RVLogger {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.rivo.pangmo"
    static let network = Logger(subsystem: subsystem, category: "network")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let core = Logger(subsystem: subsystem, category: "core")
    
    static func d(_ message: String, category: Logger = RVLogger.core, file : String = #fileID, line : Int = #line, function: String = #function){
        let timestamp = currentKSTTimestamp()
        let formatted = "\(timestamp) \(file):\(line)\n▶️ \(message)"
        category.log(level: .debug, "\(formatted)")
    }
    
    static func e(_ message: String, category: Logger = RVLogger.core, file : String = #fileID, line : Int = #line, function: String = #function){
        let timestamp = currentKSTTimestamp()
        let formatted = "\(timestamp) \(file):\(line)\n▶️ \(message)"
        category.log(level: .error, "\(formatted)")
    }
    
    private static func currentKSTTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        return formatter.string(from: Date())
    }
}
