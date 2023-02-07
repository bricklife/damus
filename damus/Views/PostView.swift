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
    @State var isUploading = false
    @State var uploadError: Error? = nil
    var isUploadingAlertPresented: Binding<Bool> {
        return Binding<Bool>(
            get: { self.uploadError != nil },
            set: { _ in self.uploadError = nil }
        )
    }
    
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
                .disabled(isUploading)

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
        .onAppear() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.focus = true
            }
        }
        .padding()
        .alert(NSLocalizedString("Note contains \"nsec1\" private key. Are you sure?", comment: "Alert user that they might be attempting to paste a private key and ask them to confirm."), isPresented: $showPrivateKeyWarning, actions: {
            Button(NSLocalizedString("No", comment: "Button to cancel out of posting a note after being alerted that it looks like they might be posting a private key."), role: .cancel) {
                showPrivateKeyWarning = false
            }
            Button(NSLocalizedString("Yes, Post with Private Key", comment: "Button to proceed with posting a note even though it looks like they might be posting a private key."), role: .destructive) {
                self.send_post()
            }
        })
        .task(id: selectedItem) {
            guard let newItem = selectedItem else { return }
            guard let type = newItem.supportedContentTypes.first else { return }
            guard let mimeType = type.preferredMIMEType else { return }
            guard let fileExtension = type.preferredFilenameExtension else { return }
            
            let uploadingText = "[uploading...]"
            
            do {
                guard let imageData = try await newItem.loadTransferable(type: Data.self) else {
                    print("No supported content type found.")
                    return
                }
                
                post += "\n\(uploadingText)"
                let url = try await MediaUploader.shared.upload(mimeType: mimeType, fileExtension: fileExtension, data: imageData)
                post = post.replacingOccurrences(of: uploadingText, with: url.absoluteString)
            } catch {
                uploadError = error
                post = post.replacingOccurrences(of: "\n\(uploadingText)", with: "")
            }
        }
        .onReceive(MediaUploader.shared.$isUploading) { isUploading in
            self.isUploading = isUploading
        }
        .alert(uploadError?.localizedDescription ?? "Error", isPresented: isUploadingAlertPresented) {}
    }
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
