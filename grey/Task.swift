//
//  Task.swift
//  grey
//
//  Created by Hasan Gondal on 15/12/2019.
//  Copyright © 2019 Hasan Gondal. All rights reserved.
//

import Foundation

import SwiftSoup

var UserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 13_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.4 Mobile/15E148 Safari/604.1"

enum TaskMode: Int, Codable {
    case Safe = 0
    case API = 1
}

enum TaskType: Int, Codable {
    case Product = 0
    case Variant = 1
}

enum TaskState: Int, Codable {
    case Idle = 0
    case LoggingIn = 1
    case LoggedIn = 2
    case InvalidCredentials = 3
    case AwaitingProduct = 4
    case ProductOOS = 5
    case AwaitingCaptcha = 6
    case ItemCarted = 7
    case GettingShipping = 8
    case SubmittingShipping = 9
    case SubmittingDelivery = 10
    case AdvancingAPICheckout = 11
    case SubmittingPayment = 12
    case CardDeclined = 13
    case OrderComplete = 14
}

enum TaskError: Error {
    case VaritiFailure
    case NilResponse
    case NilResponseData
    case InvalidCredentials
    case InvalidStatusCode
    case TaskBanned
    case EncodingError
    case DecodingError
    case ProductOOS
    case NoCSRF
    case SwiftSoupError
    case CartNotEmpty
    case NoAPIKey
    case InvalidAPIKey
    case InvalidAPIResponse
    case NoOrderIdentifier
    case TooManyOrderIdentifiers
}

enum TaskOrderState: String, Codable {
    case Cart = "cart"
    case Address = "address"
    case Delivery = "delivery"
    case Payment = "payment"
    case Complete = "complete"
}

struct TaskObj: Codable {
    var taskMode: TaskMode
    var taskType: TaskType
    var accountEmail: String
    var accountPassword: String
    var accountUser: User?
    var billingAddress: Address?
    var shippingAddress: Address?
    var csrfToken: String?
    var clearedCart: Bool = false
    var orderIdentifiers: OrderIdentifiers?
}

struct LoginResponse: Codable {
    let user: User
    let shipAddress, billAddress: Address

    enum CodingKeys: String, CodingKey {
        case user
        case shipAddress = "ship_address"
        case billAddress = "bill_address"
    }
}

struct Address: Codable {
    let id: Int
    let firstname, lastname, address1, address2: String
    let city, zipcode, phone: String
    let countryID: Int
    let hsFiscalCode: String?

    enum CodingKeys: String, CodingKey {
        case id, firstname, lastname, address1, address2, city, zipcode, phone
        case countryID = "country_id"
        case hsFiscalCode = "hs_fiscal_code"
    }
}

struct User: Codable {
    let id: Int
    let email: String
    let shipAddressID, billAddressID: Int
    let spreeAPIKey: String
    let hsCountryID: Int

    enum CodingKeys: String, CodingKey {
        case id, email
        case shipAddressID = "ship_address_id"
        case billAddressID = "bill_address_id"
        case spreeAPIKey = "spree_api_key"
        case hsCountryID = "hs_country_id"
    }
}

struct ATCResponse: Codable {
    let lineItem: ATCResponseLineItem
    let cart: Cart

    enum CodingKeys: String, CodingKey {
        case lineItem = "line_item"
        case cart
    }
}

struct Cart: Codable {
    let itemCount: Int
    let lineItems: [CartLineItem]
    let signedIn: Bool

    enum CodingKeys: String, CodingKey {
        case itemCount = "item_count"
        case lineItems = "line_items"
        case signedIn = "signed_in"
    }
}

struct CartLineItem: Codable {
    let variantID: Int
    let imageURL: String
    let name, designerName, url: String
    let quantity: Int

    enum CodingKeys: String, CodingKey {
        case variantID = "variant_id"
        case imageURL = "image_url"
        case name
        case designerName = "designer_name"
        case url, quantity
    }
}

struct ATCResponseLineItem: Codable {
    let orderID, variantID, quantity: Int

    enum CodingKeys: String, CodingKey {
        case orderID = "order_id"
        case variantID = "variant_id"
        case quantity
    }
}

struct OrderAPIResponse: Codable {
    let count, currentPage, pages: Int
    let orders: [OrderIdentifiers]

    enum CodingKeys: String, CodingKey {
        case count
        case currentPage = "current_page"
        case pages, orders
    }
}

