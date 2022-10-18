import Vapor

func routes(_ app: Application) throws {
    try app.register(collection: CTController())
    try app.register(collection: IISController())
}
