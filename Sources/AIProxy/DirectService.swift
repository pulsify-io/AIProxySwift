//
//  DirectService.swift
//  
//
//  Created by Lou Zell on 12/16/24.
//

import Foundation
import AsyncHTTPClient

protocol DirectService: ServiceMixin {}
extension DirectService {
    var urlSession: URLSession {
        return AIProxyUtils.directURLSession()
    }
    
    var httpClient: HTTPClient? {
        AIProxy.httpClient
    }
}
