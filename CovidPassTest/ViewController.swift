// Developed by Ben Dodson (ben@bendodson.com)

import AVFoundation
import UIKit

class ViewController: UIViewController {
    
    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.black
        captureSession = AVCaptureSession()

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        let videoInput: AVCaptureDeviceInput

        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }

        if (captureSession.canAddInput(videoInput)) {
            captureSession.addInput(videoInput)
        } else {
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()
        guard captureSession.canAddOutput(metadataOutput) else {
            fatalError("Add error handling")
        }
        captureSession.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        metadataOutput.metadataObjectTypes = [.qr]

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        captureSession.startRunning()
    }

}

extension ViewController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        
        captureSession.stopRunning()

        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let qrCode = readableObject.stringValue else { return }
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            
            
            // THIS JSON DATA SHOULD BE FETCHED ON APP LAUNCH FROM https://covid-status.service.nhsx.nhs.uk/pubkeys/keys.json AND THEN CACHED FOR OFFLINE USAGE
            let keys = String(data: FileManager.default.contents(atPath: Bundle.main.url(forResource: "keys", withExtension: "json")!.path)!, encoding: .utf8)!
            
            do {
                let decoder = try CovidPassDecoder(keys: keys)
                let cwt = try decoder.decodeHC1(barcode: qrCode)
                
                // RETURNS A CWT OBJECT THAT GIVES ISSUING COUNTRY, EXPIRATION, ISSUED AT, AND PASS INCLUDING NAME AND DATE OF BIRTH
                print(cwt)
                
                // VALIDATE IF A PASS IS VALID AT THE CURRENT TIME
                let isValid = cwt.isValid(using: DefaultDateService())
                print("Valid Pass: \(cwt.isValid(using: DefaultDateService()))")
                
                let name = [cwt.pass.person.standardizedGivenName, cwt.pass.person.standardizedFamilyName].compactMap({$0}).joined(separator: " ")
                
                let controller = UIAlertController(title: name, message: isValid ? "Pass is valid" : "Pass is not valid", preferredStyle: .alert)
                controller.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
                    self.captureSession.startRunning()
                }))
                present(controller, animated: true, completion: nil)
                
            } catch {
                let controller = UIAlertController(title: "Error", message: "\(error)", preferredStyle: .alert)
                controller.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
                    self.captureSession.startRunning()
                }))
                present(controller, animated: true, completion: nil)
            }
        }   
    }
}
