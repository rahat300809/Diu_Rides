// File generated for DIU Ride Firebase integration
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyA_CampusDiuRideKey_DemoWeb99',
    appId: '1:108392193821:web:9102830192830192',
    messagingSenderId: '108392193821',
    projectId: 'diu-ride',
    authDomain: 'diu-ride.firebaseapp.com',
    storageBucket: 'diu-ride.appspot.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA_CampusDiuRideKey_DemoAndroid88',
    appId: '1:108392193821:android:3490283019283019',
    messagingSenderId: '108392193821',
    projectId: 'diu-ride',
    storageBucket: 'diu-ride.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyA_CampusDiuRideKey_DemoIos77',
    appId: '1:108392193821:ios:2390283019283019',
    messagingSenderId: '108392193821',
    projectId: 'diu-ride',
    storageBucket: 'diu-ride.appspot.com',
    iosBundleId: 'com.diu.ride.diuRide',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyA_CampusDiuRideKey_DemoMac66',
    appId: '1:108392193821:ios:2390283019283019',
    messagingSenderId: '108392193821',
    projectId: 'diu-ride',
    storageBucket: 'diu-ride.appspot.com',
    iosBundleId: 'com.diu.ride.diuRide',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyA_CampusDiuRideKey_DemoWin55',
    appId: '1:108392193821:web:9102830192830192',
    messagingSenderId: '108392193821',
    projectId: 'diu-ride',
    authDomain: 'diu-ride.firebaseapp.com',
    storageBucket: 'diu-ride.appspot.com',
  );
}