struct OrderIdentifiers: Codable {
    var id: Int
    var number: String
    var state: TaskOrderState
}

class Task {
    typealias CompletionHandler = (_ data: Data?, _ response: HTTPURLResponse?, _ error: Error?) -> Void

    var taskState: TaskState = TaskState.Idle

    var taskIdentifier: String
    var session: URLSession
    var logger: Logger
    var taskObj: TaskObj

    init(taskObj: TaskObj) {
        self.taskObj = taskObj
        taskIdentifier = UUID().uuidString.lowercased()
        logger = Logger(label: "Task \(taskIdentifier)")

        var config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.httpAdditionalHeaders = ["User-Agent": UserAgent]

        if Proxies.count > 0 {
            for _ in 1 ... 5 {
                if let proxy = Proxies.randomElement() {
                    if ProxyStates[proxy.description] == ProxyState.Free {
                        config = proxy.createSessionConfig(existingSessionConfiguration: config)
                        break
                    }
                }
            }
        }

        session = URLSession(configuration: config)
    }

    private func doRequest(request: URLRequest, completionHandler: @escaping CompletionHandler) {
        session.dataTask(with: request) { data, response, error in
            guard let data = data, let response = response as? HTTPURLResponse else {
                self.logger.warn(message: "Request Error - \(error!)")
                completionHandler(nil, nil, error)
                return
            }

            if let serverName = response.allHeaderFields["Server"] as? String {
                if serverName.contains("Variti") {
                    self.logger.warn(message: "Detected Challenge - \(serverName)")
                    let responseHTML = String(data: data, encoding: .utf8)!

                    let cookieArray = solveVariti(response: responseHTML)

                    if cookieArray.count > 0 {
                        for cookie in cookieArray {
                            self.session.configuration.httpCookieStorage?.setCookie(cookie)
                        }

                        self.logger.info(message: "Solved Attempted - \(serverName)")
                    } else {
                        self.logger.info(message: "Solve Failed - \(serverName)")
                    }

                    return self.doRequest(request: request, completionHandler: completionHandler)
                }
            }

            completionHandler(data, response, error)
        }.resume()
    }

    private func rotateProxy() {
        for _ in 1 ... 5 {
            if let proxy = Proxies.randomElement() {
                if ProxyStates[proxy.description] == ProxyState.Free {
                    let config = proxy.createSessionConfig(existingSessionConfiguration: session.configuration)
                    config.httpAdditionalHeaders?["User-Agent"] = UserAgent
                    session = URLSession(configuration: config)
                    logger.info(message: "Set Proxy - \(proxy)")
                    break
                }
            }
        }
    }

    public func login() -> (Bool, Error?) {
        var isLoggedIn = false
        var loginError: Error?
        let semaphore = DispatchSemaphore(value: 0)

        var request = URLRequest(url: URL(string: "https://www.off---white.com/en/GB/login")!)
        request.httpMethod = "POST"
        request.setValue("application/javascript", forHTTPHeaderField: "Accept")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")

        let loginObj = ["spree_user": ["email": self.taskObj.accountEmail, "password": self.taskObj.accountPassword, "remember_me": 1]]
        guard let serializedBody = try? JSONSerialization.data(withJSONObject: loginObj, options: .prettyPrinted) else {
            return (isLoggedIn, TaskError.EncodingError)
        }

        request.httpBody = serializedBody

        doRequest(request: request) { data, response, error in
            if error != nil {
                loginError = error
                semaphore.signal()
                return
            }

            guard let response = response else {
                loginError = TaskError.NilResponse
                semaphore.signal()
                return
            }

            guard let data = data else {
                loginError = TaskError.NilResponseData
                semaphore.signal()
                return
            }

            switch response.statusCode {
            case 200:
                guard let responseObj = try? JSONDecoder().decode(LoginResponse.self, from: data) else {
                    loginError = TaskError.DecodingError
                    semaphore.signal()
                    return
                }

                isLoggedIn = true

                self.taskObj.accountUser = responseObj.user
                self.taskObj.billingAddress = responseObj.billAddress
                self.taskObj.shippingAddress = responseObj.shipAddress
            case 403:
                loginError = TaskError.TaskBanned
            case 422:
                loginError = TaskError.InvalidCredentials
            default:
                loginError = TaskError.InvalidStatusCode
            }

            semaphore.signal()
        }

        semaphore.wait()
        return (isLoggedIn, loginError)
    }

