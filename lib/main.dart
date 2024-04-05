import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'package:dio/dio.dart';

import 'package:devicelocale/devicelocale.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:upgrader/upgrader.dart';
import 'package:url_launcher/url_launcher.dart';

Future main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterDownloader.initialize(
      ignoreSsl: true,
      debug: true // optional: set false to disable printing logs to console
      );
  await Permission.storage.request();
  await Permission.camera.request();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  final GlobalKey webViewKey = GlobalKey();
  final ReceivePort _port = ReceivePort();
  InAppWebViewController? webView;
  List? languages;
  bool isLoading = true;

  @override
  void initState() {
    getCurrentLanguage();
    super.initState();
    IsolateNameServer.registerPortWithName(
        _port.sendPort, 'downloader_send_port');
    _port.listen((dynamic data) {
      print('data--${data}');
      String id = data[0];
      int status = data[1];
      int progress = data[2];

      setState(() {});
    });

    FlutterDownloader.registerCallback(downloadCallback);
  }

  getCurrentLanguage() async {
    languages = await Devicelocale.preferredLanguages;
    String? locale = await Devicelocale.currentLocale;
  }

  @override
  void dispose() {
    super.dispose();
    IsolateNameServer.removePortNameMapping('downloader_send_port');
  }

  static void downloadCallback(String id, status, int progress) {
    final SendPort send =
        IsolateNameServer.lookupPortByName('downloader_send_port')!;
    send.send([id, status, progress]);
  }

  @override
  Widget build(BuildContext context) {
    const appcastURL = 'https://community.verein.cloud/assets/appcast.xml';
    final upgrader = Upgrader(
        appcastConfig:
            AppcastConfiguration(url: appcastURL, supportedOS: ['android']));
    print("upgrader${upgrader.appcast}");
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: MaterialApp(
        supportedLocales: const <Locale>[
          Locale('de'),
          Locale('en'),
          Locale('es'),
          Locale('tr'),
          Locale('it'),
          Locale('sp'),
        ],
        home: WillPopScope(
          onWillPop: () async {
            // detect Android back button click
            final controller = webView;
            if (controller != null) {
              if (await controller.canGoBack()) {
                controller.goBack();
                return false;
              }
            }
            return true;
          },
          child: UpgradeAlert(
            onUpdate: () {
              if (Platform.isIOS) {
                launchUrl(Uri.parse(
                    "https://apps.apple.com/in/app/verein-cloud/id6447562632"));
              } else {
                launchUrl(Uri.parse(
                    "https://play.google.com/store/apps/details?id=com.verein.cloud"));
              }
              return true;
            },
            showLater: false,
            upgrader: upgrader,
            child: Scaffold(
              body: SafeArea(
                child: Stack(
                  children: [
                    InAppWebView(
                      key: webViewKey,
                      initialUrlRequest: URLRequest(
                        // url: Uri.tryParse('http://vcloud.mangoitsol.com/login'),
                        // url: Uri.parse('http://vcloud.mangoitsol.com/login'),
                        // url: Uri.tryParse(
                        // 'https://frontend.staging.verein.cloud/login'),
                        url: Uri.tryParse(
                            'https://community.verein.cloud/login'),
                        // url: WebUri('https://community.verein.cloud/login'),
                      ),
                      initialOptions: InAppWebViewGroupOptions(
                        crossPlatform: InAppWebViewOptions(
                          supportZoom: false,
                          useOnDownloadStart: true,
                        ),
                        ios: IOSInAppWebViewOptions(
                          allowsBackForwardNavigationGestures: true,
                        ),
                      ),
                      onWebViewCreated: (InAppWebViewController controller) {
                        webView = controller;
                      },
                      onDownloadStartRequest: (controller, url) async {
                        print('saveDir-------------------------');
                        var savedir = '';
                        if (Platform.isIOS) {
                          savedir =
                              (await getApplicationDocumentsDirectory()).path;
                        } else {
                          savedir = (await getExternalStorageDirectory())!.path;
                        }
                        print('saveDir${savedir}');
                        final taskId = await FlutterDownloader.enqueue(
                          url: url.url.toString().replaceAll('blob:', ''),
                          savedDir: savedir,
                          saveInPublicStorage: true,
                          showNotification: true,
                          // show download progress in status bar (for Android)
                          openFileFromNotification:
                              true, // click on notification to open downloaded file (for Android)
                        );
                      },
                      onLoadStart: (controller, url) {
                        if (url.toString().contains('login')) {
                          controller.evaluateJavascript(
                              source:
                                  "window.localStorage.setItem('language', '${languages![0].substring(0, 2)}')");
                        }
                      },
                      onLoadStop: (controller, url) {
                        setState(() {
                          isLoading = false;
                        });
                      },
                    ),
                    isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Color.fromRGBO(251, 95, 95, 1),
                            ),
                          )
                        : Stack(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
