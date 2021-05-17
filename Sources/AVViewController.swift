import UIKit
import AVFoundation

public class AVViewController : UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    public let session = AVCaptureSession()
    private var captureConnection: AVCaptureConnection! = nil
    private let videoDataOutput = AVCaptureVideoDataOutput()
    
    private let videoDataOutputQueue = DispatchQueue(label: "VideoDataOutput", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupAVCapture()
    }
    
    func setupAVCapture() {
        var deviceInput: AVCaptureDeviceInput!
        
        // Select a video device and make an input.
        let videoDevice = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .back).devices.first
        do {
            deviceInput = try AVCaptureDeviceInput(device: videoDevice!)
        } catch {
            print("Could not create video device input: \(error).")
            return
        }
        
        session.beginConfiguration()
        
        // The model input size is smaller than 640x480, so better resolution won't help us.
        session.sessionPreset = .vga640x480
        
        // Add a video input.
        guard session.canAddInput(deviceInput) else {
            print("Could not add video device input to the session.")
            session.commitConfiguration()
            return
        }
        session.addInput(deviceInput)
        
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
            // Add a video data output.
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]
            videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        } else {
            print("Could not add video data output to the session.")
            session.commitConfiguration()
            return
        }
        captureConnection = videoDataOutput.connection(with: .video)
        
        // Always process the frames.
        captureConnection.isEnabled = false
        
        session.commitConfiguration()
    }
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    // Implement this in the subclass.
    }
    
    public func captureOutput(_ captureOutput: AVCaptureOutput, didDrop didDropSampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        print("The capture output dropped a frame.")
    }
}
