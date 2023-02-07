//
//  Post.swift
//  damus
//
//  Created by William Casarin on 2022-04-03.
//

import SwiftUI
import PhotosUI

enum NostrPostResult {
    case post(NostrPost)
    case cancel
}

let POST_PLACEHOLDER = NSLocalizedString("Type your post here...", comment: "Text box prompt to ask user to type their post.")

struct PostView: View {
    @State var post: String = ""
    @FocusState var focus: Bool
    @State var showPrivateKeyWarning: Bool = false
    @State var selectedItem: PhotosPickerItem? = nil
    
    let replying_to: NostrEvent?
    let references: [ReferencedId]
    let damus_state: DamusState

    @Environment(\.presentationMode) var presentationMode

    enum FocusField: Hashable {
      case post
    }

    func cancel() {
        NotificationCenter.default.post(name: .post, object: NostrPostResult.cancel)
        dismiss()
    }

    func dismiss() {
        self.presentationMode.wrappedValue.dismiss()
    }

    func send_post() {
        var kind: NostrKind = .text
        if replying_to?.known_kind == .chat {
            kind = .chat
        }
        let content = self.post.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let new_post = NostrPost(content: content, references: references, kind: kind)

        NotificationCenter.default.post(name: .post, object: NostrPostResult.post(new_post))
        dismiss()
    }

    var is_post_empty: Bool {
        return post.allSatisfy { $0.isWhitespace }
    }

    var body: some View {
        VStack {
            HStack {
                Button(NSLocalizedString("Cancel", comment: "Button to cancel out of posting a note.")) {
                    self.cancel()
                }
                .foregroundColor(.primary)

                Spacer()

                PhotosPicker(selection: $selectedItem, photoLibrary: .shared()) {
                    Image(systemName: "photo")
                }

                Spacer()
                
                Button(NSLocalizedString("Post", comment: "Button to post a note.")) {
                    showPrivateKeyWarning = contentContainsPrivateKey(self.post)

                    if !showPrivateKeyWarning {
                        self.send_post()
                    }
                }
                .disabled(is_post_empty)
            }
            .padding([.top, .bottom], 4)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $post)
                    .focused($focus)
                    .textInputAutocapitalization(.sentences)

                if post.isEmpty {
                    Text(POST_PLACEHOLDER)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .foregroundColor(Color(uiColor: .placeholderText))
                        .allowsHitTesting(false)
                }
            }

            // This if-block observes @ for tagging
            if let searching = get_searching_string(post) {
                VStack {
                    Spacer()
                    UserSearch(damus_state: damus_state, search: searching, post: $post)
                }.zIndex(1)
            }
        }
        .padding()
        .onAppear() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.focus = true
            }
        }
        .task(id: selectedItem) {
            guard let newItem = selectedItem else { return }
            guard let type = newItem.supportedContentTypes.first else { return }
            guard let mimeType = type.preferredMIMEType else { return }
            guard let fileExtension = type.preferredFilenameExtension else { return }

            guard let imageData = try? await newItem.loadTransferable(type: Data.self) else {
                print("No supported content type found.")
                return
            }
            
            let uploadingText = "[uploading...]"
            do {
                post += "\n\(uploadingText)"
                
                let urlString = try await uploadImage(mimeType: mimeType, fileExtension: fileExtension, imageData: imageData)
                
                post = post.replacingOccurrences(of: uploadingText, with: urlString)
            } catch {
                print(error) // TODO: Show alert
                post = post.replacingOccurrences(of: "\n\(uploadingText)", with: "")
            }
        }
        .alert(NSLocalizedString("Note contains \"nsec1\" private key. Are you sure?", comment: "Alert user that they might be attempting to paste a private key and ask them to confirm."), isPresented: $showPrivateKeyWarning, actions: {
            Button(NSLocalizedString("No", comment: "Button to cancel out of posting a note after being alerted that it looks like they might be posting a private key."), role: .cancel) {
                showPrivateKeyWarning = false
            }
            Button(NSLocalizedString("Yes, Post with Private Key", comment: "Button to proceed with posting a note even though it looks like they might be posting a private key."), role: .destructive) {
                self.send_post()
            }
        })
    }
}

func uploadImage(mimeType: String, fileExtension: String, imageData: Data) async throws -> String {
    let url = URL(string: "https://nostr.build/upload.php")!
    let boundary = UUID().uuidString
    let paramName = "fileToUpload"
    let fileName = "file." + fileExtension
    
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

    var bodyData = Data()
    bodyData.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
    bodyData.append("Content-Disposition: form-data; name=\"\(paramName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
    bodyData.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
    bodyData.append(imageData)
    bodyData.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
    
    let response = try await URLSession.shared.upload(for: urlRequest, from: bodyData)
    guard let htmlString = String(data: response.0, encoding: .utf8) else { throw UploadError.invalidEncoding }
    
    let regex = /https:\/\/nostr\.build\/(?:i|av)\/nostr\.build_[a-z0-9]{64}\.[a-z0-9]+/
    guard let match = htmlString.firstMatch(of: regex) else { throw UploadError.notFoundUrl }
    
    return String(match.0)
}

enum UploadError: Error {
    case invalidEncoding
    case notFoundUrl
}

func get_searching_string(_ post: String) -> String? {
    guard let last_word = post.components(separatedBy: .whitespacesAndNewlines).last else {
        return nil
    }
    
    guard last_word.count >= 2 else {
        return nil
    }
    
    guard last_word.first! == "@" else {
        return nil
    }
    
    // don't include @npub... strings
    guard last_word.count != 64 else {
        return nil
    }
    
    return String(last_word.dropFirst())
}
