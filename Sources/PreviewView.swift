import UIKit
import AVFoundation

public class PreviewView: UIView {
    
    private let ANIMATION_KEY = "pulse"
    private let overlay = CALayer()
    private var boxLayers: [CALayer] = []
    private var hideBoxes = true
    
    public override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        return self.layer as! AVCaptureVideoPreviewLayer
    }
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        
        overlay.borderWidth = 2.0
        overlay.borderColor = UIColor.red.cgColor
        overlay.cornerRadius = 20.0
        overlay.isHidden = true
        
        layer.addSublayer(overlay)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func addBoxes(_ bboxes: [CGRect]) {
        for box in bboxes {
            let bLayer = CALayer()
            bLayer.borderWidth = 2.0
            bLayer.borderColor = UIColor.white.cgColor
            bLayer.frame = videoPreviewLayer.layerRectConverted(fromMetadataOutputRect: box)
            bLayer.isHidden = hideBoxes
            layer.addSublayer(bLayer)
            boxLayers.append(bLayer)
        }
    }
    
    public func removeBoxes() {
        for box in boxLayers {
            box.removeFromSuperlayer()
        }
    }
    
    public func hiddenBoxes(_ hidden: Bool) {
        hideBoxes = hidden
        
        for box in boxLayers {
            box.isHidden = hideBoxes
        }
    }
    
    public func animateOverlay(_ animate: Bool) {
        if animate && overlay.animation(forKey: ANIMATION_KEY) == nil {
            let grow = CABasicAnimation(keyPath: ("transform.scale"))
            grow.fromValue = CGPoint(x: 1.0, y: 1.0)
            grow.toValue = CGPoint(x: 1.05, y: 1.05)
            grow.autoreverses = true
            grow.duration = 0.2
            grow.repeatCount = .infinity
            
            overlay.add(grow, forKey: ANIMATION_KEY)
        } else {
            overlay.removeAnimation(forKey: ANIMATION_KEY)
        }
    }
    
    public func hiddenOverlay(_ hidden: Bool) {
        animateOverlay(false)
        overlay.isHidden = hidden
    }
    
    public func overlayColor(_ color: UIColor) {
        overlay.borderColor = color.cgColor
    }
    
    
    public override func layoutSubviews() {
        overlay.frame = videoPreviewLayer.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0)).insetBy(dx: 20.0, dy: 20.0)
    }
}

