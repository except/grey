//
//  TaskService.swift
//  grey
//
//  Created by Hasan Gondal on 15/12/2019.
//  Copyright © 2019 Hasan Gondal. All rights reserved.
//

import Foundation

import KituraWebSocket

let WSLog = Logger(label: "WSLog")

enum MessageType: Int, Codable {
    case Create = 0
    case Update = 1
    case Setup = 2
    case Start = 3
    case Stop = 4
    case Reset = 5
    case Delete = 6
    case QuickTask = 7
    case SetupAll = 9
    case StartAll = 10
}

struct Message: Codable {
    let messageCode: MessageType
    let createTask: MessageTaskCreate?
    let updateTask: MessageTaskUpdate?
    let quickTask: MessageQuickTask?
    let taskIdentifier: String?
}

struct MessageTaskCreate: Codable {}

struct MessageTaskUpdate: Codable {}

struct MessageQuickTask: Codable {
    let taskType: TaskType
    let variantArray: [Int]
}

enum ResponseType: Int, Codable {
    case ActionSuccess = 200
    case CreatedTask = 201
    case InvalidMessage = 400
    case TaskNotFound = 404
    case CannotActionTask = 406
}

struct Response: Codable {
    var responseCode: ResponseType
    var taskIdentifier: String?
}

struct ConnectionMessage: Codable {
    var taskArray: [TaskInformationMessage]
}

struct TaskInformationMessage: Codable {
    var taskIdentifier: String
}

//var clientConnection: WebSocketConnection?

class TaskService: WebSocketService {
    let connectionTimeout: Int? = 5

    public func connected(connection: WebSocketConnection) {
        connection.send(message: "GREY - Connected")
//        if clientConnection == nil {
//            clientConnection = connection
//            // Send All Tasks
//        } else {
//            connection.close(reason: .userDefined(403), description: "Client Already Connected")
//        }
    }

    public func disconnected(connection _: WebSocketConnection, reason _: WebSocketCloseReasonCode) {
//        clientConnection = nil
    }

    public func received(message: Data, from: WebSocketConnection) {
        do {
            let messages: [Message] = try JSONDecoder().decode([Message].self, from: message)
            var response: [Response] = []
            for message in messages {
                response.append(processMessage(message: message))
            }

            if let data = try? JSONEncoder().encode(response) {
                from.send(message: data)
            }
        } catch {
            from.send(message: "Invalid Message Payload")
        }
    }

    public func received(message: String, from: WebSocketConnection) {
        do {
            let messages: [Message] = try JSONDecoder().decode([Message].self, from: message.data(using: .utf8)!)
            var response: [Response] = []
            for message in messages {
                response.append(processMessage(message: message))
            }

            if let data = try? JSONEncoder().encode(response) {
                from.send(message: String(decoding: data, as: UTF8.self))
            }
        } catch {
            // Update Message
            from.send(message: "Invalid Message Payload")
        }
    }

    func processMessage(message: Message) -> Response {
        switch message.messageCode {
        case .SetupAll:
            for (_, task) in Tasks {
                switch task.taskObj.taskMode {
                case .API:
                    concurrentTaskQueue.async {
                        var setupError = task.setupAPITask()
                        
                        while setupError != nil {
                            if let error = setupError {
                                task.logger.warn(message: "Setup Error - \(error.error) in \(error.state)")
                            }
                            setupError = task.setupAPITask()
                            usleep(UInt32(RetryDelay) * 1000)
                        }
                    }
                }
            }
            WSLog.info(message: "Initiated SetupAll")
            return Response(responseCode: ResponseType.ActionSuccess)
        case .StartAll:
            for (_, task) in Tasks {
                switch task.taskObj.taskMode {
                case .API:
                    if task.setupComplete {
                        concurrentTaskQueue.async {
                            task.startAPITask()
                        }
                    }
                }
            }
            WSLog.info(message: "Initiated StartAll")
            return Response(responseCode: ResponseType.ActionSuccess)
        case .QuickTask:
            if let messageQT = message.quickTask {
                for (_, task) in Tasks {
                    concurrentTaskQueue.async {
                        if (task.taskObj.taskType == messageQT.taskType) {
                            switch task.taskObj.taskType {
                            case .Variant:
                                task.variantArray = task.variantArray.union(Set(messageQT.variantArray))
                            case .Product:
                                WSLog.warn(message: "Product Mode Not Implemented - \(task.taskIdentifier)")
                            }
                        }
                    }
                }
                WSLog.info(message: "Initiated QuickTask")
                return Response(responseCode: ResponseType.ActionSuccess)
            }
            return Response(responseCode: ResponseType.CannotActionTask)
        case .Create:
            WSLog.warn(message: "Create Not Implemented")
        case .Update:
            WSLog.warn(message: "Update Not Implemented")
        case .Setup:
            WSLog.warn(message: "Setup Not Implemented")
        case .Start:
            WSLog.warn(message: "Start Not Implemented")
        case .Stop:
            WSLog.warn(message: "Stop Not Implemented")
        case .Reset:
            WSLog.warn(message: "Reset Not Implemented")
        case .Delete:
            WSLog.warn(message: "Delete Not Implemented")
        }
        
        return Response(responseCode: ResponseType.InvalidMessage, taskIdentifier: "N/A")
    }
}
