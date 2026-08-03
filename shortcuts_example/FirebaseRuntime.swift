import FirebaseAppCheck
import FirebaseCore
import Foundation

@MainActor
enum FirebaseRuntime {
    private static var didAttemptConfiguration = false

    static var isConfigured: Bool {
        FirebaseApp.app() != nil
    }

    static func configureIfAvailable(
        bundle: Bundle = .main
    ) {
        guard !didAttemptConfiguration else {
            return
        }
        didAttemptConfiguration = true

        guard bundle.url(
            forResource: "GoogleService-Info",
            withExtension: "plist"
        ) != nil else {
            RVLogger.d(
                "Firebase 설정 파일이 없어 AI Logic을 비활성화합니다."
            )
            return
        }

        #if DEBUG
        AppCheck.setAppCheckProviderFactory(
            AppCheckDebugProviderFactory()
        )
        #else
        AppCheck.setAppCheckProviderFactory(
            AppAttestProviderFactory()
        )
        #endif
        FirebaseApp.configure()
    }
}
