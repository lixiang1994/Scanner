//
//  Scanner.swift
//  Scanner
//
//  Created by 李响 on 2021/9/24.
//

import Foundation
import UIKit
import AVFoundation
import Vision

public class Scanner {
        
    public struct Result: Hashable {
        let type: String
        let content: String
        
        let snapshot: UIImage
        let bounding: CGRect
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(type)
            hasher.combine(content)
        }
    }
    
    public enum Error: Swift.Error {
        case device
        case other(Swift.Error)
    }
    
    public typealias ResultsHandler = ([Scanner.Result]) -> (Bool)
    
    /// 预览视图
    public let preview: ScannerPreviewView
    
    let device = AVCaptureDevice.default(
        .builtInWideAngleCamera,
        for: .video,
        position: .back
    ) ?? .default(for: .video)

    private let delegate: ScannerDelegate
    
    public init(_ handler: @escaping Scanner.ResultsHandler) throws {
        guard let device = self.device else {
            throw Scanner.Error.device
        }
        // 基于Vision无法实现自然的自动缩放焦距效果 但Vision可以实现物体追踪等特性
        //delegate = try ScannerVisionDelegate(device, with: handler)
        delegate = try ScannerMetadataDelegate(device, with: handler)
        
        // 构建预览视图
        let layer = AVCaptureVideoPreviewLayer(session: delegate.session)
        preview = ScannerPreviewView(layer)
        preview.observe { (size, animation) in
            if let animation = animation {
                CATransaction.begin()
                CATransaction.setAnimationDuration(animation.duration)
                CATransaction.setAnimationTimingFunction(animation.timingFunction)
                layer.frame = .init(origin: .zero, size: size)
                CATransaction.commit()
                
            } else {
                layer.frame = .init(origin: .zero, size: size)
            }
        }
        preview.observe { (contentMode) in
            switch contentMode {
            case .scaleToFill:
                layer.videoGravity = .resize
                
            case .scaleAspectFit:
                layer.videoGravity = .resizeAspect
                
            case .scaleAspectFill:
                layer.videoGravity = .resizeAspectFill
                
            default:
                layer.videoGravity = .resizeAspectFill
            }
        }
        preview.contentMode = .scaleAspectFit
    }
}

public extension Scanner {
    
    /// 手电筒是否激活
    var isTorchActive: Bool {
        get {
            guard let device = self.device else { return false }
            return device.hasTorch && device.isTorchActive
        }
        set {
            guard let device = self.device else { return }
            guard device.hasTorch else { return }
            try? device.lockForConfiguration()
            try? device.setTorchModeOn(level: 1.0)
            device.torchMode = !device.isTorchActive ? .on : .off
            device.unlockForConfiguration()
        }
    }
    
    /// 是否预览中
    var isPreviewing: Bool {
        delegate.session.isRunning
    }
    
    /// 是否扫描中
    var isScanning: Bool {
        get { delegate.isScanning }
        set { delegate.isScanning = newValue }
    }
    
    /// 预览视频缩放
    var videoZoomFactor: CGFloat {
        get { device?.videoZoomFactor ?? 1.0 }
    }
    
    /// 开始预览
    func start() {
        delegate.start()
    }
    
    /// 结束预览
    func stop() {
        delegate.stop()
    }
    
    /// 设置预览视频缩放
    /// - Parameters:
    ///   - value: 缩放倍数 范围以设备最大支持倍数为准
    ///   - animated: 过渡动画
    func setVideoZoomFactor(_ value: CGFloat, animated: Bool = true) {
        guard let device = self.device else { return }
        let maximum = device.maxAvailableVideoZoomFactor
        let minimum = device.minAvailableVideoZoomFactor
        do {
            try device.lockForConfiguration()
            if animated {
                device.ramp(toVideoZoomFactor: min(max(value, minimum), maximum), withRate: 10)
                
            } else {
                device.videoZoomFactor = min(max(value, minimum), maximum)
            }
            device.unlockForConfiguration()
            
        } catch {
            print(error)
        }
    }
    
