import Vapor
import Redis
import REMCommons
import Fluent
import FluentSQLiteDriver

// configures your application
public func configure(_ app: Application) throws {
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    app.redis.configuration = try REMCommons.getRedisConfiguration()
    
    app.sessions.use(.redis)
    app.sessions.configuration.cookieName = REMCommons.sessionCookieName
    app.middleware.use(app.sessions.middleware)
    
    Environment.get(.contrecHTTPHost).flatMap{ app.http.server.configuration.hostname = $0 }
    Environment.get(.contrecHTTPPort).flatMap{ app.http.server.configuration.port = Int($0) ?? app.http.server.configuration.port }
     
    guard let ipGegoSQLiteDBPath = Environment.get(.contrecIPGeoSQLiteDBPath) else { throw REMCTError.InvalidIPGeoSQLiteDBPath}
    app.databases.use(.sqlite(.file(ipGegoSQLiteDBPath), connectionPoolTimeout: .seconds(300)), as: .sqlite)

   
    // register routes
    try routes(app)
    
    var iisDataReceiver = IISDataReceiver()
    guard let targetsConfPath = Environment.get(.contrecTargetsConfPath) else { throw REMCTError.InvalidTargetsConfPath }
    let targets = try REMCommons.loadJSON(from: targetsConfPath, as: [ConnectionTrackerTargetConfig].self)
    iisDataReceiver.targets = targets
    app.iisDataReceiver = iisDataReceiver
    
    app.ipGeoResolver = IPGeoResolver(
        dbId: .sqlite,
        maxParallelDBTasks: 10,
        cacheExpiresIn: .minutes(3)
    )
    
}

extension Environment {
    static func get (_ key: REMServiceEnvKey) -> String? { Self.get(key.rawValue) }
    enum REMServiceEnvKey: String {
        case contrecHTTPHost = "REM_CONNECTIONTRACKER_HTTP_HOST"
        case contrecHTTPPort = "REM_CONNECTIONTRACKER_HTTP_PORT"
        case contrecTargetsConfPath =  "REM_CONNECTIONTRACKER_TARGETS_CONF_PATH"
        case contrecIPGeoSQLiteDBPath = "REM_CONNECTIONTRACKER_IPGEO_SQLITE_DB_PATH"
        case contrecIPGeoResolverThreads="REM_CONNECTIONTRACKER_IPGEO_THREADS"
        case conntrecIPGeosResolverCacheTTLMinutes="REM_CONNECTIONTRACKER_IPGEO_TTL_MINUTES"
    }
}

enum REMCTError: Error {
    case InvalidIPGeoSQLiteDBPath
    case InvalidTargetsConfPath
}
