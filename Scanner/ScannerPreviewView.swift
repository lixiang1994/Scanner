//
//  ScannerPreviewView.swift
//  Scanner
//
//  Created by 李响 on 2021/9/24.
//

import UIKit

public class ScannerPreviewView: UIView {
    private var updateContentMode: ((UIView.ContentMode) -> Void)?
    private var updateLayout: ((CGSize, CAAnimation?) -> Void)?
    
    public let subLayer: CALayer
    
    public init(_ layer: CALayer) {
        subLayer = layer
        super.init(frame: .zero)
        clipsToBounds = true
        self.layer.addSublayer(layer)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func observe(contentMode: @escaping ((UIView.ContentMode) -> Void)) {
        updateContentMode = { (mode) in
            contentMode(mode)
        }
        updateContentMode?(self.contentMode)
    }
    
    public func observe(layout: @escaping ((CGSize, CAAnimation?) -> Void)) {
        updateLayout = { (size, animation) in
            layout(size, animation)
        }
        layoutSubviews()
    }
    
    public override var contentMode: UIView.ContentMode {
        get {
            return super.contentMode
        }
        set {
            super.contentMode = newValue
            self.updateContentMode?(newValue)
        }
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        updateLayout?(bounds.size, layer.animation(forKey: "bounds.size"))
    }
}