    func cancelVideoZoom() {
        guard let device = self.device else { return }
        do {
            try device.lockForConfiguration()
            device.cancelVideoZoomRamp()
            device.unlockForConfiguration()
            
        } catch {
            print(error)
        }
    }
    
    /// 设置焦点
    /// - Parameter point: 位置 0 - 1
    func setFocus(at point: CGPoint) {
        guard let device = self.device else { return }
        do {
            try device.lockForConfiguration()
            // 转换坐标系
            let temp = CGPoint(x: point.y, y: 1 - point.x)
            // 设置平滑对焦
            if device.isSmoothAutoFocusSupported {
                device.isSmoothAutoFocusEnabled = true
            }
            // 设置焦点位置
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = temp
            }
            // 设置焦点模式
            if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
            }
            device.unlockForConfiguration()
            
        } catch {
            print(error)
        }
    }
    
    /// 设置曝光
    /// - Parameter point: 位置 0 - 1
    func setExposure(at point: CGPoint) {
        guard let device = self.device else { return }
        do {
            try device.lockForConfiguration()
            // 转换坐标系
            let temp = CGPoint(x: point.y, y: 1 - point.x)
            // 设置曝光位置
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = temp
            }
            // 设置曝光模式
            if device.isExposureModeSupported(.autoExpose) {
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
            
        } catch {
            print(error)
        }
    }
}

fileprivate protocol ScannerDelegate: NSObjectProtocol {
    
    var session: AVCaptureSession { get }
    
    var isScanning: Bool { get set }
    
    func start()
    
    func stop()
    
    init (_ device: AVCaptureDevice, with handler: @escaping Scanner.ResultsHandler) throws
}

fileprivate class ScannerMetadataDelegate: NSObject, ScannerDelegate {
    
    let session = AVCaptureSession()
    
    private let device: AVCaptureDevice
    private let input: AVCaptureDeviceInput
    private let output = AVCaptureMetadataOutput()
    private let photo = AVCapturePhotoOutput()
    
    private let handler: Scanner.ResultsHandler
    
    var isScanning: Bool = false
    
    private var objects: [AVMetadataMachineReadableCodeObject] = []
    
    required init (_ device: AVCaptureDevice, with handler: @escaping Scanner.ResultsHandler) throws {
        self.device = device
        self.handler = handler
        self.input = try AVCaptureDeviceInput(device: device)
        super.init()
        
        if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }
        
        if session.canAddInput(input) {
            session.addInput(input)
        }
        
        if session.canAddOutput(output) {
            session.addOutput(output)
            if let connection = output.connection(with: .video) {
                // 视频方向
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                // 视频稳定
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
            }
        }

        if session.canAddOutput(photo) {
            session.addOutput(photo)
            if let connection = photo.connection(with: .video) {
                // 视频方向
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                // 视频稳定
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
            }
        }

        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [
            .upce, .code39, .code39Mod43, .ean13, .ean8, .code93, .code128, .pdf417, .qr, .aztec,
            .interleaved2of5, .itf14, .dataMatrix
        ]
    }
    
    func start() {
        session.startRunning()
    }
    
    func stop() {
        session.stopRunning()
    }
    
    private func process(_ snapshot: UIImage) {
        let temp: Set<Scanner.Result> = .init(objects.map {
            print($0.bounds)
            print($0.corners)
            // 坐标系需要-90旋转
            return .init(
                type: $0.type.rawValue,
                content: $0.stringValue ?? "",
                snapshot: snapshot,
                bounding: .init(
                    x: 1 - $0.bounds.origin.y - $0.bounds.height,
                    y: $0.bounds.origin.x,
                    width: $0.bounds.height,
                    height: $0.bounds.width
                )
            )
        })
        guard !temp.isEmpty else { return }
        isScanning = handler(.init(temp))
    }
}

