import Foundation

struct NowPlayingInfo: Equatable {
    let title: String
    let artist: String
    let album: String
    let isPlaying: Bool
    let position: TimeInterval
    let duration: TimeInterval
}

protocol MediaProvider: AnyObject {
    var onUpdate: ((NowPlayingInfo?) -> Void)? { get set }
    func start()
    func stop()
}//
//  MediaProvider.swift
//  MacKaraoke
//
//  Created by Manvi Yaduvanshi on 14/09/26.
//

