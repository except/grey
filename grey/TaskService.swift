//
//  TaskService.swift
//  grey
//
//  Created by Hasan Gondal on 15/12/2019.
//  Copyright © 2019 Hasan Gondal. All rights reserved.
//

import Foundation

import KituraWebSocket

enum MessageType: Int, Codable {
    case Create = 0
    case Update = 1
    case Login = 2
    case Start = 3
    case Stop = 4
    case Reset = 5
    case Delete = 6
}

struct Message: Codable {
    var messageCode: MessageType
    var createTask: MessageTaskCreate?
    var updateTask: MessageTaskUpdate?
    var taskIdentifier: String?
}

struct MessageTaskCreate: Codable {}

struct MessageTaskUpdate: Codable {}

enum ResponseType: Int, Codable {
    case ActionSuccess = 200
    case CreatedTask = 201
    case InvalidMessage = 400
    case TaskNotFound = 404
    case CannotActionTask = 406
}

struct Response: Codable {
    var responseCode: ResponseType
    var taskIdentifier: String
}

struct ConnectionMessage: Codable {
    var taskArray: [TaskInformationMessage]
}

struct TaskInformationMessage: Codable {
    var taskIdentifier: String
}

var clientConnection: WebSocketConnection?

class TaskService: WebSocketService {
    let connectionTimeout: Int? = 5

    public func connected(connection: WebSocketConnection) {
        if clientConnection == nil {
            clientConnection = connection
            // Send All Tasks
        } else {
            connection.close(reason: .userDefined(403), description: "Client Already Connected")
        }
    }

    public func disconnected(connection _: WebSocketConnection, reason _: WebSocketCloseReasonCode) {
        clientConnection = nil
    }

    public func received(message: Data, from: WebSocketConnection) {
        do {
            let messages: [Message] = try JSONDecoder().decode([Message].self, from: message)
            var response: [Response] = []
            for message in messages {
                response.append(processMessage(message: message))
            }

        } catch {
            // Update Message
            from.send(message: "Invalid Message Payload")
        }
    }

    public func received(message _: String, from: WebSocketConnection) {
        // Update Message
        from.send(message: "Invalid Message, should not be String")
    }

    func processMessage(message _: Message) -> Response {
        return Response(responseCode: ResponseType.ActionSuccess, taskIdentifier: "Test")
    }
}
