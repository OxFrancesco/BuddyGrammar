import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginService {
    func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }
}
