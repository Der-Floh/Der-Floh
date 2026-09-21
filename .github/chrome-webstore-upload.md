# Chrome Webstore Upload

Chrome Webstore Upload is the OAuth app my [shared CI](CI.md) uses to publish my browser extensions: it uploads new versions to the Chrome Web Store through the Chrome Web Store API and submits them for review. I am its only user, and it runs with my own Google account.

## Privacy policy

- The app asks for a single permission, access to the Chrome Web Store API (`https://www.googleapis.com/auth/chromewebstore`), which it uses to upload and publish the extensions of my own developer account.
- It reads no other Google data and no data of anyone else.
- Its credentials (client ID, client secret and refresh token) are kept as encrypted GitHub Actions secrets in my repositories and are only used by my workflows.
- It collects, stores, sells and shares no data. The API requests themselves are processed by Google.
- For questions, open an issue in this repository.

## Terms of service

- The app is for my own use only and offers no service to anyone else.
- It is provided as is, without warranty of any kind.
- Using the Chrome Web Store API is subject to Google's terms.
