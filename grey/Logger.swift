//
//  Logger.swift
//  grey
//
//  Created by Hasan Gondal on 15/12/2019.
//  Copyright © 2019 Hasan Gondal. All rights reserved.
//

import Foundation

import Rainbow

struct LogConstants {
    static let Info = "[INFO]".green
    static let Warn = "[WARN]".red
}

class Logger {
    let label: String?
    
    let dateFormatter = ISO8601DateFormatter()
    
    init(label: String? = nil) {
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        self.label = label
    }
    
    func info(message: String) {
        var messageLabel = "\(dateFormatter.string(from: Date()))"
        
        if let label = self.label {
            messageLabel = "\(messageLabel) \(label):"
        }
        
        print("\(messageLabel) \(LogConstants.Info) \(message)")
    }
    
    func warn(message: String) {
        var messageLabel = "\(dateFormatter.string(from: Date()))"
        
        if let label = self.label {
            messageLabel = "\(messageLabel) \(label):"
        }
        
        print("\(messageLabel) \(LogConstants.Warn) \(message)")
    }
}
