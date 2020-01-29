//
//  Task.swift
//  grey
//
//  Created by Hasan Gondal on 15/12/2019.
//  Copyright © 2019 Hasan Gondal. All rights reserved.
//

import Foundation

import WebKit
import SwiftSoup

var UserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 13_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.4 Mobile/15E148 Safari/604.1"
var MaxSetupAttempts = 5
var MaxLinkAttempts = 20
var RetryDelay = 500
var MonitorDelay = 250
var WebhookURL = "https://hooks.slack.com/services/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"
let GlobalWH = Webhook(url: URL(string: WebhookURL)!)

var ProductMonitorDict = Dictionary<String,String>()

enum TaskMode: Int, Codable {
//    case Safe = 0
    case API = 1
}

enum TaskType: Int, Codable {
    case Product = 0
    case Variant = 1
}

enum TaskPaymentType: Int, Codable {
    case Card = 0
    case PayPal = 1
}

enum TaskState: Int, Codable {
    case Idle = 0
    case LoggingIn = 1
    case LoggedIn = 2
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

enum TaskInternalState: Int, Codable {
    case Idle = 0
    case AttemptingLogin = 1
    case LoggedIn = 2
    case AttempingGetCountryISO = 3
    case ObtainedUserCountry = 4
    case AttemptingGetCSRF = 5
    case ObtainedCSRF = 6
    case AttemptingClearCart = 7
    case ClearedCart = 8
    case AttemptingObtainingCart = 9
    case ObtainedCartObject = 10
    case AttemptingObtainingCheckout = 11
    case ObtainedCheckoutObject = 12
    case AwaitingProduct = 13
    case ProductFound = 14
    case AttemptingToCart = 15
    case ItemCarted = 16
    case AttemptingCheckoutAdvance = 17
    case CheckoutAdvanced = 18
    case AttemptingObtainingPayPalLink = 19
    case ObtainedPayPalLink = 20
    case AttemptingCardPayment = 21
    case CardPaymentSuccess = 22
}

enum TaskError: Error {
    case VaritiFailure
    case RequestError
    case NilResponse
    case NilResponseData
    case InvalidCredentials
    case InvalidStatusCode
    case TaskBanned
    case EncodingError
    case DecodingError
    case NoBillingAddress
    case ProductOOS
    case ProductDoesNotExist
    case NoAddress
    case NoCountry
    case NoCSRF
    case SwiftSoupError
    case CartNotEmpty
    case NoAPIKey
    case InvalidAPIKey
    case InvalidOrderState
    case InvalidAPIResponse
    case NoOrderObject
    case UnhandledError
}

enum CheckoutState: String, Codable {
    case Cart = "cart"
    case Address = "address"
    case Delivery = "delivery"
    case Payment = "payment"
    case Complete = "complete"
}

struct TaskErrorState {
    let error: TaskError
    let state: TaskInternalState
}

struct TaskObj: Codable {
    var taskMode: TaskMode
    var taskType: TaskType
    var taskPayment: TaskPaymentType
    var accountEmail: String
    var accountPassword: String
    var cardObject: CardObj?
    var accountUser: User?
    var billingAddress: Address?
    var shippingAddress: Address?
    var csrfToken: String?
    var checkoutObject: CheckoutObject?
}

struct CardObj: Codable {
    let cardNumber: String
    let expiryMonth: String
    let expiryYear: String
    let cardCVV: String
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
    let name, url: String
    let quantity: Int

    enum CodingKeys: String, CodingKey {
        case variantID = "variant_id"
        case imageURL = "image_url"
        case name
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
    let orders: [CheckoutObject]

    enum CodingKeys: String, CodingKey {
        case count
        case currentPage = "current_page"
        case pages, orders
    }
}

struct CheckoutObject: Codable {
    let id: Int
    let number, total: String
    let state: CheckoutState
    let userID: Int
    let currency: String
    let lineItems: [CheckoutLineItem]
    let payments: [CheckoutPayment]

    enum CodingKeys: String, CodingKey {
        case id, number, total, state
        case userID = "user_id"
        case currency
        case lineItems = "line_items"
        case payments
    }
}

struct CheckoutLineItem: Codable {
    let id, quantity, variantID: Int
    let total: String
    let variant: CheckoutVariant

