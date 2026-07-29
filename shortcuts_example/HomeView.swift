import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appRouter: AppRouter
    
    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()
            
            VStack(spacing: 32) {
                Button {
                    appRouter.route = .chatHistory
                } label: {
                    Text("AI 채팅")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: 520)
                        .frame(height: 120)
                        .background(Color.indigo)
                        .cornerRadius(28)
                }
                .accessibilityHint(
                    "저장된 대화를 보거나 새 로컬 AI 대화를 시작합니다."
                )

                Button {
                    appRouter.route = .documentScanning
                } label: {
                    Text("카메라")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: 520)
                        .frame(height: 120)
                        .background(Color.black)
                        .cornerRadius(28)
                }
                
                Button {
                    print("파일에서 tapped")
                } label: {
                    Text("파일")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: 520)
                        .frame(height: 120)
                        .background(Color.black)
                        .cornerRadius(28)
                }
            }
        }
    }
}
