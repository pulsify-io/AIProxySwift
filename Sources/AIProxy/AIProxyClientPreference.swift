//
//  AIProxyClientPreference.swift
//  AIProxy
//
//  Created by Theo Kallioras on 3/5/25.
//

import AsyncHTTPClient

public enum AIProxyClientPreference {
    case urlSession
    case httpClient(HTTPClient)
}