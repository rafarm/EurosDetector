import UIKit
import AVFoundation
import Vision

public class VisionViewController: AVViewController {
    
    // UI parts
    public let previewView = PreviewView()
    public let objectsView = UIStackView()
    
    var stackView: UIStackView! {
        return self.view as! UIStackView
    }
    
    // Vision parts
    private var analysisRequest: VNRequest! = nil
    private let sequenceRequestHandler = VNSequenceRequestHandler()
    
    // Registration history
    private let maximumHistoryLength = 50
    private var transpositionHistoryPoints: [CGPoint] = [ ]
    private var previousPixelBuffer: CVPixelBuffer?
    
    // The current pixel buffer undergoing analysis. Run requests in a serial fashion, one after another.
    private var currentlyAnalyzedPixelBuffer: CVPixelBuffer?
    
    // Queue for dispatching vision object detection request
    private let visionQueue = DispatchQueue(label: "visionQueue")
    
    private var resultsShown = false
    private var analyzing = false
    
    public override func loadView() {
        view = UIStackView()
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        previewView.videoPreviewLayer.session = session
        previewView.videoPreviewLayer.videoGravity = AVLayerVideoGravity.resizeAspect
        
        stackView.spacing = 20.0
        objectsView.axis = .vertical
        
        // Head view side
        stackView.addArrangedSubview(previewView)
        
        // Tail view side
        let endStackView = UIStackView()
        endStackView.axis = .vertical
        endStackView.distribution = .equalSpacing
        endStackView.backgroundColor = UIColor.darkGray
        endStackView.layer.cornerRadius = 10.0
        endStackView.layoutMargins = UIEdgeInsets(top: 10.0, left: 10.0, bottom: 10.0, right: 10.0)
        endStackView.isLayoutMarginsRelativeArrangement = true
        let header = UILabel()
        header.text = "Detected Objects"
        endStackView.addArrangedSubview(header)
        endStackView.addArrangedSubview(objectsView)
        
        let buttonsStackView = UIStackView()
        buttonsStackView.spacing = 20.0
        
        let startBt = UIButton(type: .system)
        startBt.setTitle("Start", for: .normal)
        startBt.addTarget(self, action: #selector(toggleCapture), for: .touchUpInside)
        buttonsStackView.addArrangedSubview(startBt)
        
        let showBB = UISwitch()
        showBB.addTarget(self, action: #selector(toggleBoxVisibility), for: .valueChanged)
        buttonsStackView.addArrangedSubview(showBB)
        
        endStackView.addArrangedSubview(buttonsStackView)
        stackView.addArrangedSubview(endStackView)
    }
    
    private func performingDetection(_ detecting: Bool) {
        DispatchQueue.main.async {
            self.previewView.overlayColor(UIColor.red)
            self.previewView.animateOverlay(detecting)
        }
    } 
    
    private func showResults(identifiers ids: [String], boundingBoxes bboxes: [CGRect]) {
        // Perform all UI updates on the main queue.
        DispatchQueue.main.async(execute: {
            // Clear previous objects
            for label in self.objectsView.arrangedSubviews {
            	  self.objectsView.removeArrangedSubview(label)
                label.removeFromSuperview()
            }
            
            self.previewView.removeBoxes()
            
            // Show new data
            for id in ids {
                let label = UILabel()
                label.text = id
                self.objectsView.addArrangedSubview(label)
            }
            
            self.previewView.addBoxes(bboxes)
            
            self.previewView.animateOverlay(false)
            self.previewView.overlayColor(UIColor.green)
        })
    }
    
    /// - Tag: SetupVisionRequest
    @discardableResult
    func setupVision() -> NSError? {
        // Setup Vision parts.
        let error: NSError! = nil
        
        // Setup a detection request.
        guard let modelURL = Bundle.main.url(forResource: "EurosObjectDetectorImp", withExtension: "mlmodel") else {
            print("The model file is missing.")
            return NSError(domain: "VisionViewController", code: -1, userInfo: [NSLocalizedDescriptionKey: "The model file is missing."])
        }
        let compiledModelURL: URL
        do {
            compiledModelURL = try MLModel.compileModel(at: modelURL)
        } catch {
            print("Error compiling model")
            return NSError(domain: "VisionViewController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Error compiling model."])
        }
        guard let objectDetection = createDetectionRequest(modelURL: compiledModelURL) else {
            return NSError(domain: "VisionViewController", code: -1, userInfo: [NSLocalizedDescriptionKey: "The classification request failed."])
        }
        self.analysisRequest = objectDetection
        return error
    }
    
    private func createDetectionRequest(modelURL: URL) -> VNCoreMLRequest? {
        
        do {
            let model = try MLModel(contentsOf: modelURL)
            let objectDetector = try VNCoreMLModel(for: model)
            let detectionRequest = VNCoreMLRequest(model: objectDetector, completionHandler: { (request, error) in 
                guard let results = request.results as? [VNRecognizedObjectObservation] else {
                    return
                }
                if results.count ==  0 {
                    return
                }
                
                var ids: [String] = []
                var bboxes: [CGRect] = []
                for result in results  {
                    if result.confidence >= 0.1 {
                        guard let label = result.labels.first else {
                            continue
                        }
                        
                        if label.confidence > 0.3 {
                            ids.append(label.identifier)
                            bboxes.append(result.boundingBox)
                            
                            print("\(label.identifier)(\(label.confidence)): \(result.boundingBox)")
                        }
                    }
                }
                self.resultsShown = true
                self.showResults(identifiers: ids, boundingBoxes: bboxes)
            })
            return detectionRequest
            
        } catch let error as NSError {
            print("Model failed to load: \(error).")
            return nil
        }
    }
    
    /// - Tag: AnalyzeImage
    private func analyzeCurrentImage() {
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: currentlyAnalyzedPixelBuffer!)
        visionQueue.async {
            do {
                // Release the pixel buffer when done, allowing the next buffer to be processed.
                defer { self.currentlyAnalyzedPixelBuffer = nil }
                try requestHandler.perform([self.analysisRequest])
            } catch {
                print("Error: Vision request failed with error \"\(error)\"")
            }
        }
    }
    
