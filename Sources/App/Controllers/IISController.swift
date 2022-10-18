//
//  IISController.swift
//  
//
//  Created by Konstantin Gorshkov on 02.08.2022.
//

import Vapor
import SSHInvoker

struct IISController: RouteCollection {
    
    func boot(routes: RoutesBuilder) throws {
        let iisRoute = routes.grouped ("api", "connectiontracker", "iis")
        
        iisRoute.get(":sourceName", use: getDigest)
    }
    
    func getDigest(_ req: Request) throws -> Response {
        let query = """
            SELECT DISTINCT c-ip as id, date, c-ip, cs-username, sc-status, cs(User-Agent)
            FROM #logFiles#
            WHERE #commonPredicates#
            """
        
        return try execQuery(query, req: req, encodeToJSONByFields: ["id","date","clientIP", "userName", "protocolStatus","userAgent"])
    }
    

    
    
}



extension IISController {
    private func execQuery (_ query: String, req: Request, encodeToJSONByFields: [String]? = nil) throws -> Response {
        let sourceName = req.parameters.get("sourceName")!.lowercased()
        let commonParameters = try? URLEncodedFormDecoder().decode(IISQueryCommonParams.self, from: req.url)
        
        var commonPredicates = "#dateFilter#"
        
        if let ipFilter = commonParameters?.excludeInternalIPs, ipFilter == true {
            commonPredicates += " AND #excludeInternalIPs#"
        }
        
        if let userType = commonParameters?.userType?.rawValue {
            commonPredicates += " AND #userType=\(userType)#"
        }
        
        if let urlFilters = commonParameters?.urlFilters, urlFilters.count > 0 {
            commonPredicates += " AND ("
            for index in 0..<urlFilters.count {
                commonPredicates += "\(index > 0 ? " OR" : "") cs-uri-stem LIKE '/\(urlFilters[index])' OR cs-uri-stem LIKE '/\(urlFilters[index])/%'"
            }
            commonPredicates += " )"
        }
               
        let query = query.replacingOccurrences(of: "#commonPredicates#", with: commonPredicates)
        
        guard let iisDataReceiver = req.application.iisDataReceiver else {
            req.logger.warning ("iisDataReceiver object not found")
            throw Abort(.internalServerError)
        }
        guard iisDataReceiver.targetExists(sourceName) else { throw Abort(.notFound) }
        
        return try iisDataReceiver.makeStreamimgResponse (
            for: query,
               on: sourceName,
               startDate: commonParameters?.startDate,
               endDate: commonParameters?.endDate,
               encodeToJSONByFields: encodeToJSONByFields,
               req: req
        )
    }
}

struct IISQueryCommonParams: Codable {
    let startDate: Date?
    let endDate: Date?
    let excludeInternalIPs: Bool?
    let userType: UserType?
    let urlFilters: [String]?
    
    enum UserType: String, Codable {
        case authenticated, anonymous
    }
}
