//
//  ContentView.swift
//  Black Mist
//
//  Created by Noirdemort on 19/09/21.
//

import SwiftUI

struct ContentView: View {
    
    var body: some View {
    
        GeometryReader { proxy in
            
            let frame = max(proxy.size.height, proxy.size.width)
            
            Path { path in
                setup(path: &path, frame)
            }
            .stroke(lineWidth: 2.0)
        }
    }
    
    private func setup(path: inout Path, _ size: CGFloat) {
        let step: CGFloat = 20
        for x in stride(from: 0, to: size, by: step) {
          for y in stride(from: 0, to: size, by: step) {
            draw(path: &path, x, y, step, step)
          }
        }
    }
    
    private func draw(path: inout Path, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
        let leftToRight = arc4random()%2 == 0

          if leftToRight {
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + width, y: y + height))
          } else {
            path.move(to: CGPoint(x: x + width, y: y))
            path.addLine(to: CGPoint(x: x, y: y + height))
          }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
