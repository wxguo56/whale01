import CoreLocation
import Foundation

@MainActor
final class CurrentLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var cached: CLLocation?

    private let cacheLifetime: TimeInterval = 60
    private let acceptableAccuracy: CLLocationAccuracy = 300

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func currentLocation() async throws -> CLLocation {
        if let cached,
           Date().timeIntervalSince(cached.timestamp) <= cacheLifetime,
           cached.horizontalAccuracy >= 0,
           cached.horizontalAccuracy <= acceptableAccuracy {
            return cached
        }

        guard CLLocationManager.locationServicesEnabled() else {
            throw ToolExecutionError(
                code: "location_services_disabled",
                message: "系统定位服务未开启；请先打开定位服务，或直接给我一个地区。",
                permission: "location"
            )
        }

        var status = manager.authorizationStatus
        if status == .notDetermined {
            status = await waitForAuthorization()
        }

        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            break
        case .denied, .restricted:
            throw ToolExecutionError(
                code: "location_permission_denied",
                message: "定位权限被拒绝；请在系统设置中允许定位，或直接给我一个地区。",
                permission: "location"
            )
        default:
            throw ToolExecutionError(
                code: "location_permission_unknown",
                message: "定位权限状态不明，本次没有取得位置；可以给我一个明确地区。",
                permission: "location"
            )
        }

        return try await requestLocation()
    }

    private func waitForAuthorization() async -> CLAuthorizationStatus {
        manager.requestWhenInUseAuthorization()
        for _ in 0..<16 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            let status = manager.authorizationStatus
            if status != .notDetermined {
                return status
            }
        }
        return manager.authorizationStatus
    }

    private func requestLocation() async throws -> CLLocation {
        if continuation != nil {
            throw ToolExecutionError(code: "location_busy", message: "上一次定位请求尚未结束，请稍后重试")
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
            timeoutTask?.cancel()
            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled, let self else { return }
                self.finish(
                    .failure(
                        ToolExecutionError(
                            code: "location_timeout",
                            message: "超过 10 秒没有取得有效位置；可以重试，或直接给我一个地区。"
                        )
                    )
                )
            }
        }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor [weak self] in
            guard let self, let location = locations.last else { return }
            guard location.horizontalAccuracy >= 0 else {
                self.finish(
                    .failure(ToolExecutionError(code: "location_invalid", message: "系统返回的位置无效，请稍后重试。"))
                )
                return
            }
            guard location.horizontalAccuracy <= 500 else {
                self.finish(
                    .failure(
                        ToolExecutionError(
                            code: "location_accuracy_low",
                            message: "定位精度不足（约 \(Int(location.horizontalAccuracy)) 米），没有把它当作当前位置；请到开阔处重试或给我一个地区。"
                        )
                    )
                )
                return
            }
            self.cached = location
            self.finish(.success(location))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let clError = error as? CLError, clError.code == .denied {
                self.finish(
                    .failure(
                        ToolExecutionError(
                            code: "location_permission_denied",
                            message: "定位权限被拒绝；请在系统设置中允许定位，或直接给我一个地区。",
                            permission: "location"
                        )
                    )
                )
                return
            }
            self.finish(
                .failure(
                    ToolExecutionError(
                        code: "location_unavailable",
                        message: "无法取得当前位置：\(error.localizedDescription)"
                    )
                )
            )
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {}
}
