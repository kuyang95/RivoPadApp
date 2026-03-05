import SwiftUI

struct HomeView: View {
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                
                HStack(spacing: 0) {
                    
                    QuadrantView(
                        title: "OCR",
                        color: .white
                    ) {
                        print("Top Left tapped")
                    }
                    
                    QuadrantView(
                        title: "OCR 확대",
                        color: .white
                    ) {
                        print("Top Right tapped")
                    }
                }
                
                HStack(spacing: 0) {
                    
                    QuadrantView(
                        title: "이미지 질의",
                        color: .white
                    ) {
                        print("Bottom Left tapped")
                    }
                    
                    QuadrantView(
                        title: "문서 질의",
                        color: .white
                    ) {
                        print("Bottom Right tapped")
                    }
                }
            }
            .ignoresSafeArea()
        }
    }
}

struct QuadrantView: View {
    
    var title: String
    var color: Color
    var action: () -> Void
    
    var body: some View {
        ZStack {
            color
            
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.black)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            action()
        }
    }
}

#Preview {
    ContentView()
}
