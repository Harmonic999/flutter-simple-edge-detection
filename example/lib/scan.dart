import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter_exif_rotation/flutter_exif_rotation.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:simple_edge_detection/edge_detection.dart';
import 'package:flutter/material.dart';
import 'package:simple_edge_detection_example/cropping_preview.dart';

import 'camera_view.dart';
import 'edge_detector.dart';
import 'image_view.dart';

class Scan extends StatefulWidget {
  @override
  _ScanState createState() => _ScanState();
}

class _ScanState extends State<Scan> {
  CameraController? controller;
  late List<CameraDescription> cameras;
  String? imagePath;
  String? croppedImagePath;
  EdgeDetectionResult? edgeDetectionResult;

  @override
  void initState() {
    super.initState();
    checkForCameras().then((value) {
      _initializeController();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: <Widget>[
          _getMainWidget(),
          _getBottomBar(),
        ],
      ),
    );
  }

  Widget _getMainWidget() {
    if (croppedImagePath != null) {
      return ImageView(imagePath: croppedImagePath!);
    }

    if (imagePath == null && edgeDetectionResult == null) {
      final mediaSize = MediaQuery.of(context).size;
      final scale = 1 / (controller!.value.aspectRatio * mediaSize.aspectRatio);
      return ClipRect(
        clipper: _MediaSizeClipper(mediaSize),
        child: Transform.scale(
          scale: scale,
          alignment: Alignment.topCenter,
          child: CameraPreview(controller!),
        ),
      );
    }

    return ImagePreview(
      imagePath: imagePath!,
      edgeDetectionResult: edgeDetectionResult,
    );
  }

  Future<void> checkForCameras() async {
    cameras = await availableCameras();
  }

  void _initializeController() {
    checkForCameras();
    if (cameras.length == 0) {
      log('No cameras detected');
      return;
    }

    controller = CameraController(cameras[0], ResolutionPreset.max, enableAudio: false);
    controller!.initialize().then((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  Widget _getButtonRow() {
    if (imagePath != null) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FloatingActionButton(
              child: Icon(Icons.check),
              onPressed: () {
                if (croppedImagePath == null) {
                  _processImage(imagePath!, edgeDetectionResult!);
                  print('hello world!');
                  return;
                }

                setState(() {
                  imagePath = null;
                  edgeDetectionResult = null;
                  croppedImagePath = null;
                });
              },
            ),
            if (croppedImagePath != null) Container(width: 16.0, height: 0.0),
            if (croppedImagePath != null)
              FloatingActionButton(
                child: Icon(Icons.info_outline),
                onPressed: getTexts,
              ),
          ],
        ),
      );
    }

    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      FloatingActionButton(
        foregroundColor: Colors.white,
        child: Icon(Icons.camera_alt),
        onPressed: onTakePictureButtonPressed,
      ),
      SizedBox(width: 16),
    ]);
  }

  Future<void> getTexts() async {
    final textDetector = GoogleMlKit.vision.textDetector();
    File imageFile = File(croppedImagePath!);
    if (Platform.isIOS) {
      imageFile = await FlutterExifRotation.rotateImage(path: imageFile.path);
    }

    final result = await textDetector.processImage(InputImage.fromFilePath(imageFile.path));

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 56.0),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: EdgeInsets.all(16.0),
                color: Colors.white,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: result.blocks
                      .map(
                        (b) => Padding(
                          padding: EdgeInsets.all(6.0),
                          child: Row(
                            children: [
                              Container(
                                color: Colors.black,
                                child: Row(
                                  children: [
                                    Text(
                                      b.text,
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String timestamp() => DateTime.now().millisecondsSinceEpoch.toString();

  Future<String?> takePicture() async {
    if (!controller!.value.isInitialized) {
      log('Error: select a camera first.');
      return null;
    }

    if (controller!.value.isTakingPicture) {
      return null;
    }

    XFile file;

    try {
      file = await controller!.takePicture();
    } on CameraException catch (e) {
      log(e.toString());
      return null;
    }
    return file.path;
  }

  Future _detectEdges(String filePath) async {
    if (!mounted || filePath == null) {
      return;
    }

    setState(() {
      imagePath = filePath;
    });

    EdgeDetectionResult result = await EdgeDetector().detectEdges(filePath);

    setState(() {
      edgeDetectionResult = result;
    });
  }

  Future _processImage(String filePath, EdgeDetectionResult edgeDetectionResult) async {
    if (!mounted || filePath == null) {
      return;
    }

    bool result = await EdgeDetector().processImage(filePath, edgeDetectionResult);

    if (result == false) {
      return;
    }

    setState(() {
      imageCache?.clearLiveImages();
      imageCache?.clear();
      croppedImagePath = imagePath;
    });
  }

  void onTakePictureButtonPressed() async {
    String? filePath = await takePicture();

    log('Picture saved to $filePath');

    await _detectEdges(filePath!);
  }

  Padding _getBottomBar() {
    return Padding(
        padding: EdgeInsets.only(bottom: 56.0),
        child: Align(alignment: Alignment.bottomCenter, child: _getButtonRow()));
  }
}

class _MediaSizeClipper extends CustomClipper<Rect> {
  final Size mediaSize;

  const _MediaSizeClipper(this.mediaSize);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, mediaSize.width, mediaSize.height);
  }

  @override
  bool shouldReclip(CustomClipper<Rect> oldClipper) {
    return true;
  }
}
