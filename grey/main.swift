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

var Tasks: [String: Task] = [:]

let task = Task(taskObj: TaskObj(taskMode: TaskMode.API, taskType: TaskType.Product, accountEmail: "hasan@loserspay.tax", accountPassword: "TrelloUnique12"))
print(task.login())
print(task.addToCart(variantID: 115604))

HeliumLogger.use(.info)

WebSocket.register(service: TaskService(), onPath: "task")

class TaskServerDelegate: ServerDelegate {
    public func handle(request: ServerRequest, response: ServerResponse) {}
}

let server = HTTP.createServer()
server.delegate = TaskServerDelegate()

do {
    try server.listen(on: 8080)
    ListenerGroup.waitForListeners()
} catch {
    Log.error("Error listening on port 8080: \(error).")
}
