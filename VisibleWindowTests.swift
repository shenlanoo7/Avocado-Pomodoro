import Foundation
import CoreGraphics
@main struct VisibleWindowTests {
    static func main() {
        let screen = CGRect(x:0,y:0,width:1440,height:900)
        for x in [-900.0,-100,0,10,1193,1340,2500] {
            let original = CGRect(x:x,y:-20,width:247,height:377)
            let visible = VisibleWindow.frame(original,screens:[screen])
            precondition(screen.contains(visible),"entire timer must stay visible")
            precondition(visible.size == original.size,"clamping must not resize")
        }
        let left = CGRect(x:-1440,y:0,width:1440,height:900)
        let frame = CGRect(x:-1400,y:100,width:247,height:377)
        precondition(VisibleWindow.frame(frame,screens:[screen,left]) == frame)
        precondition(VisibleWindow.frame(frame,screens:[]) == frame)
        print("PASS visible boundary clamp, unchanged size, multiple screens, no screens")
    }
}
