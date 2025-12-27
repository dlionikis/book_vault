//
//  ContentView.swift
//  BookVault
//
//  Created by Claude Code on 12/26/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "books.vertical")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("BookVault")
                .font(.largeTitle)
            Text("iOS Pre-Development Setup Complete")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