    private func resetTranspositionHistory() {
        transpositionHistoryPoints.removeAll()
    }
    
    private func recordTransposition(_ point: CGPoint) {
        transpositionHistoryPoints.append(point)
        
        if transpositionHistoryPoints.count > maximumHistoryLength {
            transpositionHistoryPoints.removeFirst()
        }
    }
    /// - Tag: CheckSceneStability
    private func sceneStabilityAchieved() -> Bool {
        // Determine if we have enough evidence of stability.
        if transpositionHistoryPoints.count == maximumHistoryLength {
            // Calculate the moving average.
            var movingAverage: CGPoint = CGPoint.zero
            for currentPoint in transpositionHistoryPoints {
                movingAverage.x += currentPoint.x
                movingAverage.y += currentPoint.y
            }
            let distance = abs(movingAverage.x) + abs(movingAverage.y)
            if distance < 30 {
                return true
            }
        }
        return false
    }
    public override func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        guard previousPixelBuffer != nil else {
            previousPixelBuffer = pixelBuffer
            self.resetTranspositionHistory()
            return
        }
        
        let registrationRequest = VNTranslationalImageRegistrationRequest(targetedCVPixelBuffer: pixelBuffer)
        do {
            try sequenceRequestHandler.perform([ registrationRequest ], on: previousPixelBuffer!)
        } catch let error as NSError {
            print("Failed to process request: \(error.localizedDescription).")
            return
        }
        
        previousPixelBuffer = pixelBuffer
        
        if let results = registrationRequest.results {
            if let alignmentObservation = results.first as? VNImageTranslationAlignmentObservation {
                let alignmentTransform = alignmentObservation.alignmentTransform
                self.recordTransposition(CGPoint(x: alignmentTransform.tx, y: alignmentTransform.ty))
            }
        }
        if self.sceneStabilityAchieved() {
            // Don't analyze frames if results are already found
            if resultsShown {
                return
            }
            
            if currentlyAnalyzedPixelBuffer == nil {
                // Retain the image buffer for Vision processing.
                currentlyAnalyzedPixelBuffer = pixelBuffer
                analyzeCurrentImage()
            }
            
            if !analyzing {
                performingDetection(true)
                analyzing = true
            }
        } else {
            // Clear UI
            if resultsShown {
                resultsShown = false
                showResults(identifiers: [], boundingBoxes: [])
            }
            
            if analyzing {
                performingDetection(false)
                analyzing = false
            }
        }
    }
    
    override func setupAVCapture() {
        super.setupAVCapture()
        
        // setup Vision parts
        setupVision()
        
        // start the capture
        session.startRunning()
    }
    
    @objc func toggleCapture(sender: UIButton) {
        let captureConnection = session.connections.first!
        
        if captureConnection.isEnabled {
            captureConnection.isEnabled = false
            showResults(identifiers: [], boundingBoxes: [])
            previewView.hiddenOverlay(true)
            sender.setTitle("Start", for: .normal)
            resultsShown = false
        } else {
            previewView.overlayColor(UIColor.red)
            previewView.animateOverlay(false)
            previewView.hiddenOverlay(false)
            sender.setTitle("Stop", for: .normal)
            captureConnection.isEnabled = true
        }
    }
    
    @objc func toggleBoxVisibility(_ sender: UISwitch) {
        previewView.hiddenBoxes(!sender.isOn)
    }
}

