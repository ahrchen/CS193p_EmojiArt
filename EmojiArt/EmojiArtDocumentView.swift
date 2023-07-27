//
//  EmojiArtDocumentView.swift
//  EmojiArt
//
//  Created by Raymond Chen on 6/28/23.
//

import SwiftUI

struct EmojiArtDocumentView: View {
    @ObservedObject var document: EmojiArtDocument
    
    let defaultEmojiFontSize: CGFloat = 40
    
    var body: some View {
        VStack(spacing: 0) {
            documentBody
            PaletteChooser(emojiFontSize: defaultEmojiFontSize)
        }
    }
    
    var documentBody: some View {
        GeometryReader { geometry in
            ZStack {
                Color.white.overlay(
                    OptionalImage(uiImage: document.backgroundImage)
                        .scaleEffect(zoomScale)
                        .position(convertFromEmojiCoordinates((0,0), in: geometry))
                )
                .gesture(doubleTapToZoom(in: geometry.size))
                if document.backgroundImageFetchStatus == .fetching {
                    ProgressView().scaleEffect(2) 
                } else {
                    ForEach(document.emojis) { emoji in
                        Text(emoji.text)
                            .font(.system(size: fontSize(for: emoji)))
                            .position(position(for: emoji, in: geometry))
                            .shadow(color: emoji.isSelected ? Color.blue : Color.white, radius: 5)
                            .onTapGesture {
                                selectEmoji(emoji: emoji)
                            }
                            .gesture(emoji.isSelected ? dragGesture() : nil)
                            .gesture(!emoji.isSelected ? dragGesture(emoji: emoji): nil)
                    }
                }
                if document.emojis.contains(where: {$0.isSelected}) {
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                document.deleteSelectedEmoji()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.title)
                            }
                            .padding(10)
                        }
                        Spacer()
                    }
                }

            }
            .clipped()
            .onDrop(of: [.plainText, .url, .image], isTargeted: nil) { providers, location in
                return drop(providers: providers, at: location, in: geometry)
            }
            .gesture(!document.emojis.contains(where: {$0.isSelected}) ? panGesture().simultaneously(with:zoomGesture()) : nil)
            .gesture(document.emojis.contains(where: {$0.isSelected}) ? panGesture().simultaneously(with:scaleGesture()): nil)
            .alert(item: $alertToShow) { alertToShow in
                alertToShow.alert()
            }
            .onChange(of: document.backgroundImageFetchStatus) { status in
                switch status {
                case .failed(let url):
                    showBackgroundImageFetchFailedAlert(url)
                default:
                    break
                }
            }
            .onReceive(document.$backgroundImage) { image in
                if autozoom {
                    zoomToFit(image, in: geometry.size)
                }
            }
        }
    }
    
    @State private var autozoom = false
    @State private var alertToShow: IdentifiableAlert?
    
    private func showBackgroundImageFetchFailedAlert(_ url: URL) {
        alertToShow = IdentifiableAlert(id: "fetch failed: " + url.absoluteString, alert: {
            Alert(
                title: Text("Background Image Fetch"),
                message:  Text("Couldn't load image from \(url)."),
                dismissButton: .default(Text("OK"))
            )
        })
    }
    
    private func selectEmoji(emoji: EmojiArtModel.Emoji) {
        document.selectEmoji(emoji)
    }
    
    private func drop(providers: [NSItemProvider], at location: CGPoint, in geometry: GeometryProxy) -> Bool {
        var found = providers.loadObjects(ofType: URL.self) { url in
            autozoom = true
            document.setBackground(EmojiArtModel.Background.url(url.imageURL))
        }
        if !found {
            found = providers.loadObjects(ofType: UIImage.self, using: { image in
                if let data = image.jpegData(compressionQuality: 1.0) {
                    autozoom = true 
                    document.setBackground(.imageData(data))
                }
            })
        }
        if !found {
            found = providers.loadObjects(ofType: String.self) { string in
                if let emoji = string.first, emoji.isEmoji {
                    document.addEmoji(String(emoji),
                      at: convertToEmojiCoordinates(location, in: geometry),
                      size: defaultEmojiFontSize / zoomScale
                    )
                }
                
            }
        } 
        return found
    }
    
    private func position(for emoji: EmojiArtModel.Emoji, in geometry: GeometryProxy ) -> CGPoint {
        if emoji.isSelected {
            let x = emoji.x +  Int(gestureDragOffset.width)
            let y = emoji.y +  Int(gestureDragOffset.height)
            return convertFromEmojiCoordinates((x, y), in: geometry)
        } else if emoji.isDragging {
            let x = emoji.x + Int(gestureSingleDragOffset.width)
            let y = emoji.y + Int(gestureSingleDragOffset.height)
            return convertFromEmojiCoordinates((x, y), in: geometry)
        } else {
            let x = emoji.x
            let y = emoji.y
            return convertFromEmojiCoordinates((x, y), in: geometry)
        }

    }
    private func convertToEmojiCoordinates(_ location: CGPoint, in geometry: GeometryProxy) -> (x: Int, y: Int) {
        let center = geometry.frame(in: .local).center
        let location = CGPoint(
            x: (location.x - panOffset.width - center.x) / zoomScale,
            y: (location.y - panOffset.height - center.y) / zoomScale
            )
        return (Int(location.x), Int(location.y))
    }
    private func convertFromEmojiCoordinates(_ location: (x: Int, y: Int), in geometry: GeometryProxy) -> CGPoint {
        let center = geometry.frame(in: .local).center
        return CGPoint(
            x: center.x + CGFloat(location.x) * zoomScale + panOffset.width,
            y: center.y + CGFloat(location.y) * zoomScale + panOffset.height
        )
    }
    
    private func fontSize(for emoji: EmojiArtModel.Emoji) -> CGFloat {
        CGFloat(emoji.size) * (emoji.isSelected ? gestureStateEmojiScale * zoomScale : zoomScale)
    }
    
    @SceneStorage("EmojiArtDocumentView.steadyStateZoomScale") private var steadyStateZoomScale: CGFloat = 1
    @GestureState private var gestureZoomScale: CGFloat = 1
    
    @SceneStorage("EmojiArtDocumentView.steadyStatePanOffset") private var steadyStatePanOffset: CGSize = .zero
    @GestureState private var gesturePanOffset: CGSize = .zero
    
    private var panOffset: CGSize {
        (steadyStatePanOffset + gesturePanOffset) * zoomScale
    }
    
    @GestureState private var gestureSingleDragOffset: CGSize = .zero
    @GestureState private var gestureDragOffset: CGSize = .zero
    @GestureState private var gestureStateEmojiScale: CGFloat = 1
    
    private func scaleGesture() -> some Gesture {
        MagnificationGesture()
            .updating($gestureStateEmojiScale, body: { latestGestureScale, gestureStateEmojiScale, _ in
                gestureStateEmojiScale = latestGestureScale
            })
            .onEnded { gestureScaleAtEnd in
                for emoji in document.emojis {
                    if emoji.isSelected {
                        document.scaleEmoji(emoji, by: gestureScaleAtEnd)
                    }
                }
            }
    }

    private func dragGesture(emoji: EmojiArtModel.Emoji) -> some Gesture {
        
        DragGesture()
            .onChanged({ _ in
                document.draggingEmoji(emoji, isDragging: true)
            })
            .updating($gestureSingleDragOffset) { latestDragGestureValue, gestureSingleDragOffset, _ in
                gestureSingleDragOffset = (latestDragGestureValue.translation / zoomScale)
                
            }
            .onEnded { finalDragGestureValue in
                document.moveEmoji(emoji, by: finalDragGestureValue.translation / zoomScale)
                document.draggingEmoji(emoji, isDragging: false)
            }
    }
    
    private func dragGesture() -> some Gesture {

        DragGesture()
            .updating($gestureDragOffset) { latestDragGestureValue, gestureDragOffset, _ in
                gestureDragOffset = (latestDragGestureValue.translation / zoomScale)
            }
            .onEnded { finalDragGestureValue in
                for emoji in document.emojis {
                    if emoji.isSelected {
                        document.moveEmoji(emoji, by: finalDragGestureValue.translation / zoomScale)
                    }
                }
            }
    }
    
    
    private func panGesture() -> some Gesture {
        DragGesture()
            .updating($gesturePanOffset, body: { latestDragGestureValue, gesturePanOffset, _ in
                gesturePanOffset = (latestDragGestureValue.translation / zoomScale)
            })
            .onEnded { finalGragGestureValue in
                steadyStatePanOffset = steadyStatePanOffset + (finalGragGestureValue.translation / zoomScale)
            }
    }
    
    private var zoomScale: CGFloat {
        steadyStateZoomScale * gestureZoomScale
    }
    
    private func zoomGesture() -> some Gesture {
        MagnificationGesture()
            .updating($gestureZoomScale, body: { latestGestureScale, gestureZoomScale, _ in
                gestureZoomScale = latestGestureScale
            })
            .onEnded { gestureScaleAtEnd in
                steadyStateZoomScale *= gestureScaleAtEnd
            }
    }
    
    private func doubleTapToZoom(in size: CGSize) -> some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation {
                    zoomToFit(document.backgroundImage, in: size)
                }
        }
    }
    
    private func zoomToFit(_ image: UIImage?, in size: CGSize) {
        if let image = image, image.size.width > 0, image.size.height > 0, size.width > 0, size.height > 0 {
            let hZoom = size.width / image.size.width
            let vZoom = size.height / image.size.height
            steadyStatePanOffset = .zero
            steadyStateZoomScale = min(hZoom, vZoom)
        }
    }
    
    
    

}





struct EmojiArtDocumentView_Previews: PreviewProvider {
    static var previews: some View {
        EmojiArtDocumentView(document: EmojiArtDocument())
    }
}
