xcodebuild archive -scheme iOS -destination "generic/platform=iOS" -archivePath ../../artifacts/CitadelKit-iOS SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES &&
  xcodebuild archive -scheme iOS -destination "generic/platform=iOS Simulator" -archivePath ../../artifacts/CitadelKit-iOS-Sim SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES VALID_ARCHS=x86_64 &&
  xcodebuild archive -scheme macOS -destination "generic/platform=macOS" -archivePath ../../artifacts/CitadelKit-macOS SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES VALID_ARCHS=x86_64 &&
  cd ../../artifacts &&
  rm -rf ./CitadelKit.xcframework &&
  xcodebuild -create-xcframework -framework CitadelKit-iOS.xcarchive/Products/Library/Frameworks/CitadelKit.framework \
             -framework CitadelKit-iOS-Sim.xcarchive/Products/Library/Frameworks/CitadelKit.framework \
             -framework CitadelKit-macOS.xcarchive/Products/Library/Frameworks/CitadelKit.framework \
             -output ./CitadelKit.xcframework
