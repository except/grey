//
//  Proxy.swift
//  grey
//
//  Created by Hasan Gondal on 15/12/2019.
//  Copyright © 2019 Hasan Gondal. All rights reserved.
//

import Foundation

var Proxies: [Proxy] = []
var ProxyStates: [String: ProxyState] = [:]

enum ProxyState: Int, Codable {
    case Free = 0
    case Banned = 1
}

class Proxy: CustomStringConvertible {
    var host: String
    var port: Int
    var authorisation: String?
    init(host: String, port: Int, username: String? = nil, password: String? = nil) {
        self.host = host
        self.port = port

        if let username = username, let password = password {
            authorisation = "\(username):\(password)".data(using: .utf8)?.base64EncodedString()
        }
    }

    func createSessionConfig(existingSessionConfiguration: URLSessionConfiguration?) -> URLSessionConfiguration {
        var sessionConfiguration = existingSessionConfiguration

        if sessionConfiguration == nil {
            sessionConfiguration = URLSessionConfiguration.ephemeral
            sessionConfiguration!.httpAdditionalHeaders = ["User-Agent": UserAgent]
        }

        sessionConfiguration!.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPSEnable: true,
            kCFNetworkProxiesHTTPSProxy: self.host,
            kCFNetworkProxiesHTTPSPort: self.port,
        ]

        if authorisation != nil {
            if (sessionConfiguration!.httpAdditionalHeaders) != nil {
                sessionConfiguration!.httpAdditionalHeaders!["Proxy-Authorization"] = authorisation!
            } else {
                sessionConfiguration!.httpAdditionalHeaders = ["User-Agent": UserAgent, "Proxy-Authorization": "Bearer \(self.authorisation!)"]
            }
        }
        
        return sessionConfiguration!
    }

    var description: String {
        return "http://\(host):\(port)"
    }
}
