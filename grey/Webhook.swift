//
//  Webhook.swift
//  grey
//
//  Created by Hasan Gondal on 20/12/2019.
//  Copyright © 2019 Hasan Gondal. All rights reserved.
//

import Foundation

struct SlackWebhook: Codable {
    let attachments: [Attachment]
}

struct Attachment: Codable {
    let fallback: String
    let color, text, title: String
    let titleLink: String
    let fields: [WebhookField]
    let thumbURL: String

    enum CodingKeys: String, CodingKey {
        case fallback, color, text, title
        case titleLink = "title_link"
        case fields
        case thumbURL = "thumb_url"
    }
}

struct WebhookField: Codable {
    let title, value: String
    let short = false
}


class Webhook {
    var url: URL
    init(url: URL) {
        self.url = url
    }
    
    public func send(webhook: SlackWebhook, logger: Logger) {
        var request = URLRequest(url: self.url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let webhookObj = try? JSONEncoder().encode(webhook) else {
            logger.warn(message: "Webhook encode error")
            return
        }
        request.httpBody = webhookObj
        
        URLSession.shared.dataTask(with: request) {_, response, error in
            guard let response = response as? HTTPURLResponse else {
                if let error = error {
                    logger.warn(message: "Webhook request error - \(error)")
                }
                return
            }
            
            switch response.statusCode {
            case 200:
                logger.info(message: "Webhook Sent")
                return
            case 429:
                sleep(5)
                logger.warn(message: "Rate Limited - \(response.statusCode)")
                return self.send(webhook: webhook, logger: logger)
            default:
                logger.warn(message: "Invalid Status - \(response.statusCode)")
                return
            }
        }.resume()
    }
}
