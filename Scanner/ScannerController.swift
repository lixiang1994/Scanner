//
//  SannerController.swift
//  Scanner
//
//  Created by 李响 on 2021/9/24.
//

import Foundation
import UIKit
import AVFoundation
import Photos

class ScannerController: UIViewController {
    
    @IBOutlet weak var scanningButton: UIButton!
    
    private var scanner: Scanner?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setup()
        
        permissions { [weak self] result in
            guard let self = self else { return }
            switch result {
            case true:
                self.setupScanner()
                
            case false:
                print("无权限")
            }
        }
    }
    
    private func setup() {
        scanningButton.setTitle("Start Scanning", for: .normal)
        scanningButton.setTitle("Stop Scanning", for: .selected)
    }
    
    private func setupScanner() {
        do {
            let scanner = try Scanner { [weak self] results in
                guard let self = self else { return false }
                guard let scanner = self.scanner else { return false }
                guard let result = results.first else { return false }
                
                // 扫描到结果后 如果目标宽度小于0.25, 放大一倍
                if result.bounding.width < 0.25 {
                    scanner.setVideoZoomFactor(scanner.videoZoomFactor + 1)
                    // 返回继续扫描
                    return true
                }
                // 取消缩放
                scanner.cancelVideoZoom()
                
                print(result)
                
                // 添加调试目标的范围框
                let size = scanner.preview.frame.size
                let w = result.bounding.width * size.width
                let h = result.bounding.height * size.height
                let x = result.bounding.origin.x * size.width
                let y = result.bounding.origin.y * size.height
                
                print(CGRect(x: x, y: y, width: w, height: h))
                
                scanner.preview.subviews.forEach({ $0.removeFromSuperview() })
                let view = UIView(frame: .init(x: x, y: y, width: w, height: h))
                view.backgroundColor = UIColor.red.withAlphaComponent(0.3)
                scanner.preview.addSubview(view)
                
                // 将扫描结果的快照存入相册 方便查看
                PhotoLibrary.save(result.snapshot)
                
                // 重置状态
                func reset() {
                    self.scanningButton.isSelected = false
                    scanner.setVideoZoomFactor(1.0, animated: false)
                }
                
                // 显示扫描结果内容
                let controller = UIAlertController(title: "Result", message: result.content, preferredStyle: .alert)
                if
                    let url = URL(string: result.content),
                    let scheme = url.scheme,
                    scheme.hasPrefix("http") {
                    controller.addAction(
                        .init(title: "Open", style: .default, handler: { action in
                            UIApplication.shared.open(url, options: [:])
                            reset()
                        })
                    )
                }
                controller.addAction(
                    .init(title: "Close", style: .cancel, handler: { action in
                        reset()
                    })
                )
                self.present(controller, animated: true)
                
                
                // 返回不继续扫描
                return false
            }
            self.scanner = scanner
            // 预览视图
            let preview = scanner.preview
            preview.contentMode = .scaleAspectFill
            self.view.insertSubview(preview, at: 0)
            preview.frame = view.bounds
            preview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            // 单击手势
            let singleTap = UITapGestureRecognizer(target: self, action: #selector(singleTapAction))
            singleTap.numberOfTapsRequired = 1
            preview.addGestureRecognizer(singleTap)
            // 双击手势
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapAction))
            doubleTap.numberOfTapsRequired = 2
            preview.addGestureRecognizer(doubleTap)
            // 开始预览
            scanner.start()
            
        } catch {
            print(error)
        }
    }
    
    @objc
    private func singleTapAction(_ gesture: UITapGestureRecognizer) {
        guard let view = gesture.view else { return }
        guard let scanner = scanner else { return }
        let point = gesture.location(in: view)
        scanner.setFocus(at: .init(x: point.x / view.frame.width, y: point.y / view.frame.height))
    }
    
    @objc
    private func doubleTapAction() {
        guard let scanner = scanner else { return }
        scanner.setVideoZoomFactor(scanner.videoZoomFactor > 1 ? 1 : 2)
    }
    
    @IBAction func scanningAction(_ sender: UIButton) {
        sender.isSelected.toggle()
        scanner?.isScanning = sender.isSelected
        scanner?.preview.subviews.forEach({ $0.removeFromSuperview() })
    }
    
    @IBAction func torchAction(_ sender: UIBarButtonItem) {
        scanner?.isTorchActive.toggle()
    }
}

extension ScannerController {
    
    public func permissions(сompletion: @escaping ((Bool) -> ())) {
        // 相机权限
        capturePermissions { result in
            сompletion(result)
        }
    }
    
    private func capturePermissions(сompletion: @escaping ((Bool) -> ())) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            сompletion(true)
            
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { result in
                DispatchQueue.main.async {
                    сompletion(result)
                }
            }
            
        default:
            сompletion(false)
        }
    }
}
