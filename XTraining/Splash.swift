import SwiftUI

// 打开 App 的动画：深色背景上，渐变 X 弹出来，TRAINING 一个字母一个字母亮起，然后整个画面放大淡出
struct SplashHost: View {
    @State private var done = false
    var body: some View {
        ZStack {
            // 动画结束再放出首页，首页卡片的浮现动画正好接上
            if done {
                RootView().transition(.scale(scale: 0.94).combined(with: .opacity))
            }
            if !done {
                SplashView { withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { done = true } }
                    .transition(.opacity.combined(with: .scale(scale: 1.6)))
                    .zIndex(1)
            }
        }
    }
}

struct SplashView: View {
    let finish: () -> Void
    @State private var xIn = false
    @State private var letters = 0
    @State private var ring = false
    @State private var glow = false
    private let word = Array("TRAINING")

    var body: some View {
        ZStack {
            Color(red: 0.043, green: 0.043, blue: 0.063).ignoresSafeArea()
            // 背后的光
            Circle().fill(Brand.gradient).frame(width: 320, height: 320).blur(radius: 90)
                .opacity(glow ? 0.55 : 0).scaleEffect(glow ? 1.2 : 0.6)
            // 扩散的圈
            Circle().strokeBorder(Brand.gradient, lineWidth: 3)
                .frame(width: 140, height: 140)
                .scaleEffect(ring ? 3.2 : 0.6).opacity(ring ? 0 : 0.9)
            VStack(spacing: 14) {
                Text("X")
                    .font(.system(size: 120, weight: .black)).italic()
                    .foregroundStyle(Brand.gradient)
                    .shadow(color: Brand.pink.opacity(0.6), radius: 24)
                    .scaleEffect(xIn ? 1 : 0.2)
                    .rotationEffect(.degrees(xIn ? 0 : -25))
                    .opacity(xIn ? 1 : 0)
                HStack(spacing: 4) {
                    ForEach(word.indices, id: \.self) { i in
                        Text(String(word[i]))
                            .font(.system(size: 28, weight: .heavy)).italic()
                            .foregroundStyle(.white)
                            .opacity(i < letters ? 1 : 0)
                            .offset(y: i < letters ? 0 : 12)
                            .blur(radius: i < letters ? 0 : 4)
                    }
                }
                .kerning(4)
            }
        }
        .task {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { xIn = true; glow = true }
            withAnimation(.easeOut(duration: 1.1)) { ring = true }
            try? await Task.sleep(for: .milliseconds(350))
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            for i in 1...word.count {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { letters = i }
                try? await Task.sleep(for: .milliseconds(55))
            }
            try? await Task.sleep(for: .milliseconds(450))
            finish()
        }
    }
}
