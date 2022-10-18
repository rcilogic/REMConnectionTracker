//
//  IISDataReceiver.swift
//  
//
//  Created by Konstantin Gorshkov on 02.08.2022.
//

import SSHInvoker
import Vapor
import Fluent

public struct IISDataReceiver {
    
    public var targets: [ConnectionTrackerTargetConfig] = []
    public var targetsPublic: [ConnectionTrackerTargetConfig.Public] { targets.map {$0.targetPublic} }
    public func targetExists (_ name: String) -> Bool { targets.contains(where: {$0.name.lowercased() == name .lowercased()})}
    public func getTargetByName (_ name: String) -> RemoteSource? {
        guard let target = targets.first(where: {$0.name.lowercased() == name.lowercased()}) else { return nil }
        
        return RemoteSource(
            target: .init(host: target.host, port: Int(target.port) ?? 22),
            credentials: .password(username: target.username, password: target.password),
            serverAuth: .publicKey(target.serverPublicKey)
        )
        
    }
    
    public func execQuery (
        _ query: String,
        on sourceName: String,
        startDate: Date? = nil,
        endDate: Date? = nil,
        req: Request,
        wantResult: Bool = false,
        inboundStreamHandler: SSHInvoker.InboundStreamHandler?
    ) -> EventLoopFuture<SSHInvoker.Result?>
    {
        guard let source = getTargetByName(sourceName) else { return req.eventLoop.makeFailedFuture(IISDataReceiverError.InvalidTargetName) }
        
        let scriptParameters = """
        $logsPath = '\(source.logsPath)'
        $startDate = \( startDate != nil ? "'\(startDate!)' -as [datetime]" : "$null" )
        $endDate = \( endDate != nil ? "'\(endDate!)' -as [datetime]" : "$null" )
        $query = "\(query)"
        
        """
        
        let script = scriptParameters + Self.execQueryScript
        
        return SSHInvoker.sendScript(
            script,
            scriptExecutionTimeout: .minutes(60),
            target: source.target,
            serverAuthentication: source.serverAuth,
            connectionTimeout: .seconds(30),
            credentials: source.credentials,
            eventLoopGroup: req.eventLoop,
            wantResult: wantResult,
            inboundStreamHandler: inboundStreamHandler
        )
        
        
    }
    
    func makeStreamimgResponse (
    for query: String,
        on sourceName: String,
        startDate: Date? = nil,
        endDate: Date? = nil,
        encodeToJSONByFields: [String]?,
        req: Request
    ) throws -> Response
    {
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "text/event-stream")
        
        return Response (headers: headers, body: .init(stream: { writer in
            
            let allocator = ByteBufferAllocator()
            let encoding = String.Encoding.windowsCP1251
            var sentIPGeos: [String] = []
            
            var ipGeoResolveFutures: [EventLoopFuture<Void>] = []
        
            let resultFuture = execQuery(
                query,
                on: sourceName,
                startDate: startDate,
                endDate: endDate,
                req: req,
                wantResult: false
            ) { buf, bufType in
                var buf = buf
                buf.convertFromCP866ToWindows1251()
                
                switch bufType {
                case .stdout:
                    if let encodeWithFields = encodeToJSONByFields {
                        guard buf.getString(at: 0, length: buf.readableBytes, encoding: encoding) != "\r\n" else { return }
                        guard let (jsonBuf, clientIP) = try? buf.wrapToJSON(fields: encodeWithFields, encoding: encoding, extractField: "clientIP", allocator: allocator) else {
#if DEBUG
                            req.logger.warning("Can't convert data to JSON: \n Data:\n\(buf.getString(at: 0, length: buf.readableBytes, encoding: encoding) ?? "!DataConversionError!")")
#endif
                            return
                        }
                        
                        buf = jsonBuf.wrapToSSE(encoding: encoding, allocator: allocator)
                        
                        let bufWriteFuture = writer.write(.buffer(buf))
                        
                        guard let clientIP = clientIP else { return }
                        guard !sentIPGeos.contains(clientIP) else { return }
                        sentIPGeos.append(clientIP)
                        
                        let ipGeoJsonPromise = writer.eventLoop.makePromise(of: String?.self)
                        
                        ipGeoJsonPromise.completeWithTask{
                            return await req.application.ipGeoResolver?.getIPGeoJSON(for: clientIP, on: req)
                        }
                        
                        ipGeoResolveFutures.append(
                            ipGeoJsonPromise.futureResult.and(bufWriteFuture).map { (ipGeoJson, _) in
                                guard let ipGeoJson = ipGeoJson else { return }
                                writer.write(.buffer(allocator.buffer(string: ipGeoJson).wrapToSSE(eventName: "ipgeo", encoding: encoding, allocator: allocator)), promise: nil)
                            }
                        )
                        
                    } else {
                        writer.write(.buffer(buf),promise: nil)
                    }
                    
                case .stderr:
#if DEBUG
                    req.logger.warning("stdErr: \(buf.getString(at: 0, length: buf.readableBytes, encoding: encoding) ?? "!DataConversionError!")")
#endif
                    writer.write(.buffer(buf),promise: nil)
                }
            }
            
            resultFuture.whenComplete{result in
                EventLoopFuture.andAllComplete(ipGeoResolveFutures, on: req.eventLoop).whenComplete { _ in
                    writer.write(.buffer(allocator.buffer(string: "").wrapToSSE(eventName: "stop", encoding: encoding, allocator: allocator)))
                        .whenComplete{ _ in
                            switch result {
                            case .success:
                                writer.write(.end, promise: nil)
                            case .failure(let error):
                                writer.write(.error(error), promise: nil)
                            }
                        }
                }
            }
        }))
        
    }
    
    
    
    
}

enum IISDataReceiverError: Error {
    case InvalidTargetName
    case CantLoadPowerShellScript
}

extension IISDataReceiver {
    public struct RemoteSource {
        let target: SSHInvoker.Target
        let credentials: SSHInvoker.Credentials
        let serverAuth: SSHInvoker.ServerAuthentication
        let logsPath: String
        
        init(
            target: SSHInvoker.Target,
            credentials: SSHInvoker.Credentials,
            serverAuth: SSHInvoker.ServerAuthentication,
            logsPath: String = #"C:\inetpub\logs\LogFiles\W3SVC1"#
        ) {
            self.target = target
            self.credentials = credentials
            self.serverAuth = serverAuth
            self.logsPath = logsPath
        }
    }
}

struct IISDataReceiverKey: StorageKey {
    typealias Value = IISDataReceiver
}

extension Application {
    var iisDataReceiver: IISDataReceiver? {
        get {
            self.storage[IISDataReceiverKey.self]
        }
        set {
            self.storage[IISDataReceiverKey.self] = newValue
        }
    }
}

public struct ConnectionTrackerTargetConfig: Codable {
    enum TargetType: String, Codable {
        case iis,rdgw,empty
    }
    let type: TargetType
    let name: String
    let description: String
    let host: String
    let port: String
    let username: String
    let password: String
    let serverPublicKey: String
    let options: [String]
    let optionsSelected: [String]
}

public extension ConnectionTrackerTargetConfig {
    struct Public: Content {
        let type: ConnectionTrackerTargetConfig.TargetType
        let name: String
        let url: String
        let description: String
        let options: [String]
        let optionsSelected: [String]
    }
}

public extension ConnectionTrackerTargetConfig {
    var targetPublic: Self.Public {
        return .init(
            type: type,
            name: name,
            url: "iis/\(name.lowercased())",
            description: description,
            options: options,
            optionsSelected: optionsSelected
        )
    }
}