    enum CodingKeys: String, CodingKey {
        case id, quantity
        case variantID = "variant_id"
        case total, variant
    }
}

struct CheckoutVariant: Codable {
    let id: Int
    let name, sku, slug, optionsText: String
    let inStock, isBackorderable: Bool
    let totalOnHand, productID: Int

    enum CodingKeys: String, CodingKey {
        case id, name, sku, slug
        case optionsText = "options_text"
        case inStock = "in_stock"
        case isBackorderable = "is_backorderable"
        case totalOnHand = "total_on_hand"
        case productID = "product_id"
    }
}

struct CheckoutPayment: Codable {
    let id: Int
}

struct CountryAPIResponse: Codable {
    let count, currentPage, pages: Int
    let countries: [Country]

    enum CodingKeys: String, CodingKey {
        case count
        case currentPage = "current_page"
        case pages, countries
    }
}

struct Country: Codable {
    let id: Int
    let isoName, iso: String

    enum CodingKeys: String, CodingKey {
        case id
        case isoName = "iso_name"
        case iso
    }
}


struct APIErrorResponse: Codable {
    let error: String
    let errors: Errors
}

struct Errors: Codable {
    let base: [String]
}


class Task {
    typealias CompletionHandler = (_ data: Data?, _ response: HTTPURLResponse?, _ error: Error?) -> Void

    var taskState: TaskState = TaskState.Idle

    var taskIdentifier: String
    var session: Session
    var logger: Logger
    var taskObj: TaskObj
    var proxyObj: Proxy?
    var isLoggedIn = false
    var setupComplete = false
    var isMonitorTask = false
    var taskSetupAttempts = 0
    var qtUpdate = false
    var stopCalled = false
    var variantArray = Set<Int>()
    var userCountry = "GB"
    var clearedCart: Bool = false
    
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

        session = Session(configuration: config, logger: logger)
    }

    private func rotateProxy() {
        for _ in 1 ... 5 {
            if let proxy = Proxies.randomElement() {
                if ProxyStates[proxy.description] == ProxyState.Free {
                    let config = proxy.createSessionConfig(existingSessionConfiguration: session.session.configuration)
                    self.proxyObj = proxy
                    config.httpAdditionalHeaders?["User-Agent"] = UserAgent
                    session = Session(configuration: config, logger: logger)
                    self.logger.info(message: "Set Proxy - \(proxy)")
                    break
                }
            }
        }
    }

    public func login() -> (Bool, TaskError?) {
        var isLoggedIn = false
        var loginError: TaskError?
        let semaphore = DispatchSemaphore(value: 0)

        var request = URLRequest(url: URL(string: "https://www.off---white.com/en/\(self.userCountry)/login")!)
        request.httpMethod = "POST"
        request.setValue("application/javascript", forHTTPHeaderField: "Accept")
        request.setValue(QHTTPFormURLEncoded.contentType, forHTTPHeaderField: "Content-Type")
        
        let query = [("utf8", "✓"), ("authenticity_token", ""), ("spree_user[email]", self.taskObj.accountEmail), ("spree_user[password]",  self.taskObj.accountPassword), ("spree_user[remember_me]", "1"), ("commit", "Login")]
        
        request.httpBody = QHTTPFormURLEncoded.urlEncoded(formDataSet: query).data(using: .utf8)

        self.session.doRequest(request: request) { data, response, error in
            if error != nil {
                loginError = .RequestError
                semaphore.signal()
                return
            }

            guard let response = response else {
                loginError = .NilResponse
                semaphore.signal()
                return
            }

            guard let data = data else {
                loginError = .NilResponseData
                semaphore.signal()
                return
            }

            switch response.statusCode {
            case 200:
                guard let responseObj = try? JSONDecoder().decode(LoginResponse.self, from: data) else {
                    loginError = .DecodingError
                    semaphore.signal()
                    return
                }

                isLoggedIn = true

                self.taskObj.accountUser = responseObj.user
                self.taskObj.billingAddress = responseObj.billAddress
                self.taskObj.shippingAddress = responseObj.shipAddress
            case 403:
                loginError = .TaskBanned
            case 422:
                loginError = .InvalidCredentials
            default:
                self.logger.warn(message: "Invalid Status on Login - \(response.statusCode)")
                loginError = .InvalidStatusCode
            }

            semaphore.signal()
        }

        semaphore.wait()
        return (isLoggedIn, loginError)
    }
    
