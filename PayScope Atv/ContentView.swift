import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = TVWeeklyScheduleViewModel()

    var body: some View {
        TVWeeklyScheduleView(viewModel: viewModel)
            .task {
                await viewModel.reload()
            }
    }
}

#Preview {
    ContentView()
}
