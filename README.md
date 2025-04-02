# Fleet Manager - Seafarer Connection App

An iOS app built with SwiftUI that connects seafarers who need crew replacements with those looking to join ships.

## Features

- **User Registration**: Sign up with name, email, contact info, fleet type, and rank
- **Status Management**: Track whether you're on a ship or on land
- **Ship Assignments**: When on a ship, record details including:
  - Date of onboarding
  - Rank
  - Ship name
  - Port of joining
  - Contract length
  - Contact details
  
- **Land Assignments**: When on land, record details including:
  - Date home
  - Expected joining date
  - Fleet type
  - Last vessel
  - Contact details
  
- **Matching System**: Connects seafarers based on:
  - Matching fleet types
  - Same rank requirements
  - Compatible timing (expected joining date matches expected release date)
  
- **Data Storage**: Data stored using SwiftData with CloudKit integration for syncing

## Implementation Notes

### Data Storage
- Primary storage is handled by SwiftData with CloudKit integration
- CloudKit private database is used for synchronization
- Fallback to memory-only storage if CloudKit integration fails

### Data Visibility
- Users control whether their assignments are public or private
- Public assignments are visible to potential matches
- Contact information is only shared for matched assignments

### CloudKit Requirements
This app follows CloudKit requirements for data models:
- All properties are optional or have default values
- Relationships have proper inverses
- No non-optional relationships
- Unique constraints handled properly for CloudKit

## Technical Details

- Built with SwiftUI and SwiftData
- Uses CloudKit for data synchronization
- Supports iOS 17.0+

## Getting Started

1. Register as a new user with your details
2. Update your status based on whether you're on a ship or on land
3. Browse matches in the Matches tab
4. Contact potential replacements directly from the app

## Setup for Development

1. Create an iCloud container identifier in your Apple Developer account matching your entitlements file
2. Ensure you have CloudKit enabled for your app in your Apple Developer account
3. If using a physical device, sign in to iCloud for full functionality 

# Fleet Manager - Firebase Setup

This application uses Firebase for authentication, data storage, and real-time synchronization. Follow these steps to set up Firebase for the project:

## Setting Up Firebase

1. Create a Firebase project at [firebase.google.com](https://firebase.google.com/)
2. Add an iOS app to your Firebase project
   - Use the bundle ID `com.drm.fleetmanager` or update the bundle ID in the project settings
   - Download the `GoogleService-Info.plist` file

3. Add the `GoogleService-Info.plist` file to your project:
   - Drag the file into your Xcode project
   - Make sure to check "Copy items if needed"
   - Add to the "Fleet Manager" target

4. Install CocoaPods if not already installed:
   ```
   sudo gem install cocoapods
   ```

5. Run pod install in the project directory:
   ```
   pod install
   ```

6. Open the `.xcworkspace` file instead of the `.xcodeproj` file

7. Configure Firebase Services:
   - Enable Authentication with Email/Password sign-in in the Firebase console
   - Create a Firestore database in the Firebase console
   - Set up the security rules for your Firestore database

## Firestore Database Structure

The app uses the following Firestore collections:

- `users`: Stores user profile information
- `shipAssignments`: Stores ship assignment details
- `landAssignments`: Stores land assignment details

## Security Rules

Add these basic security rules to your Firestore database:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
      allow read: if request.auth != null;
    }
    
    match /shipAssignments/{document=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.resource.data.userId == request.auth.uid;
    }
    
    match /landAssignments/{document=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.resource.data.userId == request.auth.uid;
    }
  }
}
```

## Additional Setup

If you're using Firebase Storage, make sure to:
1. Enable Firebase Storage in the Firebase console
2. Configure the storage security rules

## Questions?

Contact the development team for additional support. 