extension ScannerMetadataDelegate: AVCapturePhotoCaptureDelegate {

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        defer { objects.removeAll() }
        guard error == nil else { return }
        guard let data = photo.fileDataRepresentation() else { return }
        process(.init(data: data, scale: 1.0)?.rotated(by: .init(value: 0, unit: .degrees)) ?? .init())
    }
}

extension ScannerMetadataDelegate: AVCaptureMetadataOutputObjectsDelegate {
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        // 未开启扫描不进行处理
        guard isScanning else { return }
        // 设备缩放中不进行处理
        guard !device.isRampingVideoZoom else { return }
        // 已存在记录不进行处理
        guard objects.isEmpty else { return }
        // 保持记录
        objects = metadataObjects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject })
        // 拍摄快照
        photo.capturePhoto(with: .init(), delegate: self)
    }
}

fileprivate class ScannerVisionDelegate: NSObject, ScannerDelegate {
    
    let queue = DispatchQueue(label: "com.capture.video.output")
    let session = AVCaptureSession()
    
    private let device: AVCaptureDevice
    private let input: AVCaptureDeviceInput
    private let output = AVCaptureVideoDataOutput()
    private let handler: Scanner.ResultsHandler
    
    var isScanning: Bool = false
    
    required init (_ device: AVCaptureDevice, with handler: @escaping Scanner.ResultsHandler) throws {
        self.device = device
        self.handler = handler
        self.input = try AVCaptureDeviceInput(device: device)
        super.init()
        
        if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }
        
        if session.canAddInput(input) {
            session.addInput(input)
        }
        
        if session.canAddOutput(output) {
            session.addOutput(output)
            if let connection = output.connection(with: .video) {
                // 视频方向
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                // 视频稳定
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
            }
        }
        
        output.setSampleBufferDelegate(self, queue: queue)
        //注意CVPixelBufferCreate函数不支持 kCVPixelFormatType_32RGBA 等格式 不知道为什么。
        //支持kCVPixelFormatType_32ARGB和kCVPixelFormatType_32BGRA等 iPhone为小端对齐因此kCVPixelFormatType_32ARGB和kCVPixelFormatType_32BGRA都需要和kCGBitmapByteOrder32Little配合使用
        //注意当inputPixelFormat为kCVPixelFormatType_32BGRA时bitmapInfo不能是kCGImageAlphaNone，kCGImageAlphaLast，kCGImageAlphaFirst，kCGImageAlphaOnly。
        //注意iPhone的大小端对齐方式为小段对齐 可以使用宏 kCGBitmapByteOrder32Host 来解决大小端对齐 大小端对齐必须设置为kCGBitmapByteOrder32Little。
        output.videoSettings = [.init(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA]
    }
    
    func start() {
        session.startRunning()
    }
    
    func stop() {
        session.stopRunning()
    }
    
    private func process(_ results: [VNObservation], snapshot: UIImage) {
        let temp: Set<Scanner.Result> = .init(results.compactMap {
            guard
                let result = $0 as? VNBarcodeObservation,
                let value = result.payloadStringValue else {
                return .none
            }
            return .init(
                type: result.symbology.rawValue,
                content: value,
                snapshot: snapshot,
                bounding: result.boundingBox
            )
        })
        guard !temp.isEmpty else { return }
        DispatchQueue.main.sync {
            self.isScanning = handler(.init(temp))
        }
    }
}

extension ScannerVisionDelegate: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isScanning else { return }
        guard !device.isRampingVideoZoom else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up
        )
        
        do {
            let request = VNDetectBarcodesRequest { request, error in
                guard error == nil else { return }
                guard let results = request.results, !results.isEmpty else { return }
                // 处理结果
                self.process(results, snapshot: sampleBuffer.asUIImage() ?? .init())
            }
            //request.preferBackgroundProcessing = true
            try handler.perform([request])
            
        } catch {
            print(error)
        }
    }
}

