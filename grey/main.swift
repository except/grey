//
//  main.swift
//  grey
//
//  Created by Hasan Gondal on 15/12/2019.
//  Copyright © 2019 Hasan Gondal. All rights reserved.
//

import Foundation

import KituraNet
import KituraWebSocket

import HeliumLogger
import LoggerAPI
import WebKit

var Tasks: [String: Task] = [:]

Log.info("Starting")

HeliumLogger.use(.info)

testFunc()

WebSocket.register(service: TaskService(), onPath: "task")

class TaskServerDelegate: ServerDelegate {
    public func handle(request _: ServerRequest, response _: ServerResponse) {}
}

let server = HTTP.createServer()
server.delegate = TaskServerDelegate()

do {
    try server.listen(on: 8080)
    ListenerGroup.waitForListeners()
} catch {
    Log.error("Error listening on port 8080: \(error).")
}
