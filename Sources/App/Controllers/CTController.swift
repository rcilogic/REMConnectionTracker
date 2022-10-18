//
//  Created by Konstantin Gorshkov on 05.08.2022
//  Copyright (c) 2022 Konstantin Gorshkov. All Rights Reserved
//  See LICENSE.txt for license information
//
//  SPDX-License-Identifier: Apache-2.0
//
   

import Vapor


struct CTController: RouteCollection {
    
    func boot(routes: RoutesBuilder) throws {
        let iisRoute = routes.grouped ("api", "connectiontracker")
        
        iisRoute.get("targets", use: getTargets)
    }
    
    func getTargets (_ req: Request) throws -> [ConnectionTrackerTargetConfig.Public] {
        guard req.application.iisDataReceiver != nil else { throw Abort(.internalServerError) }
        return req.application.iisDataReceiver!.targetsPublic
    }
    
}
