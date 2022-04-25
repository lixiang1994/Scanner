//
//  ViewController.swift
//  Scanner
//
//  Created by 李响 on 2021/9/24.
//

import UIKit
import PhotosUI

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }

    @IBAction func photoAction(_ sender: UIButton) {
        if #available(iOS 14, *) {
            var config = PHPickerConfiguration()
            config.filter = .images
            config.selectionLimit = 1
            
            let controller = PHPickerViewController(configuration: config)
            controller.delegate = self
            present(controller, animated: true)
            
        } else {
            // Fallback on earlier versions
        }
    }
}

@available(iOS 14, *)
extension ViewController: PHPickerViewControllerDelegate {
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true) {
            results.first?.itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                guard let photo = object as? UIImage, error == nil else { return }
                
                DispatchQueue.main.async {
                    print(Scanner.single(image: photo))
                }
            }
        }
    }
}
