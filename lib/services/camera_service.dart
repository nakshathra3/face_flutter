import 'package:camera/camera.dart';

class CameraService {
  late CameraController controller;

  Future<void> initialize() async {
    final cameras = await availableCameras();
    final front = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
    );

    controller = CameraController(
      front,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await controller.initialize();
  }

  void dispose() {
    controller.dispose();
  }
}
