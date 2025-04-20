import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class CameraService {
  CameraController? controller;
  CameraDescription? cameraDescription;
  CameraLensDirection cameraLensDirection = CameraLensDirection.front;
  
  Future<void> initialize(List<CameraDescription> cameras) async {
    if (cameras.isEmpty) return;
    
    cameraDescription = cameraLensDirection == CameraLensDirection.front 
        ? cameras.firstWhere((camera) => camera.lensDirection == CameraLensDirection.front)
        : cameras.firstWhere((camera) => camera.lensDirection == CameraLensDirection.back);
    
    controller = CameraController(
      cameraDescription!, 
      ResolutionPreset.medium,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21 
          : ImageFormatGroup.bgra8888,
      enableAudio: false
    );
    
    await controller!.initialize();
  }
  
  Future<void> startImageStream(Function(CameraImage) onImage) async {
    controller!.startImageStream(onImage);
  }
  
  Future<void> stopImageStream() async {
    if (controller != null && controller!.value.isStreamingImages) {
      await controller!.stopImageStream();
    }
  }
  
  void dispose() {
    controller?.dispose();
  }
  
  Future<void> toggleCameraDirection(List<CameraDescription> cameras) async {
    await stopImageStream();
    
    if (cameraLensDirection == CameraLensDirection.back) {
      cameraLensDirection = CameraLensDirection.front;
      cameraDescription = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
    } else {
      cameraLensDirection = CameraLensDirection.back;
      cameraDescription = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
    }
    
    controller = CameraController(
      cameraDescription!, 
      ResolutionPreset.medium,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21 
          : ImageFormatGroup.bgra8888,
      enableAudio: false
    );
    
    await controller!.initialize();
  }
  
  InputImage? getInputImage(CameraImage frame, List<CameraDescription> cameras) {
    final camera = cameraLensDirection == CameraLensDirection.front 
        ? cameras.firstWhere((camera) => camera.lensDirection == CameraLensDirection.front)
        : cameras.firstWhere((camera) => camera.lensDirection == CameraLensDirection.back);
    
    final sensorOrientation = camera.sensorOrientation;
    
    final _orientations = {
      DeviceOrientation.portraitUp: 0,
      DeviceOrientation.landscapeLeft: 90,
      DeviceOrientation.portraitDown: 180,
      DeviceOrientation.landscapeRight: 270,
    };

    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation = _orientations[controller!.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation = (sensorOrientation - rotationCompensation + 360) % 360;
      }
      
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(frame.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) return null;

    if (frame.planes.length != 1) return null;
    final plane = frame.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(frame.width.toDouble(), frame.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }
} 