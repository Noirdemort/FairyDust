//
//  CircleParkingView.swift
//  Black Mist
//
//  Created by Noirdemort on 19/09/21.
//

import SwiftUI

struct CircleParkingView: View {
    
    typealias Circle = (origin: CGPoint, radius: CGFloat)
    
    var body: some View {
        GeometryReader { proxy in
            
            let frame = max(proxy.size.height, proxy.size.width)
            
            Path { path in
                setup(path: &path, frame)
            }
            .stroke(lineWidth: 2.0)
        }
        .scaledToFill()
    }
    
    private func setup(path: inout Path, _ size: CGFloat) {
        
        var circles: [Circle] = [];
        
//        let minRadius: CGFloat = 2;
//        let maxRadius: CGFloat = 100;
        let totalCircles = 500;
//        let attempts = 500;
         

        for _ in stride(from: 0, to: totalCircles, by: 1) {
            if let newCircle = circle(pool: circles,
                                      size: size) {
                circles.append(newCircle)
            }
        }
        
        for circle in circles {
            
            path.move(to: circle.origin)
            path.addArc(center: circle.origin,
                        radius: circle.radius,
                        startAngle: .init(degrees: 10),
                        endAngle: .init(degrees: 350),
                        clockwise: false)
            path.closeSubpath()
                
//            path.addRelativeArc(center: circle.origin, radius: circle.radius, startAngle: .init(degrees: 0), delta: .init(degrees: 360))
//            path.addArc(center: circle.origin,
//                        radius: circle.radius,
//                        startAngle: .zero,
//                        endAngle: .init(degrees: 360),
//                        clockwise: true)
        }
    }
    
    private func randomPoint(upto limit: CGFloat) -> CGPoint {
        let xCoordinate = (CGFloat(arc4random()) * CGFloat(arc4random())).truncatingRemainder(dividingBy: limit)
        let yCoordinate = (CGFloat(arc4random()) * CGFloat(arc4random())).truncatingRemainder(dividingBy: limit)
        return CGPoint(x: xCoordinate, y: yCoordinate)
    }
    
    private func circle(pool: [Circle], size: CGFloat, _ attempts: Int = 1000, _ minRadius: CGFloat = 2, _ maxRadius: CGFloat = 100) -> Circle? {
        
        var circleSafeToDraw = false
        
        var newCircle = Circle(origin: randomPoint(upto: size), radius: minRadius)
        
        for _ in 0..<attempts {
            
            let circle = Circle(origin: randomPoint(upto: size), radius: minRadius)
            
            if !confirmCollision(target: circle, pool: pool, size: size) {
                circleSafeToDraw = true
                newCircle = circle
                break
            }
        }
        
        if !circleSafeToDraw {
            return nil
        }
        
        for radius in stride(from: minRadius, to: maxRadius, by: 1) {
            newCircle.radius = radius
            
            if confirmCollision(target: newCircle, pool: pool, size: size) {
                newCircle.radius -= 1
                break
            }
        }
        
        return newCircle
    }
    
    private func confirmCollision(target: Circle, pool: [Circle], size: CGFloat) -> Bool {
       
        for circle in pool {
            let a = target.radius + circle.radius
            let x = target.origin.x - circle.origin.x
            let y = target.origin.y - circle.origin.y
            
            if (a >= sqrt( x * x + y * y )) {
                return true
            }
        }
        
        
        if (target.origin.x + target.radius >= size || target.origin.x - target.radius <= 0) {
            return true
        }
          
        if (target.origin.y + target.radius >= size || target.origin.y - target.radius <= 0) {
            return true
        }
        
        return false
    }
    
}

struct CircleParkingView_Previews: PreviewProvider {
    static var previews: some View {
        CircleParkingView()
    }
}
