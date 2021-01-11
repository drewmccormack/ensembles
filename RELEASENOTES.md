Release Notes
=============

NEXT
---
- Introduced custom value transformer for CDEPropertyValueChange to silence secure transformer warnings
- Added code to handle secure attribute transformers in user model

1.8
---
- Some fixes in multipeer file system
- Cleaned up a lot of warnings in latest Xcode

1.7.1
---
- Updated version of Dropbox v2
- Fixes for new security features in binary Core Data stores
- Better Carthage support

1.7
---
- Backported Dropbox v2 backend from Ensembles 2 (Dropbox is terminating the v1 API)
- Using ZipArchive project, which is actively developed, instead of SSZipArchive project

1.6.2
---
- Fixed memory issues related to new `NSError` autorelease behaviour
- Updated installation instructions in README
- Added a guard against `NSNull` values that could cause a crash

1.6.1
---
- Memory fixes for `NSError` propagation. The problems arose due to changes in `performBlock` methods, which now have an internal autorelease pool.

1.6
---
- Added a module target for iOS.
- Added the Simple Sync in Swift sample app.
- Added `dismantle` method, which can be called a `CDEPersistentStoreEnsemble` is no longer needed.
- Fixed a number of autoreleasing-NSError argument memory management issues.

1.5.2
---
- Improved notifications for file transfers in the multipeer backend

1.5.1
---
Minor changes.

1.5
---
Minor changes.

1.4.3
---
Minor changes.

1.4.2
---
- Added Quality of Service settings to all operation queues, to ensure they keep working even on mobile networks

1.4.1
---
- Minor changes to comments in code
- Updates to support Xcode 7 (including bitcode)

1.4
---
- If a save makes no changes to the persistent store, no event will be generated
- Mention Swift in the README


_Release Notes prior to 1.4 were not kept. The GitHub commit log can be used to see what changed in earlier releases._
