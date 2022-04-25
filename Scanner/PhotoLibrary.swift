//
//  PhotoLibrary.swift
//  TODOEN-IELTS-ARIES
//
//  Created by 李响 on 2021/4/1.
//

import Photos
import UIKit

enum PhotoLibrary {
    
    enum Error: Swift.Error {
        case authorization
        case unsupported
        case other(Swift.Error)
    }
}

extension PhotoLibrary {
    
    static func save(_ image: UIImage, with completion: ((Swift.Result<Void, Error>) -> Void)? = .none) {
        let data = image.pngData() ?? image.jpegData(compressionQuality: 1)
        save(data, with: completion)
    }
    
    static func save(_ data: Data?, with completion: ((Swift.Result<Void, Error>) -> Void)? = .none) {
        guard let data = data else {
            completion?(.failure(.unsupported))
            return
        }
        
        permissions { (result) in
            guard result else {
                completion?(.failure(.authorization))
                return
            }
            
            let library = PHPhotoLibrary.shared()
            
            library.performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: .none)
                
            } completionHandler: { (result, error) in
                DispatchQueue.main.async {
                    if let error = error {
                        completion?(.failure(.other(error)))
                        
                    } else {
                        completion?(.success(()))
                    }
                }
            }
        }
    }
}

private func permissions(сompletion: @escaping ((Bool) -> ())) {
    if #available(iOS 14, *) {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized:
            сompletion(true)
            
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                DispatchQueue.main.async {
                    сompletion(status == .authorized || status == .limited)
                }
            }
            
        default:
            сompletion(false)
        }
        
    } else {
        switch PHPhotoLibrary.authorizationStatus() {
        case .authorized:
            сompletion(true)
            
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { status in
                DispatchQueue.main.async {
                    сompletion(status == .authorized)
                }
            }
            
        default:
            сompletion(false)
        }
    }
}
