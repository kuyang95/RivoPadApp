//
//  ImageUtil.swift
//  shortcuts_example
//
//  Created by me on 3/10/26.
//

import UIKit

final class ImageLoader {

    static let shared = ImageLoader()

    private init() {}

    func loadImage(from url: URL, completion: @escaping (UIImage?) -> Void) {

        URLSession.shared.dataTask(with: url) { data, response, error in

            guard let data = data,
                  let image = UIImage(data: data),
                  error == nil else {

                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            DispatchQueue.main.async {
                completion(image)
            }

        }.resume()
    }
}
