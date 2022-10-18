//
//  IPGeo.swift
//  
//
//  Created by Konstantin Gorshkov on 02.08.2022.
//

import Fluent
import Vapor



final class IPGeo: Model, Content {
    
    static let schema = "ip"
    
    @ID(custom: "id")
    var id: Int?
    
    @Field(key: "ip_from")
    var ipFrom: Int
    
    @Field(key: "country_code")
    var countryCode: String
    
    @Field(key: "country_name")
    var countryName: String
    
    @Field(key: "region_name")
    var regionName: String
    
    @Field(key: "city_name")
    var cityName: String
    
    @Field(key: "isp")
    var isp: String
    
    @Field(key: "domain")
    var domain: String
    
    @Field(key: "usage_type")
    var usageType: String
    
    @Field(key: "asn")
    var asNumber: Int
    
    @Field(key: "as")
    var asName: String

    init() { }

    init(id: UUID? = nil) {

    }
}


