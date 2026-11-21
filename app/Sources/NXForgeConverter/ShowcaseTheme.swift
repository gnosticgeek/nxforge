// Theatre's Showcase theme: the Carousel, the Fan and the Shelf as one theme with three layouts (ShowcaseLayout). Switching layout keeps
// the game in focus, the filter and the music; only the boxes rearrange.
import SwiftUI

struct ShowcaseTheme: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack {
            switch model.showcaseLayout {
            case .carousel: CarouselTheme(model: model).transition(.opacity)
            case .fan: FanTheme(model: model).transition(.opacity)
            case .shelf: ShelfTheme(model: model).transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: model.showcaseLayout)
    }
}
