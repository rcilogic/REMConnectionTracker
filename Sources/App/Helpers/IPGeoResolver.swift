//
//  IPGeoResolver.swift
//  
//
//  Created by Konstantin Gorshkov on 02.08.2022.
//

import Foundation
import Vapor
import Fluent


actor IPGeoResolver {
    typealias IPGeoResolveCompletionHandler = (String?) -> ()
    
    let dbId: DatabaseID
    let cacheExpiresIn: CacheExpirationTime?
    let maxParallelDBTasks: Int
    
    struct ResolveTask {
        let id: UUID = UUID()
        let ipInt: Int
        var isProcessing: Bool = false
        let req: Request
        var completionHandlers: [IPGeoResolveCompletionHandler] = []
    }
    
    var resolveQueue: [ResolveTask] = [] {
        didSet {
            if !isExecutorWorking && !resolveQueue.isEmpty {
                isExecutorWorking = true
                Task { await executeTasks() }
                isExecutorWorking = false
            }
        }
    }
    
    
    var isExecutorWorking = false
    
    init (dbId: DatabaseID, maxParallelDBTasks: Int = 3, cacheExpiresIn: CacheExpirationTime? = nil) {
        self.dbId = dbId
        self.cacheExpiresIn = cacheExpiresIn
        self.maxParallelDBTasks = maxParallelDBTasks
    }
    
    private func executeTasks () async {
        await withTaskGroup(of: Void.self) { group -> Void in
            for tid in 0..<maxParallelDBTasks {
                group.addTask { [weak self] in
                    while self != nil, await !self!.resolveQueue.isEmpty {
                        guard let resolveTask = await self?.getFreeTaskFromQueue(tid: tid) else {
                            await Task.yield()
                            continue
                        }
                        let resolvedIPGeo = await self?.dbTask(ipInt: resolveTask.ipInt, req: resolveTask.req)
                        await self?.completeTaskWithID(resolveTask.id, ipGeoJSON: resolvedIPGeo)
                    }
                }
            }
        }
    }
    
    private func getFreeTaskFromQueue (tid: Int) -> ResolveTask? {
        guard let index = resolveQueue.firstIndex(where: { !$0.isProcessing }) else { return nil }
        resolveQueue[index].isProcessing = true
        return resolveQueue[index]
    }
    
    private func completeTaskWithID (_ id: UUID, ipGeoJSON: String?) {
        guard let index = resolveQueue.firstIndex(where:{ $0.id == id }) else { return }
        resolveQueue[index].completionHandlers.forEach {completionHandler in
            completionHandler(ipGeoJSON)
        }
        resolveQueue.remove(at: index)
    }
    

    public func getIPGeoJSON (for ip: String, on req: Request) async -> String? {
        guard let ipInt = Self.ipv4ToInt(ip), !Self.isIPInternal(ipInt) else { return nil }
        
        if let cachedIPGeo = try? await req.cache.get("ipv4:\(ip)", as: String.self) { return cachedIPGeo }
      
        return await withCheckedContinuation { continuation in
            withResolvedIPGeoJSON(for: ipInt, req: req) { ipGeoJSON in
                continuation.resume(returning: ipGeoJSON)
            }
        }
    }
    
    private func withResolvedIPGeoJSON (for ipInt: Int, req: Request, completionHandler: @escaping IPGeoResolveCompletionHandler) {
        if let existIndex = resolveQueue.firstIndex(where: { $0.ipInt == ipInt }) {
            resolveQueue[existIndex].completionHandlers.append(completionHandler)
        } else {
            resolveQueue.append(ResolveTask(ipInt: ipInt, req:req, completionHandlers: [
                completionHandler,
                { [weak self] ipGeoJSON in
                    _ = req.cache.set("ipv4:\(Self.ipIntv4ToString(ipInt))", to: ipGeoJSON, expiresIn: self?.cacheExpiresIn)
                }
            ]))
        }
    }
    

    
    
    func dbTask (ipInt: Int, req: Request) async -> String? {
        guard let ipGeo = try? await IPGeo.query(on: req.db(dbId))
            .filter(\.$ipFrom < ipInt)
            .first()
        else { return nil }
        
        return Self.ipGeoToJSON(ip: Self.ipIntv4ToString(ipInt), ipgeo: ipGeo)
    }
    
    
    static func getIPGeo (ip: String, req: Request, cacheExpiresIn: CacheExpirationTime? = nil) async -> String? {
        
        guard let ipInt = Self.ipv4ToInt(ip), !isIPInternal(ipInt) else { return nil }
        
        if let cachedIPGeo = try? await req.cache.get("ipv4:\(ip)", as: String.self) { return cachedIPGeo }
       
        guard let ipGeo = try? await IPGeo.query(on: req.db(.sqlite))
            .filter(\.$ipFrom < ipInt)
            .first()
        else { return nil }
       
        let result = ipGeoToJSON(ip: ip, ipgeo: ipGeo)
        
        try? await req.cache.set("ipv4:\(ip)", to: result, expiresIn: cacheExpiresIn)
        
        return result
        
    }
    
    static func ipGeoToJSON (ip: String, ipgeo: IPGeo) -> String {
           """
           {"ip":"\(ip)","countryCode":"\(ipgeo.countryCode)","countryName":"\(ipgeo.countryName)","regionName":"\(ipgeo.regionName)","cityName":"\(ipgeo.cityName)","isp":"\(ipgeo.isp)","domain":"\(ipgeo.domain)","usageType":"\(ipgeo.usageType)","asNumber":"\(ipgeo.asNumber)","asName":"\(ipgeo.asName)"}
           """
    }
    
    static func ipIntv4ToString (_ ipInt: Int) -> String {
        let rankValue = [16777216,65536,256,1]
        var resultIP = [0,0,0,0]
        
        var remainder = ipInt
        for i in 0..<4 {
            resultIP[i] = Int(floor( Double(remainder) / Double(rankValue[i]) ))
            remainder %= rankValue[i]
        }
        
        return resultIP.map{String($0)}.joined(separator: ".")
    }
    
    static func ipv4ToInt (_ ip: String) -> Int? {
        let octets: [Int?] = ip.split(separator: ".").map{Int($0)}
        guard octets.count == 4, !octets.contains(nil) else { return nil }
        // Precalculated (2^8)^n where n = 3,2,1,0
        let rankValue = [16777216,65536,256,1]
        var result = 0
        for index in 0..<4 {
            guard octets[index]! >= 0 && octets[index]! < 256 else { return nil }
            result += octets[index]! * rankValue[index]
        }
        return result
    }
    
    static func isIPInternal (_ ip: Int) -> Bool {
        if (167772160...184549375).contains(ip) ||
            (1681915904...1686110207).contains(ip) ||
            (2851995648...2852061183).contains(ip) ||
            (2886729728...2887778303).contains(ip) ||
            (3232235520...3232301055).contains(ip) ||
            (2130706432...2147483647).contains(ip) { return true }
        return false
    }
    
    static func isIPInternal (_ ip: String) -> Bool? {
        guard let ipInt = Self.ipv4ToInt(ip) else { return nil }
        return Self.isIPInternal(ipInt)
    }
    
}

struct IPGeoReolverKey: StorageKey {
    typealias Value = IPGeoResolver
}


extension Application {
    var ipGeoResolver: IPGeoResolver? {
        get {
            self.storage[IPGeoReolverKey.self]
        }
        set {
            self.storage[IPGeoReolverKey.self] = newValue
        }
    }
}