    public func getCountryISO(countryID: Int) -> (String?, TaskError?) {
        var countryISO: String?
        var getCountryError: TaskError?
        let semaphore = DispatchSemaphore(value: 0)

        var request = URLRequest(url: URL(string: "https://www.off---white.com/api/countries.json?q[id_eq]=\(countryID)")!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        self.session.doRequest(request: request) { data, response, error in
            if error != nil {
                getCountryError = .RequestError
                semaphore.signal()
                return
            }

            guard let response = response else {
                getCountryError = .NilResponse
                semaphore.signal()
                return
            }

            guard let data = data else {
                getCountryError = .NilResponseData
                semaphore.signal()
                return
            }

            switch response.statusCode {
            case 200:
                guard let responseObj = try? JSONDecoder().decode(CountryAPIResponse.self, from: data) else {
                    getCountryError = .DecodingError
                    semaphore.signal()
                    return
                }
                
                if responseObj.count > 0 {
                    for (country) in responseObj.countries {
                        if country.id == countryID {
                            countryISO = country.iso
                        }
                    }
                }
                
                if countryISO == nil {
                    getCountryError = .NoCountry
                    semaphore.signal()
                    return
                }

            case 403:
                getCountryError = .TaskBanned
            default:
                getCountryError = .InvalidStatusCode
            }

            semaphore.signal()
        }

        semaphore.wait()
        return (countryISO, getCountryError)
    }

    public func getCSRF() -> (Bool, TaskError?) {
        var obtainedCSRF = false
        var csrfError: TaskError?
        let semaphore = DispatchSemaphore(value: 0)

        let request = URLRequest(url: URL(string: "https://www.off---white.com/en/\(self.userCountry)/cart")!)

        self.session.doRequest(request: request) { data, response, error in
            if error != nil {
                csrfError = .RequestError
                semaphore.signal()
                return
            }

            guard let response = response else {
                csrfError = .NilResponse
                semaphore.signal()
                return
            }

            guard let data = data else {
                csrfError = .NilResponseData
                semaphore.signal()
                return
            }

            switch response.statusCode {
            case 200:
                let html = String(data: data, encoding: .utf8)!

                guard let doc: Document = try? SwiftSoup.parse(html) else {
                    csrfError = .SwiftSoupError
                    semaphore.signal()
                    return
                }

                guard let csrfToken = try? doc.select("meta[name=\"csrf-token\"]").attr("content") else {
                    csrfError = .NoCSRF
                    semaphore.signal()
                    return
                }

                self.taskObj.csrfToken = csrfToken
                obtainedCSRF = true
                
                if let variantArray = try? doc.select(".decrement").array() {
                    if variantArray.count > 0 {
                        csrfError = .CartNotEmpty
                    }
                }
            case 403:
                csrfError = .TaskBanned
            default:
                csrfError = .InvalidStatusCode
            }

            semaphore.signal()
        }

        semaphore.wait()
        return (obtainedCSRF, csrfError)
    }

    public func attemptClearCart() -> TaskError? {
        var clearCartError: TaskError?
        let semaphore = DispatchSemaphore(value: 0)
        guard let csrfToken = self.taskObj.csrfToken else {
            clearCartError = .NoCSRF
            semaphore.signal()
            return clearCartError
        }

        var request = URLRequest(url: URL(string: "https://www.off---white.com/en/\(self.userCountry)/cart/empty")!)
        request.httpMethod = "PUT"
        request.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

       self.session.doRequest(request: request) { _, response, error in
            if error != nil {
                clearCartError = .RequestError
                semaphore.signal()
                return
            }

            guard let response = response else {
                clearCartError = .NilResponse
                semaphore.signal()
                return
            }

            switch response.statusCode {
            case 403:
                clearCartError = .TaskBanned
            case 404:
                clearCartError = nil
            default:
                clearCartError = .InvalidStatusCode
            }

            semaphore.signal()
        }

        semaphore.wait()
        return clearCartError
    }

    public func getCartObject() -> (Cart?, TaskError?) {
        var cartObj: Cart?
        var cartError: TaskError?
        let semaphore = DispatchSemaphore(value: 0)

        let request = URLRequest(url: URL(string: "https://www.off---white.com/en/\(self.userCountry)/cart.json")!)

        self.session.doRequest(request: request) { data, response, error in
            if error != nil {
                cartError = .RequestError
                semaphore.signal()
                return
            }

            guard let response = response else {
                cartError = .NilResponse
                semaphore.signal()
                return
            }

            guard let data = data else {
                cartError = .NilResponseData
                semaphore.signal()
                return
            }

            switch response.statusCode {
            case 200:
                guard let responseObj = try? JSONDecoder().decode(Cart.self, from: data) else {
                    cartError = .DecodingError
                    semaphore.signal()
                    return
                }

                cartObj = responseObj
            case 403:
                cartError = .TaskBanned
            default:
                cartError = .InvalidStatusCode
            }

            semaphore.signal()
        }

        semaphore.wait()
        return (cartObj, cartError)
    }
    
    public func clearCart() -> TaskError? {
        let cartClearError = self.attemptClearCart()
        
        if cartClearError != nil {
            return cartClearError
        }
        
        let (cartObject, getCartError) = self.getCartObject()
        
        if getCartError != nil {
            return getCartError
        }
        
        if cartObject!.lineItems.count > 0 {
            return .CartNotEmpty
        }
        
        return nil
    }

    public func getCheckoutObject(query: String) -> (CheckoutObject?, TaskError?) {
        var checkoutObject: CheckoutObject?
        var getOrderError: TaskError?
        let semaphore = DispatchSemaphore(value: 0)

        var request = URLRequest(url: URL(string: "https://www.off---white.com/api/orders/mine?\(query)")!)

        guard let APIKey = self.taskObj.accountUser?.spreeAPIKey else {
            getOrderError = .NoAPIKey
            return (checkoutObject, getOrderError)
        }

        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(APIKey, forHTTPHeaderField: "X-Spree-Token")

        self.session.doRequest(request: request) { data, response, error in
            if error != nil {
                getOrderError = .RequestError
                semaphore.signal()
                return
            }

            guard let response = response else {
                getOrderError = .NilResponse
                semaphore.signal()
                return
            }

            guard let data = data else {
                getOrderError = .NilResponseData
                semaphore.signal()
                return
            }

            switch response.statusCode {
            case 200:
                guard let responseObj = try? JSONDecoder().decode(OrderAPIResponse.self, from: data) else {
                    getOrderError = .DecodingError
                    semaphore.signal()
                    return
                }

                switch responseObj.count {
                case 0:
                    getOrderError = .NoOrderObject
                case 1:
                    checkoutObject = responseObj.orders[0]
                default:
                    var currentCheckoutObj: CheckoutObject?
                    for (order) in responseObj.orders {
                        if currentCheckoutObj == nil || order.id > currentCheckoutObj!.id {
                            if order.payments.count < 5 {
                                currentCheckoutObj = order
                            }
                        }
                        checkoutObject = currentCheckoutObj
                    }
                }
            case 401:
                getOrderError = .InvalidAPIKey
            case 403:
                getOrderError = .TaskBanned
            case 422:
                getOrderError = .InvalidAPIResponse
            default:
                getOrderError = .InvalidStatusCode
            }

            semaphore.signal()
        }

        semaphore.wait()
        return (checkoutObject, getOrderError)
    }
    
    public func getInitialCheckoutObj() -> (CheckoutObject?, TaskError?) {
        var checkoutObj: CheckoutObject?
        var getCheckoutObjError: TaskError?
        
        var checkoutObjects: [CheckoutObject] = []
        
        for (query) in ["q[state_eq]=cart", "q[state_eq]=address", "q[state_eq]=delivery", "q[state_eq]=payment"] {
            (checkoutObj, getCheckoutObjError) = self.getCheckoutObject(query: query)
            if let checkoutObject = checkoutObj {
                checkoutObjects.append(checkoutObject)
            }
        }
        
        for (checkoutObject) in checkoutObjects {
            if let currentCheckoutObj = checkoutObj {
                if checkoutObject.id > currentCheckoutObj.id {
                    checkoutObj = checkoutObject
                }
            } else {
                checkoutObj = checkoutObject
            }
        }
        
        if checkoutObj != nil {
            return (checkoutObj, nil)
        }
        
        return (nil, getCheckoutObjError)
    }

    public func addToCart(variantID: Int, captchaToken: String? = nil) -> (ATCResponse?, TaskError?) {
        var cartingResponse: ATCResponse?
        var cartingError: TaskError?
        let semaphore = DispatchSemaphore(value: 0)

        var cartObj: [String: Any] = ["variant_id": variantID, "quantity": 1]

        if let captchaToken = captchaToken {
            cartObj["g-recaptcha-response"] = captchaToken
        }

        var request = URLRequest(url: URL(string: "https://www.off---white.com/en/\(self.userCountry)/orders/populate")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")

        guard let serializedBody = try? JSONSerialization.data(withJSONObject: cartObj, options: []) else {
            cartingError = .EncodingError
            return (cartingResponse, cartingError)
        }

        request.httpBody = serializedBody

        self.session.doRequest(request: request) { data, response, error in
            if error != nil {
                cartingError = .RequestError
                semaphore.signal()
                return
            }

            guard let response = response else {
                cartingError = .NilResponse
                semaphore.signal()
                return
            }

            guard let data = data else {
                cartingError = .NilResponseData
                semaphore.signal()
                return
            }

            switch response.statusCode {
            case 200:
                guard let responseObj = try? JSONDecoder().decode(ATCResponse.self, from: data) else {
                    cartingError = .DecodingError
                    semaphore.signal()
                    return
                }

                if responseObj.lineItem.variantID == variantID {
                    cartingResponse = responseObj
                }
            case 403:
                cartingError = .TaskBanned
            case 404:
                cartingError = .ProductDoesNotExist
            case 422:
                cartingError = .ProductOOS
            default:
                cartingError = .InvalidStatusCode
            }

            semaphore.signal()
        }

        semaphore.wait()
        return (cartingResponse, cartingError)
    }

    func advanceOrder(orderNumber: String) -> (CheckoutObject?, TaskError?) {
        var checkoutObj: CheckoutObject?
        var advanceError: TaskError?
        let semaphore = DispatchSemaphore(value: 0)

        var request = URLRequest(url: URL(string: "https://www.off---white.com/api/checkouts/\(orderNumber)/advance.json")!)

        guard let APIKey = self.taskObj.accountUser?.spreeAPIKey else {
            advanceError = .NoAPIKey
            return (checkoutObj, advanceError)
        }

        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(APIKey, forHTTPHeaderField: "X-Spree-Token")

        self.session.doRequest(request: request) { data, response, error in
            if error != nil {
                advanceError = .RequestError
                semaphore.signal()
                return
            }

            guard let response = response else {
                advanceError = .NilResponse
                semaphore.signal()
                return
            }

            guard let data = data else {
                advanceError = .NilResponseData
                semaphore.signal()
                return
            }

            switch response.statusCode {
            case 200:
                guard let responseObj = try? JSONDecoder().decode(CheckoutObject.self, from: data) else {
                    advanceError = .DecodingError
                    semaphore.signal()
                    return
                }

                checkoutObj = responseObj
                self.logger.info(message: "Advanced Order - \(orderNumber) - \(responseObj.state)")
            case 403:
                advanceError = .TaskBanned
            case 422:
                advanceError = .InvalidAPIResponse
            default:
                advanceError = .InvalidStatusCode
            }

            semaphore.signal()
        }

        semaphore.wait()
        return (checkoutObj, advanceError)
    }

    func updateCheckoutState(orderNumber: String, orderState: CheckoutState) -> (Bool, TaskError?) {
        var stateUpdated = false
        var stateUpdateError: TaskError?
        let semaphore = DispatchSemaphore(value: 0)

        var request = URLRequest(url: URL(string: "https://www.off---white.com/api/checkouts/\(orderNumber).json")!)

        guard let APIKey = self.taskObj.accountUser?.spreeAPIKey else {
            stateUpdateError = .NoAPIKey
            return (stateUpdated, stateUpdateError)
        }

        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(APIKey, forHTTPHeaderField: "X-Spree-Token")
        
        let updateObj = ["state": orderState.rawValue]
        
        guard let serializedBody = try? JSONEncoder().encode(updateObj) else {
            stateUpdateError = .EncodingError
            return (stateUpdated, stateUpdateError)
        }
        
        request.httpBody = serializedBody

        self.session.doRequest(request: request) { data, response, error in
            if error != nil {
                stateUpdateError = .RequestError
                semaphore.signal()
                return
            }

            guard let response = response else {
                stateUpdateError = .NilResponse
                semaphore.signal()
                return
            }

            guard let data = data else {
                stateUpdateError = .NilResponseData
                semaphore.signal()
                return
            }

            switch response.statusCode {
            case 200:
                guard let responseObj = try? JSONDecoder().decode(CheckoutObject.self, from: data) else {
                    stateUpdateError = .DecodingError
                    semaphore.signal()
                    return
                }

                if responseObj.state == orderState || orderState == CheckoutState.Cart && responseObj.state == CheckoutState.Address {
                    stateUpdated = true
                }
            case 403:
                stateUpdateError = .TaskBanned
            case 422:
                guard let responseObj = try? JSONDecoder().decode(APIErrorResponse.self, from: data) else {
                    stateUpdateError = .DecodingError
                    semaphore.signal()
                    return
                }
                
                if responseObj.errors.base.count == 1 && responseObj.errors.base[0] == "There are no items for this order. Please add an item to the order to continue." {
                    stateUpdated = true
                } else {
                    stateUpdateError = .InvalidAPIResponse
                }
            default:
                stateUpdateError = .InvalidStatusCode
            }

            semaphore.signal()
        }

        semaphore.wait()

        return (stateUpdated, stateUpdateError)
    }
    
    public func getPayPalExpressLink(checkoutObj: CheckoutObject) -> (String?, TaskError?) {
        var expressLink: String?
        var expressLinkError: TaskError?
        let semaphore = DispatchSemaphore(value: 0)
        
        if checkoutObj.state != CheckoutState.Payment {
            expressLinkError = .InvalidOrderState
            semaphore.signal()
            return (expressLink, expressLinkError)
        }

        var request = URLRequest(url: URL(string: "https://www.off---white.com/en/\(self.userCountry)/checkout/payment/paypal_redirect")!)
        request.httpMethod = "POST"
        request.setValue(QHTTPFormURLEncoded.contentType, forHTTPHeaderField: "Content-Type")
        
        guard let csrfToken = self.taskObj.csrfToken else {
            expressLinkError = .NoCSRF
            semaphore.signal()
            return (expressLink, expressLinkError)
        }
        
        
        let query = [("utf8", "✓"), ("authenticity_token", csrfToken), ("transaction", checkoutObj.number), ("amount", checkoutObj.total), ("payment_method_id", "12"), ("commit", "Proceed")]
        
        request.httpBody = QHTTPFormURLEncoded.urlEncoded(formDataSet: query).data(using: .utf8)
        
        self.session.doRequest(request: request, followRedirects: false) { _, response, error in
            if error != nil {
                expressLinkError = .RequestError
                semaphore.signal()
                return
            }

            guard let response = response else {
                expressLinkError = .NilResponse
                semaphore.signal()
                return
            }
            
            switch response.statusCode {
            case 302:
                guard let redirectURL = response.value(forHTTPHeaderField: "Location") else {
                    expressLinkError = .NilResponse
                    semaphore.signal()
                    return
                }
                
                expressLink = redirectURL
            case 403:
                expressLinkError = .TaskBanned
            default:
                expressLinkError = .InvalidStatusCode
            }

            semaphore.signal()
        }

        semaphore.wait()
        
        return (expressLink, expressLinkError)
    }
    
    public func setupAPITask() -> (TaskErrorState?) {
        if !self.setupComplete {
            self.logger.info(message: "Starting")
            _ = self.getCartObject()
            
            if !self.isLoggedIn {
                let (loggedIn, loginError) = self.login()
                
                if !loggedIn {
                    if let error = loginError {
                        switch error {
                        case .TaskBanned:
                            if let proxy = self.proxyObj {
                                ProxyStates[proxy.description] = ProxyState.Banned
                            }
                            
                            self.rotateProxy()
                            
                            if self.taskSetupAttempts < MaxSetupAttempts {
                                self.taskSetupAttempts += 1
                                return self.setupAPITask()
                            }
                                
                            return TaskErrorState(error: .TaskBanned, state: .AttemptingLogin)
                        default:
                            return TaskErrorState(error: error, state: .AttemptingLogin)
                        }
                    }
                } else {
                    self.logger.info(message: "Logged In")
                    self.isLoggedIn = true
                }
                
                if let billAddress = self.taskObj.billingAddress {
                    let (countryISO, getCountryError) = self.getCountryISO(countryID: billAddress.countryID)
                    if let userCountry = countryISO {
                        self.logger.info(message: "Got Country - \(userCountry)")
                        self.userCountry = userCountry
                    } else if let error = getCountryError {
                        switch error {
                        case .TaskBanned:
                            if let proxy = self.proxyObj {
                                ProxyStates[proxy.description] = ProxyState.Banned
                            }
                            self.rotateProxy()

                            if self.taskSetupAttempts < MaxSetupAttempts {
                                self.taskSetupAttempts += 1
                                return self.setupAPITask()
                            }

                            return TaskErrorState(error: .TaskBanned, state: .AttempingGetCountryISO)
                        default:
                            return TaskErrorState(error: error, state: .AttempingGetCountryISO)
                        }
                    }
                } else {
                    return TaskErrorState(error: .NoAddress, state: .AttemptingLogin)
                }
            }
            
            var cartNeedsClearing = false
            
            if self.taskObj.csrfToken == nil {
                let (gotCSRF, csrfError) = self.getCSRF()
                
                if !gotCSRF || csrfError != nil {
                    if let error = csrfError {
                        switch error {
                        case .TaskBanned:
                            if let proxy = self.proxyObj {
                                ProxyStates[proxy.description] = ProxyState.Banned
                            }
                            
                            self.rotateProxy()
                            
                            if self.taskSetupAttempts < MaxSetupAttempts {
                                self.taskSetupAttempts += 1
                                return self.setupAPITask()
                            }
                            
                            return TaskErrorState(error: .TaskBanned, state: .AttemptingGetCSRF)
                        case .CartNotEmpty:
                            cartNeedsClearing = true
                        default:
                            return TaskErrorState(error: error, state: .AttemptingGetCSRF)
                        }
                    }
                } else {
                    self.logger.info(message: "Cart Is Clear")
                    self.clearedCart = true
                }
            }
            if !self.clearedCart {
                if cartNeedsClearing {
                    let cartClearError = self.clearCart()
                    
                    if let error = cartClearError {
                        switch error {
                        case .TaskBanned:
                            if let proxy = self.proxyObj {
                                ProxyStates[proxy.description] = ProxyState.Banned
                            }
                
                            self.rotateProxy()
                            
                            if self.taskSetupAttempts < MaxSetupAttempts {
                                self.taskSetupAttempts += 1
                                return self.setupAPITask()
                            }
                            return TaskErrorState(error: .TaskBanned, state: .AttemptingClearCart)
                        default:
                            return TaskErrorState(error: error, state: .AttemptingClearCart)
                        }
                    } else {
                        self.logger.info(message: "Cart Cleared")
                        self.clearedCart = true
                    }
                }
            }
            
            let (checkoutObj, checkoutObjError) = self.getInitialCheckoutObj()
            
            if let checkoutObject = checkoutObj {
                if checkoutObject.state == CheckoutState.Cart {
                    self.logger.info(message: "Got Checkout Object - \(checkoutObject.id)")
                    self.taskObj.checkoutObject = checkoutObject
                } else {
                    let (updatedState, stateUpdateError) = self.updateCheckoutState(orderNumber: checkoutObject.number, orderState: CheckoutState.Cart)
                    if !updatedState {
                        self.logger.warn(message: "Ignoring Found Cart Object - \(stateUpdateError!) - \(checkoutObject.id)")
                    } else {
                        self.logger.info(message: "Got Checkout Object - \(checkoutObject.id)")
                        self.taskObj.checkoutObject = checkoutObject
                    }
                }
            }
            
            if let error = checkoutObjError {
                switch error {
                case .NoOrderObject:
                    _ = self.addToCart(variantID: 1)
                    if self.taskSetupAttempts < MaxSetupAttempts {
                        self.taskSetupAttempts += 1
                        return self.setupAPITask()
                    }
                case .TaskBanned:
                    if let proxy = self.proxyObj {
                        ProxyStates[proxy.description] = ProxyState.Banned
                    }
                    
                    self.rotateProxy()
                    
                    if self.taskSetupAttempts < MaxSetupAttempts {
                        self.taskSetupAttempts += 1
                        return self.setupAPITask()
                    }
                    return TaskErrorState(error: .TaskBanned, state: .AttemptingObtainingCheckout)
                default:
                    return TaskErrorState(error: error, state: .AttemptingObtainingCheckout)
                }
            }
            
            self.setupComplete = true
            self.logger.info(message: "Setup Complete")
            return nil
        }
        return nil
    }
    
    public func startAPITask() {
        _ = self.getCartObject()
        if setupComplete {
            switch self.taskObj.taskType {
            case .Variant:
                var addToCartResponse: ATCResponse?
                var cartingError: TaskError?
                while addToCartResponse == nil {
                    if self.stopCalled {
                        self.stopCalled = false
                        return
                    }
                    if let variant = self.variantArray.randomElement() {
                        (addToCartResponse, cartingError) = self.addToCart(variantID: variant)
                        if let error = cartingError {
                            switch error {
                            case .TaskBanned:
                                if let proxy = self.proxyObj {
                                    ProxyStates[proxy.description] = ProxyState.Banned
                                }
                                
                                self.rotateProxy()
                            default:
                                usleep(10 * 1000)
                                self.logger.warn(message: "Carting Error - \(variant) - \(error)")
                            }
                            usleep(UInt32(RetryDelay) * 1000)
                        }
                        cartingError = nil
                    }
                }
                
                if let cartResponse = addToCartResponse {
                    self.logger.info(message: "Carted - \(cartResponse.lineItem.variantID)")
                    if let checkoutObject = self.taskObj.checkoutObject {
                        if checkoutObject.id == cartResponse.lineItem.orderID {
                            var (advancedCheckoutObject, advancingError) = self.advanceOrder(orderNumber: checkoutObject.number)
                            var advanceAttempts = 0
                            while advancedCheckoutObject == nil && advanceAttempts < 10 {
                                if let error = advancingError {
                                    advanceAttempts += 1
                                    
                                    switch error {
                                    case .TaskBanned:
                                        if let proxy = self.proxyObj {
                                            ProxyStates[proxy.description] = ProxyState.Banned
                                        }

                                        self.rotateProxy()
                                    default:
                                        self.logger.warn(message: "Advancing Error - \(error)")
                                        return
                                    }
                                    
                                    usleep(UInt32(RetryDelay) * 1000)
                                    (advancedCheckoutObject, advancingError) = self.advanceOrder(orderNumber: checkoutObject.number)
                                }
                            }
                            
                            if let finalOrderObject = advancedCheckoutObject, finalOrderObject.state == CheckoutState.Payment {
                                var (redirectLink, linkError) = self.getPayPalExpressLink(checkoutObj: finalOrderObject)
                                var linkAttempts = 0
                                while redirectLink == nil && linkAttempts < MaxLinkAttempts {
                                    
                                    if let error = linkError {
                                        linkAttempts += 1
    
                                        switch error {
                                        case .TaskBanned:
                                            if let proxy = self.proxyObj {
                                                ProxyStates[proxy.description] = ProxyState.Banned
                                            }
    
                                            self.rotateProxy()
                                        default:
                                            self.logger.warn(message: "Obtain Link Error - \(error)")
                                            return
                                        }
                                        usleep(UInt32(RetryDelay) * 1000)
                                        (redirectLink, linkError) = self.getPayPalExpressLink(checkoutObj: checkoutObject)
                                    }
                                }
    
                                if let obtainedRedirectLink = redirectLink {
                                    self.sendPayPalWH(redirectLink: obtainedRedirectLink, cartResponse: cartResponse.cart)
                                    self.logger.info(message: "Obtained PayPal Link - \(obtainedRedirectLink)")
                                }
                            }
                        } else {
                            
                        }
                        
                    }
                }
            case .Product:
                self.logger.warn(message: "Product Mode Not Implemented")
            }
        }
    }
    
    public func sendPayPalWH(redirectLink: String, cartResponse: Cart) {
        var sessionCookie: String?
        if let cookieArray = self.session.session.configuration.httpCookieStorage?.cookies {
            for (cookie) in cookieArray {
                if cookie.name == "_hs_session_v5" {
                    sessionCookie = cookie.value
                }
            }
        }
        
        let attachment = Attachment(fallback: redirectLink, color: "#75787B", text: "```\(sessionCookie ?? "N/A")```", title: "GREY | PayPal Checkout", titleLink: redirectLink, fields: [WebhookField(title: "Email", value: self.taskObj.accountEmail), WebhookField(title: "Variant", value:"\( cartResponse.lineItems[0].variantID)"), WebhookField(title: "Item", value: "<https://www.off---white.com/\(cartResponse.lineItems[0].url)|\(cartResponse.lineItems[0].name)>")], thumbURL: cartResponse.lineItems[0].imageURL)
        
       
        concurrentWHQueue.async {
            GlobalWH.send(webhook: SlackWebhook(attachments: [attachment]), logger: self.logger)
        }
    }
}
