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

let concurrentTaskQueue = DispatchQueue(label: "TaskQueue", attributes: .concurrent)
let concurrentWHQueue = DispatchQueue(label: "WHQueue", attributes: .concurrent)

struct Config: Codable {
    let proxies: [String]
    let accounts: [TaskObj]
}

struct Account: Codable {
    let accountEmail: String
    let accountPassword: String
}

let MainLog = Logger(label: "main")

var Tasks: [String: Task] = [:]
HeliumLogger.use(.info)

MainLog.info(message: "Starting")

guard let configURL = Bundle.main.url(forResource: "config", withExtension: "json") else {
    MainLog.warn(message: "Config file was not found")
    exit(1)
}

guard let configData = try? Data(contentsOf: configURL) else {
    MainLog.warn(message: "Config data is not available")
    exit(1)
}

guard let config = try? JSONDecoder().decode(Config.self, from: configData) else {
    MainLog.warn(message: "Config data is not valid")
    exit(1)
}

for proxystr in config.proxies {
    let proxyComp = proxystr.components(separatedBy: ":")
    switch proxyComp.count {
    case 2:
        let proxy = Proxy(host: proxyComp[0], port: Int(proxyComp[1])!)
        Proxies.append(proxy)
        ProxyStates[proxy.description] = ProxyState.Free
    case 4:
        let proxy = Proxy(host: proxyComp[0], port: Int(proxyComp[1])!, username: proxyComp[2], password: proxyComp[3])
        Proxies.append(proxy)
        ProxyStates[proxy.description] = ProxyState.Free
    default:
        continue
    }
}

let variants = [
  118633,
  118634,
  118635,
  118636,
  118638,
  118639,
  118640,
  118641,
  118630,
  118631,
  118632,
  118646,
  118647,
  118648,
  118649,
  118650,
  118651,
  118652,
  118653,
  118643,
  118644,
  118645,
  118658,
  118659,
  118660,
  118661,
  118663,
  118664,
  118665,
  118666,
  118655,
  118656,
  118657
]

for var account in config.accounts {
    account.taskPayment = .PayPal
    let task = Task(taskObj: account)
    task.variantArray = Set(variants)
    Tasks[task.taskIdentifier] = task
}

MainLog.info(message: "Loaded \(Tasks.count) Accounts & \(Proxies.count) Proxies")

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