extension Scanner {
    
    /// 单图扫描
    /// - Parameter image: 图像
    /// - Returns: 扫描结果
    static func single(image: UIImage) -> [Scanner.Result]? {
        guard let temp = image.cgImage else {
            return .none
        }
        
        func process(_ results: [VNObservation]?) -> [Scanner.Result]? {
            return results?.compactMap {
                guard
                    let result = $0 as? VNBarcodeObservation,
                    let value = result.payloadStringValue else {
                    return .none
                }
                return .init(
                    type: result.symbology.rawValue,
                    content: value,
                    snapshot: image,
                    bounding: result.boundingBox
                )
            }
        }
        
        var results: [Scanner.Result]?
        
        lazy var request = VNDetectBarcodesRequest { request, error in
            guard error == nil else { return }
            results = process(request.results)
        }
        
        let handler = VNImageRequestHandler(
            cgImage: temp,
            orientation: .up
        )
        
        try? handler.perform([request])
        
        return results
    }
}

fileprivate extension CMSampleBuffer {
    
    func asUIImage() -> UIImage? {
        guard let buffer = CMSampleBufferGetImageBuffer(self) else { return .none }
        CVPixelBufferLockBaseAddress(buffer, .init(rawValue: 0))
        
        //CGBitmapInfo的设置
        //uint32_t bitmapInfo = CGImageAlphaInfo | CGBitmapInfo;
        
        //当kCVPixelFormatType_32BGRA CGBitmapInfo的正确的设置
        //uint32_t bitmapInfo = kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host;
        //uint32_t bitmapInfo = kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Host;
        
        //当kCVPixelFormatType_32ARGB CGBitmapInfo的正确的设置
        //uint32_t bitmapInfo = kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Big;
        
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        defer { CVPixelBufferUnlockBaseAddress(buffer, .init(rawValue: 0)) }
        guard let image = context?.makeImage() else { return .none }
        return .init(cgImage: image, scale: 1.0, orientation: .up)
    }
}

fileprivate extension UIImage {
    
    func rotated(by angle: Measurement<UnitAngle>) -> UIImage? {
        let radians = CGFloat(angle.converted(to: .radians).value)

        let destRect = CGRect(origin: .zero, size: size)
            .applying(CGAffineTransform(rotationAngle: radians))
        let roundedDestRect = CGRect(x: destRect.origin.x.rounded(),
                                     y: destRect.origin.y.rounded(),
                                     width: destRect.width.rounded(),
                                     height: destRect.height.rounded())

        UIGraphicsBeginImageContext(roundedDestRect.size)
        guard let contextRef = UIGraphicsGetCurrentContext() else { return nil }

        contextRef.translateBy(x: roundedDestRect.width / 2, y: roundedDestRect.height / 2)
        contextRef.rotate(by: radians)

        draw(in: .init(origin: .init(x: -size.width / 2, y: -size.height / 2), size: size))

        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage
    }
    
    func asCVPixelBuffer() -> CVPixelBuffer? {
        guard let image = cgImage else { return .none }
        
        let options = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            .init(size.width),
            .init(size.height),
            kCVPixelFormatType_32BGRA,
            options as CFDictionary,
            &buffer
        )
        guard let buffer = buffer, status == kCVReturnSuccess else { return .none }
        
        CVPixelBufferLockBaseAddress(buffer, .init(rawValue: 0))
        
        guard let data = CVPixelBufferGetBaseAddress(buffer) else { return .none }
        
        let context = CGContext(
            data: data,
            width: .init(size.width),
            height: .init(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        context?.concatenate(.identity)
        context?.draw(image, in: .init(origin: .zero, size: size))
        
        CVPixelBufferUnlockBaseAddress(buffer, .init(rawValue: 0))
        
        return buffer
    }
}