    public func getCSRF() -> (Bool, Error?) {
        var obtainedCSRF = false
        var csrfError: Error?
        let semaphore = DispatchSemaphore(value: 0)

        let request = URLRequest(url: URL(string: "https://www.off---white.com/en/GB/cart")!)

        doRequest(request: request) { data, response, error in
            if error != nil {
                csrfError = error
                semaphore.signal()
                return
            }

            guard let response = response else {
                csrfError = TaskError.NilResponse
                semaphore.signal()
                return
            }

            guard let data = data else {
                csrfError = TaskError.NilResponseData
                semaphore.signal()
                return
            }

            switch response.statusCode {
            case 200:
                let html = String(data: data, encoding: .utf8)!

                guard let doc: Document = try? SwiftSoup.parse(html) else {
                    csrfError = TaskError.SwiftSoupError
                    semaphore.signal()
                    return
                }

                guard let csrfToken = try? doc.select("meta[name=\"csrf-token\"]").attr("content") else {
                    csrfError = TaskError.NoCSRF
                    semaphore.signal()
                    return
                }

                self.taskObj.csrfToken = csrfToken
                obtainedCSRF = true

                let variantComponents = html.components(separatedBy: "/frame_remove_item_quantity_from_cart?variant_id=")
                let variants = variantComponents.count > 1 ? variantComponents.dropFirst().compactMap { Int($0.components(separatedBy: "\"")[0]) } : []

                if variants.count > 0 {
                    csrfError = TaskError.CartNotEmpty
                } else {
                    self.taskObj.clearedCart = true
                }
            case 403:
                csrfError = TaskError.TaskBanned
            default:
                csrfError = TaskError.InvalidStatusCode
            }

            semaphore.signal()
        }

        semaphore.wait()
        return (obtainedCSRF, csrfError)
    }

    public func clearCart() -> Error? {
        var clearCartError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        guard let csrfToken = self.taskObj.csrfToken else {
            clearCartError = TaskError.NoCSRF
            semaphore.signal()
            return clearCartError
        }

        var request = URLRequest(url: URL(string: "https://www.off---white.com/en/GB/cart/empty")!)
        request.httpMethod = "PUT"
        request.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        doRequest(request: request) { _, response, error in
            if error != nil {
                clearCartError = error
                semaphore.signal()
                return
            }

            guard let response = response else {
                clearCartError = TaskError.NilResponse
                semaphore.signal()
                return
            }

            switch response.statusCode {
            case 403:
                clearCartError = TaskError.TaskBanned
            case 404:
                clearCartError = nil
            default:
                clearCartError = TaskError.InvalidStatusCode
            }

            semaphore.signal()
        }

        semaphore.wait()
        return clearCartError
    }

    public func getCartObject() -> (Cart?, Error?) {
        var cartObj: Cart?
        var cartError: Error?
        let semaphore = DispatchSemaphore(value: 0)

        let request = URLRequest(url: URL(string: "https://www.off---white.com/en/GB/cart.json")!)

        doRequest(request: request) { data, response, error in
            if error != nil {
                cartError = error
                semaphore.signal()
                return
            }

            guard let response = response else {
                cartError = TaskError.NilResponse
                semaphore.signal()
                return
            }

            guard let data = data else {
                cartError = TaskError.NilResponseData
                semaphore.signal()
                return
            }

            switch response.statusCode {
            case 200:
                guard let responseObj = try? JSONDecoder().decode(Cart.self, from: data) else {
                    cartError = TaskError.DecodingError
                    semaphore.signal()
                    return
                }

                cartObj = responseObj
            case 403:
                cartError = TaskError.TaskBanned
            default:
                cartError = TaskError.InvalidStatusCode
            }

            semaphore.signal()
        }

        semaphore.wait()
        return (cartObj, cartError)
    }

