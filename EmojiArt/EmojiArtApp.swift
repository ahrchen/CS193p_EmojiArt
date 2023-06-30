//
//  EmojiArtApp.swift
//  EmojiArt
//
//  Created by Raymond Chen on 6/26/23.
//

import SwiftUI

@main
struct EmojiArtApp: App {
    let document = EmojiArtDocument()
    
    var body: some Scene {
        WindowGroup {
            EmojiArtDocumentView(document: document)
        }
    }
}
