import UIKit
import CoreData

enum ImageResult {
    case Success(UIImage)
    case Failure(Error)
}

enum PhotoError: Error {
    case ImageCreationError
}

class PhotoStore {
    let coreDateStack = CoreDataStack(modelName: "Photorama")
    
    let session: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config)
    }()
    
    func fetchRecentPhotos(completion: @escaping (PhotosResult) -> Void) {
        let url = FlickrAPI.recentPhotosURL()
        let request = URLRequest(url: url)
        let task = session.dataTask(with: request) {
            (data, response, error) -> Void in
            
            var result = self.processPhotosRequest(data: data, error: error)
            if case let .Success(photos) = result {
                let mainQueueContext = self.coreDateStack.mainQueueContext
                mainQueueContext.performAndWait {
                    try! mainQueueContext.obtainPermanentIDs(for: photos)
                }
                let objectIDs = photos.map{ $0.objectID }
                let predicate = NSPredicate(format: "self IN %@", objectIDs)
                let sortByDateTaken = NSSortDescriptor(key: "dateTaken", ascending: true)
                
                do {
                    try self.coreDateStack.saveChanges()
                    
                    let mainQueuePhotos = try self.fetchMainQueuePhotos(predicate: predicate, sortDescriptors: [sortByDateTaken])
                    result = .Success(mainQueuePhotos)
                } catch let error {
                    result = .Failure(error)
                }
            }
            completion(result)
        }
        task.resume()
    }
    
    func processPhotosRequest(data: Data?, error: Error?) -> PhotosResult {
        guard let jsonData = data else {
            return .Failure(error!)
        }
        
        return FlickrAPI.photosFromJSONData(data: jsonData, inContext: self.coreDateStack.mainQueueContext)
    }

    func fetchImageForPhoto(photo: Photo, completion: @escaping (ImageResult) -> Void) {
        if  let image = photo.image {
            completion(.Success(image))
            return
        }

        let photoURL = photo.remoteURL
        let request = URLRequest(url: photoURL)
        
        let task = session.dataTask(with: request) {
            (data, response, error) -> Void in
            
            let result = self.processImageRequest(data: data, error: error)
            
            if case let .Success(image) = result {
                photo.image = image
            }
            
            completion(result)
        }
        task.resume()
    }
    
    func processImageRequest(data: Data?, error: Error?) -> ImageResult {
        guard let
            imageData = data,
            let image = UIImage(data: imageData) else {
                
                // Coudn't create an image
                if data == nil {
                    return .Failure(error!)
                } else {
                    return .Failure(PhotoError.ImageCreationError)
                }
        }
        
        return .Success(image)
    }
    
    func fetchMainQueuePhotos(predicate: NSPredicate? = nil,
                              sortDescriptors: [NSSortDescriptor]? = nil) throws -> [Photo] {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Photo")
        fetchRequest.sortDescriptors = sortDescriptors
        fetchRequest.predicate = predicate
        
        let mainQueueContext = self.coreDateStack.mainQueueContext
        var mainQueuePhotos: [Photo]?
        var fetchRequestError: Error?
        mainQueueContext.performAndWait {
            do {
                mainQueuePhotos = try mainQueueContext.fetch(fetchRequest) as? [Photo]
            } catch let error{
                fetchRequestError = error
            }
        }
        
        guard let photos = mainQueuePhotos else {
            throw fetchRequestError!
        }
        
        return photos
    }
}