    public func getOrderIdentifiers(query: String) -> (OrderIdentifiers?, Error?) {
        var orderIdentifiers: OrderIdentifiers?
        var getOrderError: Error?
        let semaphore = DispatchSemaphore(value: 0)

        var request = URLRequest(url: URL(string: "https://www.off---white.com/api/orders/mine?\(query)")!)

        guard let APIKey = self.taskObj.accountUser?.spreeAPIKey else {
            getOrderError = TaskError.NoAPIKey
            return (orderIdentifiers, getOrderError)
        }

        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(APIKey, forHTTPHeaderField: "X-Spree-Token")

        doRequest(request: request) { data, response, error in
            if error != nil {
                getOrderError = error
                semaphore.signal()
                return
            }

            guard let response = response else {
                getOrderError = TaskError.NilResponse
                semaphore.signal()
                return
            }

            guard let data = data else {
                getOrderError = TaskError.NilResponseData
                semaphore.signal()
                return
            }

            switch response.statusCode {
            case 200:
                guard let responseObj = try? JSONDecoder().decode(OrderAPIResponse.self, from: data) else {
                    getOrderError = TaskError.DecodingError
                    semaphore.signal()
                    return
                }

                switch responseObj.count {
                case 0:
                    getOrderError = TaskError.NoOrderIdentifier
                case 1:
                    orderIdentifiers = responseObj.orders[0]
                default:
                    getOrderError = TaskError.TooManyOrderIdentifiers
                }
            case 401:
                getOrderError = TaskError.InvalidAPIKey
            case 403:
                getOrderError = TaskError.TaskBanned
            case 422:
                getOrderError = TaskError.InvalidAPIResponse
            default:
                getOrderError = TaskError.InvalidStatusCode
            }

            semaphore.signal()
        }

        semaphore.wait()
        return (orderIdentifiers, getOrderError)
    }

