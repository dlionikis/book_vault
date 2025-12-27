import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationView {
            VStack {
                Image(systemName: "books.vertical")
                    .imageScale(.large)
                    .foregroundColor(.accentColor)
                    .font(.system(size: 60))

                Text("Book Vault")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding()

                Text("Your personal audiobook library")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .navigationTitle("Book Vault")
        }
    }
}

#Preview {
    ContentView()
}
