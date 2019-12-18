//
//  Variti.swift
//  grey
//
//  Created by Hasan Gondal on 15/12/2019.
//  Copyright © 2019 Hasan Gondal. All rights reserved.
//

import Foundation

import CommonCrypto

extension String {
    func md5() -> String {
        let data = Data(utf8) as NSData
        var hash = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        CC_MD5(data.bytes, CC_LONG(data.length), &hash)
        return hash.map { String(format: "%02hhx", $0) }.joined()
    }
}

func solveVariti(response: String) -> [HTTPCookie] {
    let privateKeyString = response.components(separatedBy: "decrypt.setPrivateKey(\"")[1].components(separatedBy: "\");")[0]
    let encryptedText = response.components(separatedBy: "decrypt.decrypt(\"")[1].components(separatedBy: "\");")[0]

    guard let keyData = Data(base64Encoded: privateKeyString),
        let encryptedData = Data(base64Encoded: encryptedText),
        let privateKey = SecKeyCreateWithData(keyData as NSData, [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
        ] as NSDictionary, nil),
        let decryptedByteArray = SecKeyCreateDecryptedData(privateKey, SecKeyAlgorithm.rsaEncryptionPKCS1, encryptedData as CFData, nil),
        let valueIPP_Key = String(bytes: decryptedByteArray as Data, encoding: .utf8) else {
        return []
    }

    let valueIPP_UID = response.components(separatedBy: "document.cookie=\"ipp_uid=")[1].components(separatedBy: ";")[0]
    let valueIPP_UID1 = response.components(separatedBy: "document.cookie=\"ipp_uid1=")[1].components(separatedBy: ";")[0]
    let valueIPP_UID2 = response.components(separatedBy: "document.cookie=\"ipp_uid2=")[1].components(separatedBy: ";")[0]
    let valueSalt = response.components(separatedBy: "salt=\"")[1].components(separatedBy: "\"")[0]
    let deviceFingerprint = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()

    var cookieDictionary: [String: String] = [:]

    cookieDictionary["ipp_key"] = valueIPP_Key
    cookieDictionary["ipp_uid"] = valueIPP_UID
    cookieDictionary["ipp_uid1"] = valueIPP_UID1
    cookieDictionary["ipp_uid2"] = valueIPP_UID2
    cookieDictionary["ipp_sign"] = "\(deviceFingerprint)_\(valueSalt)_\((deviceFingerprint + valueSalt).md5())"

    let ExpTime = TimeInterval(60 * 60 * 24 * 365)

    var cookieArray: [HTTPCookie] = []

    for (cookieName, cookieValue) in cookieDictionary {
        let cookieProperties: [HTTPCookiePropertyKey: Any] = [
            HTTPCookiePropertyKey.domain: "www.off---white.com",
            HTTPCookiePropertyKey.path: "/",
            HTTPCookiePropertyKey.name: cookieName,
            HTTPCookiePropertyKey.value: cookieValue,
            HTTPCookiePropertyKey.expires: NSDate(timeIntervalSinceNow: ExpTime),
        ]

        guard let cookie = HTTPCookie(properties: cookieProperties) else {
            continue
        }
        cookieArray.append(cookie)
    }

    return cookieArray
}