    public func addToCart(variantID: Int, captchaToken: String? = nil) -> (ATCResponse?, Error?) {
        var cartingResponse: ATCResponse?
        var cartingError: Error?
        let semaphore = DispatchSemaphore(value: 0)

        var cartObj: [String: AnyHashable] = ["variant_id": variantID, "quantity": 1]

        if let captchaToken = captchaToken {
            cartObj["g-recaptcha-response"] = captchaToken
        }

        var request = URLRequest(url: URL(string: "https://www.off---white.com/en/GB/orders/populate")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")

        guard let serializedBody = try? JSONSerialization.data(withJSONObject: cartObj, options: .prettyPrinted) else {
            cartingError = TaskError.EncodingError
            return (cartingResponse, cartingError)
        }

        request.httpBody = serializedBody

        doRequest(request: request) { data, response, error in
            if error != nil {
                cartingError = error
                semaphore.signal()
                return
            }

            guard let response = response else {
                cartingError = TaskError.NilResponse
                semaphore.signal()
                return
            }

            guard let data = data else {
                cartingError = TaskError.NilResponseData
                semaphore.signal()
                return
            }

            switch response.statusCode {
            case 200:
                guard let responseObj = try? JSONDecoder().decode(ATCResponse.self, from: data) else {
                    cartingError = TaskError.DecodingError
                    semaphore.signal()
                    return
                }

                if responseObj.lineItem.variantID == variantID {
                    cartingResponse = responseObj
                }

            case 403:
                cartingError = TaskError.TaskBanned
            case 422:
                cartingError = TaskError.ProductOOS
            default:
                cartingError = TaskError.InvalidStatusCode
            }

            semaphore.signal()
        }

        semaphore.wait()
        return (cartingResponse, cartingError)
    }

    func advanceOrder(orderNumber: String) -> (TaskOrderState?, Error?) {
        var orderState: TaskOrderState?
        var advanceError: Error?
        let semaphore = DispatchSemaphore(value: 0)

        var request = URLRequest(url: URL(string: "https://www.off---white.com/api/checkouts/\(orderNumber)/advance")!)

        guard let APIKey = self.taskObj.accountUser?.spreeAPIKey else {
            advanceError = TaskError.NoAPIKey
            return (orderState, advanceError)
        }

        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(APIKey, forHTTPHeaderField: "X-Spree-Token")

        doRequest(request: request) { data, response, error in
            if error != nil {
                advanceError = error
                semaphore.signal()
                return
            }

            guard let response = response else {
                advanceError = TaskError.NilResponse
                semaphore.signal()
                return
            }

            guard let data = data else {
                advanceError = TaskError.NilResponseData
                semaphore.signal()
                return
            }

            switch response.statusCode {
            case 200:
                guard let responseObj = try? JSONDecoder().decode(OrderIdentifiers.self, from: data) else {
                    advanceError = TaskError.DecodingError
                    semaphore.signal()
                    return
                }

                orderState = responseObj.state
            case 403:
                advanceError = TaskError.TaskBanned
            case 422:
                advanceError = TaskError.InvalidAPIResponse
            default:
                advanceError = TaskError.InvalidStatusCode
            }

            semaphore.signal()
        }

        semaphore.wait()
        return (orderState, advanceError)
    }

    func updateOrderState(orderNumber: String, orderState: TaskOrderState) -> (Bool?, Error?) {
        var stateUpdated = false
        var stateUpdateError: Error?
        let semaphore = DispatchSemaphore(value: 0)

        var request = URLRequest(url: URL(string: "https://www.off---white.com/api/checkouts/\(orderNumber).json")!)

        guard let APIKey = self.taskObj.accountUser?.spreeAPIKey else {
            stateUpdateError = TaskError.NoAPIKey
            return (stateUpdated, stateUpdateError)
        }

        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(APIKey, forHTTPHeaderField: "X-Spree-Token")
        
        let updateObj = ["state": orderState.rawValue]
        
        guard let serializedBody = try? JSONSerialization.data(withJSONObject: updateObj, options: .prettyPrinted) else {
            stateUpdateError = TaskError.EncodingError
            return (stateUpdated, stateUpdateError)
        }
        
        request.httpBody = serializedBody

        doRequest(request: request) { data, response, error in
            if error != nil {
                stateUpdateError = error
                semaphore.signal()
                return
            }

            guard let response = response else {
                stateUpdateError = TaskError.NilResponse
                semaphore.signal()
                return
            }

            guard let data = data else {
                stateUpdateError = TaskError.NilResponseData
                semaphore.signal()
                return
            }

            switch response.statusCode {
            case 200:
                guard let responseObj = try? JSONDecoder().decode(OrderIdentifiers.self, from: data) else {
                    stateUpdateError = TaskError.DecodingError
                    semaphore.signal()
                    return
                }

                if responseObj.state == orderState || orderState == TaskOrderState.Cart && responseObj.state == TaskOrderState.Address {
                    stateUpdated = true
                }
            case 403:
                stateUpdateError = TaskError.TaskBanned
            case 422:
                
                stateUpdateError = TaskError.InvalidAPIResponse
            default:
                stateUpdateError = TaskError.InvalidStatusCode
            }

            semaphore.signal()
        }

        semaphore.wait()

        return (stateUpdated, stateUpdateError)
    }
}

func testFunc() {
    let task = Task(taskObj: TaskObj(taskMode: TaskMode.API, taskType: TaskType.Product, accountEmail: "hasan@loserspay.tax", accountPassword: "TrelloUnique12"))
    let (loggedIn, loginError) = task.login()
    if let error = loginError, !loggedIn {
        print(error)
        return
    }

    print(task.taskObj)

    let (gotCSRF, csrfError) = task.getCSRF()

    var cartClearError: Error?

    if let error = csrfError {
        switch error {
        case TaskError.CartNotEmpty:
            if !gotCSRF {
                return
            } else {
                cartClearError = task.clearCart()
            }
        default:
            print(error)
            return
        }
    }

    print(gotCSRF)

    if let error = cartClearError {
        print(error)
        return
    }

    let (cartObj, cartError) = task.getCartObject()

    if let cartObj = cartObj {
        if cartObj.lineItems.count == 0 {
            print(cartObj)
        }
    } else if let cartError = cartError {
        print(cartError)
    }

    var orderId: OrderIdentifiers?
    var getOrderError: Error?

    for (query) in ["q[state_eq]=cart", "q[state_eq]=address", "q[state_eq]=delivery", "q[state_eq]=payment"] {
        let (oiObj, oiError) = task.getOrderIdentifiers(query: query)
        if oiObj != nil {
            orderId = oiObj
            getOrderError = nil
            break
        } else {
            getOrderError = oiError
        }
    }
    
    guard let orderIdentifiers = orderId else {
        print(getOrderError!)
        return
    }

   
    let methodStart = NSDate()
    let (cartItemObj, cartingError) = task.addToCart(variantID: 118_563)

    guard let cart = cartItemObj else {
        print(cartingError!)
        return
    }

    print(cartItemObj)

    if cart.lineItem.orderID == orderIdentifiers.id {
        print(task.advanceOrder(orderNumber: orderIdentifiers.number))
        let methodFinish = NSDate()
        let executionTime = methodFinish.timeIntervalSince(methodStart as Date)
        print("API Reservation Time: \(executionTime)")
        print(task.updateOrderState(orderNumber: orderIdentifiers.number, orderState: TaskOrderState.Cart))
    }
}
