//
//  Task.swift
//  grey
//
//  Created by Hasan Gondal on 15/12/2019.
//  Copyright © 2019 Hasan Gondal. All rights reserved.
//

import Foundation

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
}

struct TaskObj: Codable {
    var taskMode: TaskMode
    var taskType: TaskType
    var accountEmail: String
    var accountPassword: String
    var accountUser: User?
    var billingAddress: Address?
    var shippingAddress: Address?
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

struct CartResponse: Codable {
    let lineItem: CartResponseLineItem
    let cart: Cart

    enum CodingKeys: String, CodingKey {
        case lineItem = "line_item"
        case cart
    }
}

struct Cart: Codable {
    let itemCount: Int
    let lineItems: [LineItemElement]
    let signedIn: Bool

    enum CodingKeys: String, CodingKey {
        case itemCount = "item_count"
        case lineItems = "line_items"
        case signedIn = "signed_in"
    }
}

struct LineItemElement: Codable {
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

struct CartResponseLineItem: Codable {
    let variantID, quantity: Int

    enum CodingKeys: String, CodingKey {
        case variantID = "variant_id"
        case quantity
    }
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
        self.taskIdentifier = UUID().uuidString.lowercased()
        self.logger = Logger(label: "Task \(self.taskIdentifier)")
        
        var config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = ["User-Agent": UserAgent]
        
        if Proxies.count > 0 {
            for _ in 1...5 {
                if let proxy = Proxies.randomElement() {
                    if ProxyStates[proxy.description] == ProxyState.Free {
                        config = proxy.createSessionConfig(existingSessionConfiguration: config)
                        break
                    }
                }
            }
        }
        
        self.session = URLSession(configuration: config)
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
                        for (cookie) in cookieArray {
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
        for _ in 1...5 {
            if let proxy = Proxies.randomElement() {
                if ProxyStates[proxy.description] == ProxyState.Free {
                    let config = proxy.createSessionConfig(existingSessionConfiguration: session.configuration)
                    config.httpAdditionalHeaders?["User-Agent"] = UserAgent
                    self.session = URLSession(configuration: config)
                    self.logger.info(message: "Set Proxy - \(proxy)")
                    break
                }
            }
        }
    }
    
    public func login() -> (Bool, Error?) {
        var isLoggedIn = false
        var loginError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        
        let loginObj = ["spree_user": ["email": self.taskObj.accountEmail, "password": self.taskObj.accountPassword, "remember_me": 1]]
        
        var request = URLRequest(url: URL(string: "https://www.off---white.com/en/GB/login")!)
        request.httpMethod = "POST"
        request.setValue("application/javascript", forHTTPHeaderField: "Accept")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        
        guard let serializedBody = try? JSONSerialization.data(withJSONObject: loginObj, options: .prettyPrinted) else {
            return (isLoggedIn, TaskError.EncodingError)
        }

        request.httpBody = serializedBody
        
        self.doRequest(request: request) { data, response, error in
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
    
    public func addToCart(variantID: Int, captchaToken: String? = nil) -> (Cart?, Error?) {
        var cart: Cart?
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
            return (cart, cartingError)
        }
        
        request.httpBody = serializedBody
        
        self.doRequest(request: request) { data, response, error in
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
                guard let responseObj = try? JSONDecoder().decode(CartResponse.self, from: data) else {
                    cartingError = TaskError.DecodingError
                    semaphore.signal()
                    return
                }
                
                if responseObj.lineItem.variantID == variantID {
                    cart = responseObj.cart
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
        return (cart, cartingError)
    }
}
